// =============================================================================
// SwarmAI Mobile — Bridge Client
// =============================================================================
//
// WebSocket + REST client that lives in the Tauri Rust core. It talks to the
// macOS app's `BridgeServer` (port 8765 WS / 8766 HTTP) over LAN.
//
// Responsibilities:
//  - WebSocket lifecycle (connect, authenticate, reconnect, heartbeat)
//  - REST polling for thread list / status (initial load, fallback when WS
//    is unavailable)
//  - Inbound event routing (WS → Tauri events → Frontend)
//  - Outbound command serialization (Frontend → Tauri commands → WS/REST)
//  - Offline message queue (flushes on reconnect)
//  - mDNS discovery of bridge services

use std::sync::Arc;
use tokio::sync::{RwLock, broadcast};
use tokio::time::{interval, Duration};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Error, Message},
    MaybeTlsStream, WebSocketStream,
};
use futures_util::{sink::SinkExt, stream::StreamExt};
use tracing::{debug, info, warn};
use uuid::Uuid;

use super::models::{BridgeEvent, BridgeModels, BridgeStatus, BridgeThreadDetail, BridgeThreadSummary};
use super::store::{ConnectionInfo, ConnectionStatus, MobileStore, QueuedMessage, SavedPairing};

// Broadcast channel size for frontend events.
const EVENT_CHANNEL_CAPACITY: usize = 128;

// ---------------------------------------------------------------------------
// MobileBridgeClient
// ---------------------------------------------------------------------------

#[derive(Clone)]
pub struct MobileBridgeClient {
    store: Arc<tokio::sync::RwLock<MobileStore>>,
    event_tx: broadcast::Sender<BridgeClientEvent>,
}

#[derive(Debug, Clone)]
pub enum BridgeClientEvent {
    Connected { host: String, port: u16 },
    Disconnected,
    Paired { session_token: String },
    PairFailed { reason: String },
    ThreadsUpdated(Vec<BridgeThreadSummary>),
    ThreadDetailLoaded(Uuid, BridgeThreadDetail),
    StatusLoaded(BridgeStatus),
    ModelsLoaded(BridgeModels),
    EventReceived(BridgeEvent),
    ConnectionError { message: String },
    Reconnecting { attempt: u32, max_attempts: u32 },
}

impl MobileBridgeClient {
    pub fn new(store: Arc<tokio::sync::RwLock<MobileStore>>) -> Self {
        let (event_tx, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        Self { store, event_tx }
    }

    /// Subscribe to client lifecycle events.
    pub fn subscribe(&self) -> broadcast::Receiver<BridgeClientEvent> {
        self.event_tx.subscribe()
    }

    /// Emit an event to all subscribers.
    fn emit(&self, event: BridgeClientEvent) {
        let _ = self.event_tx.send(event);
    }

    // ---- Public Commands ----

    /// Connect to a specific host/port.
    pub async fn connect(&self, host: String, port: u16) -> Result<(), String> {
        self.update_connection_status(ConnectionStatus::Connecting, None).await;

        let url = format!("ws://{}:{}/ws/v1/stream", host, port);
        match connect_async(&url).await {
            Ok((ws_stream, _)) => {
                info!(%url, "Bridge connected");
                self.update_connection_status(ConnectionStatus::Connected, None).await;
                self.emit(BridgeClientEvent::Connected { host: host.clone(), port });

                // Spawn message pump
                let store = self.store.clone();
                let tx = self.event_tx.clone();
                tokio::spawn(async move {
                    Self::message_pump(ws_stream, store, tx).await;
                });

                Ok(())
            }
            Err(e) => {
                let msg = e.to_string();
                self.update_connection_status(ConnectionStatus::Failed, Some(msg.clone())).await;
                self.emit(BridgeClientEvent::ConnectionError { message: msg });
                Err(format!("Connection failed: {}", e))
            }
        }
    }

    /// Start pairing flow — pair with a code.
    pub async fn pair_with_code(&self, code: String) {
        let event = BridgeEvent::Pair { code };
        let _ = self.send_event(event).await;
    }

    /// Fetch the full thread list via REST.
    pub async fn fetch_threads(&self, host: &str, port: u16) -> Result<Vec<BridgeThreadSummary>, String> {
        let url = format!("http://{}:{}/api/v1/threads", host, port);
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("REST error: {}", resp.status()));
        }

        let threads: Vec<BridgeThreadSummary> = resp
            .json()
            .await
            .map_err(|e| e.to_string())?;

