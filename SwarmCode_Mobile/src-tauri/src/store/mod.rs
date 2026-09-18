// =============================================================================
// SwarmAI Mobile — Persistent Local Store
// =============================================================================
//
// JSON-backed store for: saved pairings (host/port/displayName/token), recent
// threads, queued offline messages. The store is owned by `MobileBridgeClient`
// and exposed to commands via `State<'_, Arc<RwLock<MobileStore>>>`.

use chrono::{DateTime, Utc};
#[cfg(any(target_os = "ios", target_os = "android"))]
use std::sync::{Mutex, PoisonError};
#[cfg(not(any(target_os = "ios", target_os = "android")))]
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

use crate::models::BridgeThreadSummary;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedPairing {
    pub id: Uuid,
    pub host: String,
    pub port: u16,
    pub name: String,
    pub token: String,
    pub last_connected: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedMessage {
    pub id: Uuid,
    pub thread_id: Uuid,
    pub content: String,
    pub queued_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionInfo {
    pub host: String,
    pub port: u16,
    pub status: ConnectionStatus,
    pub last_connected: Option<DateTime<Utc>>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Paired,
    Reconnecting,
    Failed,
}

pub struct MobileStore {
    pub data_dir: PathBuf,
    pub pairings: Mutex<Vec<SavedPairing>>,
    pub thread_cache: Mutex<Vec<BridgeThreadSummary>>,
    pub message_queue: Mutex<Vec<QueuedMessage>>,
    pub connection: Mutex<ConnectionInfo>,
}

impl MobileStore {
    pub fn new() -> Self {
        let data_dir = std::env::var("SWARMAI_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                home_dir().join(".swarmai/mobile")
            });

        std::fs::create_dir_all(&data_dir).ok();

        Self {
            data_dir,
            pairings: Mutex::new(Vec::new()),
            thread_cache: Mutex::new(Vec::new()),
            message_queue: Mutex::new(Vec::new()),
            connection: Mutex::new(ConnectionInfo {
                host: String::new(),
                port: 8765,
                status: ConnectionStatus::Disconnected,
                last_connected: None,
                error: None,
            }),
        }
    }

    #[cfg(target_os = "android")]
    fn lock<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
        mutex.lock().unwrap_or_else(PoisonError::into_inner)
    }

    #[cfg(not(target_os = "android"))]
    fn lock<T>(mutex: &Mutex<T>) -> parking_lot::MutexGuard<'_, T> {
        mutex.lock()
    }

    pub fn save_pairing(&self, p: SavedPairing) {
        let mut pairings = Self::lock(&self.pairings);
        pairings.retain(|existing| existing.host != p.host || existing.port != p.port);
        pairings.push(p);
        self.persist_pairings(&pairings);
    }

    pub fn remove_pairing(&self, id: Uuid) {
        let mut pairings = Self::lock(&self.pairings);
        pairings.retain(|p| p.id != id);
        self.persist_pairings(&pairings);
    }

    pub fn cache_threads(&self, threads: Vec<BridgeThreadSummary>) {
        let mut cache = Self::lock(&self.thread_cache);
        *cache = threads;
    }

    pub fn queue_message(&self, msg: QueuedMessage) {
        Self::lock(&self.message_queue).push(msg);
    }

    pub fn drain_queue(&self) -> Vec<QueuedMessage> {
        let mut queue = Self::lock(&self.message_queue);
        std::mem::take(&mut *queue)
    }

    fn persist_pairings(&self, pairings: &[SavedPairing]) {
        let path = self.data_dir.join("pairings.json");
        if let Ok(json) = serde_json::to_string_pretty(pairings) {
            let _ = std::fs::write(path, json);
        }
    }

    pub fn load_persisted(&self) {
        let path = self.data_dir.join("pairings.json");
        if let Ok(bytes) = std::fs::read(&path) {
            if let Ok(parsed) = serde_json::from_slice::<Vec<SavedPairing>>(&bytes) {
                *Self::lock(&self.pairings) = parsed;
            }
        }
    }

    pub fn get_connection_info(&self) -> ConnectionInfo {
        let conn = Self::lock(&self.connection);
        ConnectionInfo {
            host: conn.host.clone(),
            port: conn.port,
            status: conn.status,
            last_connected: conn.last_connected,
            error: conn.error.clone(),
        }
    }

    pub fn get_status(&self) -> ConnectionStatus {
        Self::lock(&self.connection).status
    }

    pub fn get_pairings(&self) -> Vec<SavedPairing> {
        Self::lock(&self.pairings).clone()
    }

    pub fn set_disconnected(&self) {
        let mut conn = Self::lock(&self.connection);
        conn.status = ConnectionStatus::Disconnected;
    }

    pub fn set_connection_status(&self, status: ConnectionStatus, error: Option<String>) {
        let mut conn = Self::lock(&self.connection);
        conn.status = status;
        conn.error = error;
    }
}

pub fn init_store() {
    tracing::debug!("MobileStore: initialized");
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}
