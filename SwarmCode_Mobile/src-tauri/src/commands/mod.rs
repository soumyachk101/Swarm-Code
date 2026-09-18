use std::sync::Arc;
use tokio::sync::RwLock;
use tauri::State;
use uuid::Uuid;

use crate::bridge::MobileBridgeClient;
use crate::models::{
    BridgeApproval, BridgeModels, BridgeStatus, BridgeThreadDetail, BridgeThreadSummary,
};
use crate::store::{ConnectionStatus, MobileStore, SavedPairing};

// ---- Connection ----

#[tauri::command]
pub async fn pair_with_code(
    code: String,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<(), String> {
    bridge.pair_with_code(code).await;
    Ok(())
}

#[tauri::command]
pub async fn get_connection_status(
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<ConnectionStatus, String> {
    let store = state.read().await;
    Ok(store.get_status())
}

#[tauri::command]
pub async fn connect_to_bridge(
    host: String,
    port: u16,
    state: State<'_, Arc<RwLock<MobileStore>>>,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<String, String> {
    let h = host.clone();
    bridge.connect(host.clone(), port).await?;
    {
        let store = state.read().await;
        store.save_pairing(SavedPairing {
            id: Uuid::new_v4(),
            host: h.clone(),
            port,
            name: format!("SwarmAI ({})", h),
            token: String::new(),
            last_connected: Some(chrono::Utc::now()),
        });
    }
    Ok(format!("Connected to {}:{}", h, port))
}

#[tauri::command]
pub async fn disconnect_bridge(
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<(), String> {
    let store = state.read().await;
    store.set_disconnected();
    Ok(())
}

#[tauri::command]
pub async fn discover_bridges(
    bridge: State<'_, MobileBridgeClient>,
) -> Result<Vec<SavedPairing>, String> {
    let found = MobileBridgeClient::discover_services().await;
    Ok(found)
}

// ---- Pairing ----

#[tauri::command]
pub async fn save_pairing(
    pairing: SavedPairing,
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<SavedPairing, String> {
    let store = state.read().await;
    store.save_pairing(pairing.clone());
    Ok(pairing)
}

#[tauri::command]
pub async fn get_saved_pairings(
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<Vec<SavedPairing>, String> {
    let store = state.read().await;
    Ok(store.get_pairings())
}

#[tauri::command]
pub async fn delete_pairing(
    id: String,
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let store = state.read().await;
    store.remove_pairing(uuid);
    Ok(())
}

// ---- Threads ----

#[tauri::command]
pub async fn get_threads(
    host: Option<String>,
    port: Option<u16>,
    state: State<'_, Arc<RwLock<MobileStore>>>,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<Vec<BridgeThreadSummary>, String> {
    let info = {
        let store = state.read().await;
        store.get_connection_info()
    };
    let h = host.unwrap_or(info.host);
    let p = port.unwrap_or(info.port);

    if h.is_empty() {
        return Ok(Vec::new());
    }

    bridge.fetch_threads(&h, p).await
}

#[tauri::command]
pub async fn get_thread_detail(
    thread_id: String,
    host: Option<String>,
    port: Option<u16>,
    state: State<'_, Arc<RwLock<MobileStore>>>,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<BridgeThreadDetail, String> {
    let uuid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
    let info = {
        let store = state.read().await;
        store.get_connection_info()
    };
    let h = host.unwrap_or(info.host);
    let p = port.unwrap_or(info.port);

    bridge.fetch_thread_detail(&h, p, uuid).await
}

// ---- Actions ----

#[tauri::command]
pub async fn send_message(
    thread_id: String,
    content: String,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
    bridge
        .send_event(crate::models::BridgeEvent::SendMessage {
            threadID: uuid,
            content,
        })
        .await
}

#[tauri::command]
pub async fn approve_action(
    thread_id: String,
    action_id: String,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
    bridge
        .send_event(crate::models::BridgeEvent::Approve {
            threadID: uuid,
            actionID: action_id,
        })
        .await
}

#[tauri::command]
pub async fn reject_action(
    thread_id: String,
    action_id: String,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
    bridge
        .send_event(crate::models::BridgeEvent::Reject {
            threadID: uuid,
            actionID: action_id,
        })
        .await
}

#[tauri::command]
pub async fn create_thread(
    project_id: Option<String>,
    prompt: String,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<(), String> {
    let pid = project_id
        .and_then(|s| Uuid::parse_str(&s).ok())
        .unwrap_or_else(Uuid::new_v4);
    bridge
        .send_event(crate::models::BridgeEvent::CreateThread { projectID: pid, prompt })
        .await
}

#[tauri::command]
pub async fn get_models(
    host: Option<String>,
    port: Option<u16>,
    state: State<'_, Arc<RwLock<MobileStore>>>,
    bridge: State<'_, MobileBridgeClient>,
) -> Result<BridgeModels, String> {
    let info = {
        let store = state.read().await;
        store.get_connection_info()
    };
    let h = host.unwrap_or(info.host);
    let p = port.unwrap_or(info.port);

    if h.is_empty() {
        return Ok(BridgeModels { providers: std::collections::HashMap::new() });
    }

    bridge.fetch_models(&h, p).await
}

#[tauri::command]
pub async fn get_git_status(
    thread_id: String,
    host: Option<String>,
    port: Option<u16>,
    state: State<'_, Arc<RwLock<MobileStore>>>,
) -> Result<String, String> {
    let info = {
        let store = state.read().await;
        store.get_connection_info()
    };
    let h = host.unwrap_or(info.host);
    let p = port.unwrap_or(info.port);

    if h.is_empty() {
        return Ok("{}".to_string());
    }

    let url = format!(
        "http://{}:{}/api/v1/git/status?thread_id={}",
        h, p, thread_id
    );

    let client = reqwest::Client::new();
    let resp = client.get(&url).timeout(std::time::Duration::from_secs(10)).send().await;
    match resp {
        Ok(r) if r.status().is_success() => r.text().await.map_err(|e| e.to_string()),
        Ok(r) => Err(format!("HTTP {}", r.status())),
        Err(e) => Err(e.to_string()),
    }
}
