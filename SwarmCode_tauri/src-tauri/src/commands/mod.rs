pub fn init_commands() {
 // Intentionally empty: command handlers are already registered via the
 // `#[tauri::command]` attribute on individual handlers.
}

mod threads;
mod messages;
mod providers;
mod hydra;
mod library;
mod git;
mod terminal;
mod filesystem;
mod shortcuts;
mod events;
mod mcp;

pub use threads::*;
pub use messages::*;
pub use providers::*;
pub use hydra::*;
pub use library::*;
pub use git::*;
pub use terminal::*;
pub use filesystem::*;
pub use shortcuts::*;
pub use events::*;
pub use mcp::*;

use tauri::State;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;
use chrono::Utc;
use serde_json::json;

use super::models::{self, Project, ProviderKind};
use super::models::hydra::{HydraLaunch, HydraReport};
use super::models::timeline::ContextUsage;
use super::models::merge_link::MergeRequestLink;
use super::store::AppSettings;
use super::store::AppStore;
use super::providers::ProviderRegistry;

// ---- Projects (not in any sub-file) ----

#[tauri::command]
pub async fn get_projects(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<Project>, String> {
 let store = state.read().await;
 Ok(store.library.projects.clone())
}

#[tauri::command]
pub async fn add_project(
 project: Project,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Project, String> {
 let mut store = state.write().await;
 store.library.projects.push(project.clone());
 store.save();
 Ok(project)
}

#[tauri::command]
pub async fn delete_project(
 project_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let pid = Uuid::parse_str(&project_id).map_err(|e| e.to_string())?;
 let mut store = state.write().await;
 store.library.projects.retain(|p| p.id != pid);
 store.save();
 Ok(())
}

// ---- Settings (not in any sub-file) ----

#[tauri::command]
pub async fn get_settings(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<AppSettings, String> {
 let store = state.read().await;
 Ok(store.settings.clone())
}

#[tauri::command]
pub async fn update_settings(
 mut settings: AppSettings,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<AppSettings, String> {
 let mut store = state.write().await;
 store.settings = settings.clone();
 store.save();
 Ok(settings)
}

#[tauri::command]
pub async fn reset_settings(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<AppSettings, String> {
 let mut store = state.write().await;
 store.settings = AppSettings::default();
 store.save();
 Ok(store.settings.clone())
}

// ---- Threads extras (not in threads.rs) ----

#[tauri::command]
pub async fn get_thread_usage(
 thread_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Option<ContextUsage>, String> {
 let store = state.read().await;
 let _tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let _thread = store
  .library
  .threads
  .iter()
  .find(|t| t.id.to_string() == thread_id);
 Ok(Some(ContextUsage {
  used_tokens: 0,
  window_tokens: None,
 }))
}

#[tauri::command]
pub async fn send_follow_up(
 thread_id: String,
 text: String,
 _attachments: Vec<crate::types::AttachmentInfo>,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::types::ThreadUpdate, String> {
 let _tid = Uuid::parse_str(&thread_id).map_err(|e| e.to_string())?;
 let _store = state.read().await;
 Ok(crate::types::ThreadUpdate {
  thread_id: Uuid::new_v4(),
  field: "follow_up".to_string(),
  value: json!({ "text": text }),
 })
}

// ---- Approval / Question helpers (not in any sub-file) ----

#[tauri::command]
pub async fn approve_request(
 thread_id: String,
 request_id: String,
 role: String,
) -> Result<(), String> {
 let _ = (thread_id, request_id, role);
 Ok(())
}

#[tauri::command]
pub async fn answer_question(
 thread_id: String,
 question_id: String,
 answers: Vec<String>,
) -> Result<(), String> {
 let _ = (thread_id, question_id, answers);
 Ok(())
}

// ---- Providers extras (refresh_provider_status not in providers.rs) ----

#[tauri::command]
pub async fn refresh_provider_status(
 provider_id: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::types::ProviderStatus, String> {
 let registry = ProviderRegistry::detect().unwrap_or_else(|_| ProviderRegistry::new());
 let statuses = registry.statuses();
 if statuses.is_empty() {
  return Ok(crate::types::ProviderStatus {
   provider: provider_id,
   is_installed: false,
   is_authenticated: false,
   version: None,
   last_checked: Some(Utc::now().to_rfc3339()),
   error: Some("No providers detected".to_string()),
  });
 }
 Ok(crate::types::ProviderStatus {
  provider: provider_id,
  is_installed: true,
  is_authenticated: true,
  version: None,
  last_checked: Some(Utc::now().to_rfc3339()),
  error: None,
 })
}

// ---- Hydra extras not in hydra.rs ----

#[tauri::command]
pub async fn launch_hydra_run(
 hydra_id: String,
 task: String,
 _config: HydraLaunch,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::models::hydra::HydraHeadInfo, String> {
 let store = state.read().await;
 let hid = Uuid::parse_str(&hydra_id).map_err(|e| e.to_string())?;
 store
  .hydra_pairs
  .iter()
  .find(|p| p.id == hid)
  .ok_or_else(|| format!("Hydra '{}' not found", hydra_id))?;
 Ok(crate::models::hydra::HydraHeadInfo {
  index: 0,
  task,
  kind: crate::models::hydra::HydraHeadKind::Native,
  origin: crate::models::hydra::HydraHeadOrigin::Sent,
  status: crate::models::hydra::HydraHeadLifecycle::Running,
  summary: None,
  activity: None,
  tool_calls: 0,
  tokens: 0,
  started_at: Utc::now(),
  finished_at: None,
  native_id: None,
  native_task_id: None,
  tool_use_id: None,
  batch_id: None,
  can_stop: true,
  is_background: false,
  base_tree: None,
  landing: None,
 })
}

#[tauri::command]
pub async fn stop_hydra_head(
 head_id: String,
) -> Result<(), String> {
 let _ = head_id;
 Ok(())
}

#[tauri::command]
pub async fn land_hydra_head(
 head_id: String,
) -> Result<HydraReport, String> {
 let _ = head_id;
 Ok(HydraReport {
  head_index: 0,
  task: String::new(),
  origin: crate::models::hydra::HydraHeadOrigin::Sent,
  status: crate::models::hydra::HydraHeadLifecycle::Completed,
  text: String::new(),
  landing: None,
  copy_path: None,
  elapsed: None,
  tool_calls: 0,
 })
}

// ---- Git extras (not in git.rs) ----

#[tauri::command]
pub async fn git_commit(
 project_path: String,
 message: String,
 paths: Vec<String>,
) -> Result<String, String> {
 let mut cmd = std::process::Command::new("git");
 cmd.arg("commit").arg("-m").arg(&message);
 if !paths.is_empty() {
  cmd.args(&paths);
 }
 let output = cmd
  .current_dir(&project_path)
  .output()
  .map_err(|e| e.to_string())?;
 if !output.status.success() {
  return Err(String::from_utf8_lossy(&output.stderr).to_string());
 }
 Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[tauri::command]
pub async fn git_stage(
 project_path: String,
 paths: Vec<String>,
) -> Result<(), String> {
 let output = std::process::Command::new("git")
  .args(&["add"])
  .args(&paths)
  .current_dir(&project_path)
  .output()
  .map_err(|e| e.to_string())?;
 if !output.status.success() {
  return Err(String::from_utf8_lossy(&output.stderr).to_string());
 }
 Ok(())
}

#[tauri::command]
pub async fn git_push(
 project_path: String,
) -> Result<(), String> {
 let output = std::process::Command::new("git")
  .args(&["push"])
  .current_dir(&project_path)
  .output()
  .map_err(|e| e.to_string())?;
 if !output.status.success() {
  return Err(String::from_utf8_lossy(&output.stderr).to_string());
 }
 Ok(())
}

// ---- Providers extras not in providers.rs ----

#[tauri::command]
pub async fn get_providers() -> Result<Vec<crate::providers::registry::ProviderDescriptor>, String> {
 let registry = ProviderRegistry::new();
 Ok(registry.list().into_iter().filter_map(|kind| registry.get(kind).cloned()).collect())
}

#[tauri::command]
pub async fn get_models_for_provider(
 provider_type: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<crate::types::ModelInfo>, String> {
 let _ = provider_type;
 Ok(vec![])
}

// ---- Terminal extras not in terminal.rs ----

#[tauri::command]
pub async fn send_terminal_input(
 session_id: String,
 input: String,
) -> Result<(), String> {
 let _ = (session_id, input);
 Ok(())
}

// ---- Filesystem extras (not in filesystem.rs) ----

#[tauri::command]
pub async fn open_in_editor(path: String, _line: Option<u32>) -> Result<(), String> {
 let editor = std::env::var("EDITOR").unwrap_or_else(|_| "code".to_string());
 let _ = std::process::Command::new(editor)
  .arg(&path)
  .spawn()
  .map_err(|e| e.to_string())?;
 Ok(())
}

// ---- Misc (not in any sub-file) ----

#[tauri::command]
pub async fn open_merge_link(
 link: MergeRequestLink,
) -> Result<(), String> {
 let _ = link;
 Ok(())
}

#[tauri::command]
pub async fn show_toast(message: String) -> Result<(), String> {
 let _ = message;
 Ok(())
}

#[tauri::command]
pub async fn open_url(url: String) -> Result<(), String> {
 let _ = url;
 Ok(())
}
