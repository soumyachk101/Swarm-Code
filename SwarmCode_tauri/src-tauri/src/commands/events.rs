use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::Utc;
use uuid::Uuid;

use tauri::Emitter;

use crate::types::{MessageChunk, ChunkContent, TerminalStream, ThreadUpdate};
use crate::store::AppStore;

// ---------------------------------------------------------------------------
// emit_message_chunk
//
// Called by the streaming provider runtime each time a new chunk of text or a
// reasoning block or a tool event arrives. The frontend receives this as a
// Tauri event and appends it to the active timeline row.
// ---------------------------------------------------------------------------

#[tauri::command]
pub async fn emit_message_chunk(
 app_handle: tauri::AppHandle,
 thread_id: String,
 chunk: MessageChunk,
) -> Result<(), String> {
 let tid = Uuid::parse_str(&thread_id)
 .map_err(|e| format!("Invalid thread ID: {e}"))?;

 let payload = serde_json::json!({
 "threadId": tid.to_string(),
 "content": chunk.content,
 "timestamp": chunk.timestamp.to_rfc3339(),
 });

 let _ = app_handle.emit("message_chunk", payload);
 Ok(())
}

// ---------------------------------------------------------------------------
// emit_hydra_progress
//
// Fires whenever a Hydra head reports progress. The frontend uses this to
// drive per-head progress bars in the hydra roster.
// ---------------------------------------------------------------------------

#[tauri::command]
pub async fn emit_hydra_progress(
 app_handle: tauri::AppHandle,
 hydra_id: String,
 head_id: String,
 progress: f64,
) -> Result<(), String> {
 let _hid = Uuid::parse_str(&hydra_id)
 .map_err(|e| format!("Invalid Hydra ID: {e}"))?;

 let payload = serde_json::json!({
 "hydraId": hydra_id,
 "headId": head_id,
 "progress": progress.clamp(0.0, 1.0),
 "timestamp": Utc::now().to_rfc3339(),
 });

 let _ = app_handle.emit("hydra_progress", payload);
 Ok(())
}

// ---------------------------------------------------------------------------
// emit_thread_update
//
// Emits when a field on a thread changes (title, pinned, status, etc.)
// so the sidebar can refresh the relevant row without reloading.
// ---------------------------------------------------------------------------

#[tauri::command]
pub async fn emit_thread_update(
 app_handle: tauri::AppHandle,
 thread_id: String,
 update: ThreadUpdate,
) -> Result<(), String> {
 let _tid = Uuid::parse_str(&thread_id)
 .map_err(|e| format!("Invalid thread ID: {e}"))?;

 let payload = serde_json::json!({
 "threadId": thread_id,
 "field": update.field,
 "value": update.value,
 "timestamp": Utc::now().to_rfc3339(),
 });

 let _ = app_handle.emit("thread_update", payload);
 Ok(())
}

// ---------------------------------------------------------------------------
// emit_terminal_output
//
// Forwards PTY stdout / stderr output from the terminal runtime to the
// frontend terminal view.
// ---------------------------------------------------------------------------

#[tauri::command]
pub async fn emit_terminal_output(
 app_handle: tauri::AppHandle,
 session_id: String,
 output: String,
 stream: TerminalStream,
) -> Result<(), String> {
 let _sid = Uuid::parse_str(&session_id)
 .map_err(|e| format!("Invalid session ID: {e}"))?;

 let payload = serde_json::json!({
 "sessionId": session_id,
 "output": output,
 "stream": stream,
 });

 let _ = app_handle.emit("terminal_output", payload);
 Ok(())
}
