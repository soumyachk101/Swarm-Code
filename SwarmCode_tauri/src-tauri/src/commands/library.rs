use std::sync::Arc;
use tokio::sync::RwLock;

use tauri::State;

use crate::models::thread::ChatThread;
use crate::store::AppStore;

#[tauri::command]
pub async fn get_library_items(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<ChatThread>, String> {
 let store = state.read().await;
 Ok(store.library.threads.clone())
}

#[tauri::command]
pub async fn save_library_item(
 item: ChatThread,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ChatThread, String> {
 let mut store = state.write().await;
 if let Some(existing) = store.library.threads.iter_mut().find(|t| t.id == item.id) {
 *existing = item.clone();
 } else {
 store.library.threads.push(item.clone());
 }
 store.save();
 Ok(item)
}

#[tauri::command]
pub async fn delete_library_item(
 id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
 let count_before = store.library.threads.len();
 store.library.threads.retain(|t| t.id != tid);
 if store.library.threads.len() == count_before {
 return Err(format!("Thread '{}' not found", id));
 }
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn search_library(
 query: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<ChatThread>, String> {
 let store = state.read().await;
 let q = query.to_lowercase();
 if q.is_empty() {
 return Ok(store.library.threads.clone());
 }
 let results: Vec<ChatThread> = store
 .library
 .threads
 .iter()
 .filter(|t| {
 t.title.to_lowercase().contains(&q)
 || t.provider.to_string().to_lowercase().contains(&q)
 || t.model
 .as_ref()
 .map(|m| m.to_lowercase().contains(&q))
 .unwrap_or(false)
 })
 .cloned()
 .collect();
 Ok(results)
}
