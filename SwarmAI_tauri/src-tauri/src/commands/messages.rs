use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use tauri::State;

use crate::types::MessageOptions;
use crate::models::timeline::{TimelineItem, TimelineContent, UserMessage};
use crate::store::AppStore;

#[tauri::command]
pub async fn send_message(
 thread_id: String,
 content: String,
 options: MessageOptions,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<TimelineItem, String> {
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let store = state.read().await;

 let thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;

 let user_msg = UserMessage {
 text: content,
 attachments: options
 .attachments
 .into_iter()
 .map(|a| crate::models::timeline::Attachment {
 id: Uuid::parse_str(&a.id).unwrap_or_else(|_| Uuid::new_v4()),
 name: a.name,
 path: a.path,
 mime_type: a.mime_type,
 })
 .collect(),
 hydra_heads: None,
 };

 let item = TimelineItem {
 id: crate::support::id::next_id(),
 turn_id: None,
 date: chrono::Utc::now(),
 content: TimelineContent::User(user_msg),
 };

 drop(store);

 let mut store = state.write().await;
 // Update thread timestamp
 if let Some(t) = store.library.threads.iter_mut().find(|t| t.id == tid) {
 t.updated_at = chrono::Utc::now();
 }
 store.save();

 Ok(item)
}

#[tauri::command]
pub async fn get_messages(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<TimelineItem>, String> {
 let store = state.read().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let _thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 Ok(vec![])
}

#[tauri::command]
pub async fn regenerate_message(
 thread_id: String,
 message_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<TimelineItem, String> {
 let store = state.read().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let _thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 drop(store);
 Err("Regeneration requires an active provider session".to_string())
}

#[tauri::command]
pub async fn delete_message(
 thread_id: String,
 message_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let store = state.read().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let _thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 drop(store);
 let mut store = state.write().await;
 if let Some(t) = store.library.threads.iter_mut().find(|t| t.id == tid) {
 t.updated_at = chrono::Utc::now();
 }
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn stop_generation(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let store = state.read().await;
 let _thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 drop(store);
 // Signal generation stop by updating thread status
 let mut store = state.write().await;
 if let Some(t) = store.library.threads.iter_mut().find(|t| t.id == tid) {
 t.updated_at = chrono::Utc::now();
 t.last_status = Some("stopped".to_string());
 }
 store.save();
 Ok(())
}