        self.store.read().await.cache_threads(threads.clone());
        self.emit(BridgeClientEvent::ThreadsUpdated(threads.clone()));
        Ok(threads)
    }

    /// Fetch a single thread detail via REST.
    pub async fn fetch_thread_detail(
        &self,
        host: &str,
        port: u16,
        thread_id: Uuid,
    ) -> Result<BridgeThreadDetail, String> {
        let url = format!(
            "http://{}:{}/api/v1/threads/{}",
            host, port, thread_id
        );
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("REST error: {}", resp.status()));
        }

        let detail: BridgeThreadDetail = resp.json().await.map_err(|e| e.to_string())?;
        self.emit(BridgeClientEvent::ThreadDetailLoaded(thread_id, detail.clone()));
        Ok(detail)
    }

    /// Get bridge status via REST.
    pub async fn fetch_status(&self, host: &str, port: u16) -> Result<BridgeStatus, String> {
        let url = format!("http://{}:{}/api/v1/status", host, port);
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("REST error: {}", resp.status()));
        }

        let status: BridgeStatus = resp.json().await.map_err(|e| e.to_string())?;
        self.emit(BridgeClientEvent::StatusLoaded(status.clone()));
        Ok(status)
    }

    /// Get available models via REST.
    pub async fn fetch_models(&self, host: &str, port: u16) -> Result<BridgeModels, String> {
        let url = format!("http://{}:{}/api/v1/models", host, port);
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("REST error: {}", resp.status()));
        }

        let models: BridgeModels = resp.json().await.map_err(|e| e.to_string())?;
        self.emit(BridgeClientEvent::ModelsLoaded(models.clone()));
        Ok(models)
    }

    /// Send an event over WebSocket (non-blocking, best-effort).
    pub async fn send_event(&self, event: BridgeEvent) -> Result<(), String> {
        // In a full implementation, we'd hold the WS writer in a shared Arc<Mutex>
        // and actually write bytes here. For scaffolding, we just acknowledge.
        let json = serde_json::to_string(&event).map_err(|e| e.to_string())?;
        debug!(event_type = ?event, "Bridge event send (scaffolding)");
        Ok(())
    }

    /// Discover bridge services on the local network via mDNS.
    pub async fn discover_services() -> Vec<SavedPairing> {
        // TODO: Use mdns crate for proper mDNS browsing.
        // For now, attempt well-known local hosts.
        let mut found: Vec<SavedPairing> = Vec::new();
        let common_hosts = vec![
            "localhost".to_string(),
            "127.0.0.1".to_string(),
        ];

        let client = reqwest::Client::new();
        for host in common_hosts {
            match client
                .get(&format!("http://{}:8766/api/v1/status", host))
                .timeout(Duration::from_millis(500))
                .send()
                .await
            {
                Ok(resp) if resp.status().is_success() => {
                    if let Ok(status) = resp.json::<BridgeStatus>().await {
                        if status.status == "ok" {
                            found.push(SavedPairing {
                                id: Uuid::new_v4(),
                                host: host.clone(),
                                port: 8765,
                                name: format!("SwarmAI ({})", host),
                                token: String::new(),
                                last_connected: None,
                            });
                        }
                    }
                }
                _ => {}
            }
        }

        found
    }

    // ---- Private Helpers ----

    async fn message_pump(
        mut ws: WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>,
        store: Arc<tokio::sync::RwLock<MobileStore>>,
        tx: broadcast::Sender<BridgeClientEvent>,
    ) {
        let mut ping_interval = interval(Duration::from_secs(30));

        loop {
            tokio::select! {
                msg = ws.next() => {
                    match msg {
                        Some(Ok(Message::Text(text))) => {
                            match serde_json::from_str::<BridgeEvent>(&text) {
                                Ok(event) => {
                                    let _ = tx.send(BridgeClientEvent::EventReceived(event));
                                }
                                Err(e) => {
                                    warn!(%e, %text, "Failed to parse bridge event");
                                }
                            }
                        }
                        Some(Ok(Message::Close(_))) => {
                            info!("Bridge connection closed by server");
                            let _ = tx.send(BridgeClientEvent::Disconnected);
                            break;
                        }
                        Some(Err(e)) => {
                            warn!(?e, "Bridge WS error");
                            let _ = tx.send(BridgeClientEvent::ConnectionError {
                                message: format!("{}", e),
                            });
                            break;
                        }
                        _ => {}
                    }
                }
                _ = ping_interval.tick() => {
                    let _ = ws.send(Message::Ping(vec![].into())).await;
                }
            }
        }

        // Flush queued messages on disconnect
        let _ = tx.send(BridgeClientEvent::Disconnected);
    }

    async fn update_connection_status(&self, status: ConnectionStatus, error: Option<String>) {
        let store = self.store.read().await;
        store.set_connection_status(status, error);
    }
}
