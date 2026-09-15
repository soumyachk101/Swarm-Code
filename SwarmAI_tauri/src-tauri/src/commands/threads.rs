use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use tauri::State;

use crate::models::thread::ChatThread;
use crate::models::provider::{ProviderKind, RuntimeMode};
use crate::models::timeline::{ThreadDocument, ContextUsage};
use crate::store::AppStore;

#[tauri::command]
pub async fn create_thread(
 project_id: String,
 provider: ProviderKind,
 model: Option<String>,
 effort: Option<String>,
 runtime_mode: RuntimeMode,
 fast_mode: bool,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ChatThread, String> {
 let mut store = state.write().await;
 let pid_uuid = Uuid::parse_str(&project_id).map_err(|e| e.to_string())?;
 let thread = ChatThread::new(pid_uuid, provider, model.clone(), effort.clone(), runtime_mode, fast_mode);
 store.library.threads.push(thread.clone());
 store.save();
 Ok(thread)
}

#[tauri::command]
pub async fn get_threads(
 project_id: Option<String>,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<ChatThread>, String> {
 let store = state.read().await;
 if let Some(pid) = project_id {
 let pid_uuid = Uuid::parse_str(&pid).ok();
 Ok(store
 .library
 .threads
 .iter()
 .filter(|t| pid_uuid.map(|p| t.project_id == p).unwrap_or(false))
 .cloned()
 .collect())
 } else {
 Ok(store.library.threads.clone())
 }
}

#[tauri::command]
pub async fn get_thread(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ChatThread, String> {
 let store = state.read().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .cloned()
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))
}

#[tauri::command]
pub async fn delete_thread(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let count_before = store.library.threads.len();
 store.library.threads.retain(|t| t.id != tid);
 if store.library.threads.len() == count_before {
 return Err(format!("Thread '{}' not found", thread_id));
 }
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn update_thread_title(
 thread_id: String,
 title: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let thread = store
 .library
 .threads
 .iter_mut()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 thread.title = title;
 thread.updated_at = chrono::Utc::now();
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn search_threads(
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

#[tauri::command]
pub async fn get_recent_threads(
 limit: usize,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<ChatThread>, String> {
 let store = state.read().await;
 let mut threads: Vec<ChatThread> = store.library.threads.clone();
 threads.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
 threads.truncate(limit);
 Ok(threads)
}

#[tauri::command]
pub async fn get_thread_document(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ThreadDocument, String> {
 let store = state.read().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let thread = store
 .library
 .threads
 .iter()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 Ok(ThreadDocument {
 thread_id: thread.id,
 items: vec![],
 turns: vec![],
 usage: Some(ContextUsage {
 used_tokens: 0,
 window_tokens: None,
 }),
 follow_ups: vec![],
 })
}

#[tauri::command]
pub async fn pin_thread(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let thread = store
 .library
 .threads
 .iter_mut()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 thread.is_pinned = true;
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn unpin_thread(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let thread = store
 .library
 .threads
 .iter_mut()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 thread.is_pinned = false;
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn archive_thread(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let thread = store
 .library
 .threads
 .iter_mut()
 .find(|t| t.id == tid)
 .ok_or_else(|| format!("Thread '{}' not found", thread_id))?;
 thread.is_archived = true;
 store.save();
 Ok(())
}
