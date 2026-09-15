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

use tauri::State;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// init_commands
//
// Module-level initializer for the commands layer. Commands are registered
// with Tauri via the `#[tauri::command]` attribute (and collected with
// `tauri::generate_handler!` in the binary entry-point). This hook exists so
// that any future command registration work (e.g. setting up rate limits,
// audit logging, or Rust-side pre-warming) has a stable place to run.
// ---------------------------------------------------------------------------

pub fn init_commands() {
 // Intentionally empty: command handlers are already registered via the
 // `#[tauri::command]` attribute. This function exists so the binary can
 // call every module's initializer for symmetry, and to give future
 // work (e.g. registering a custom command-group, an audit log writer)
 // a stable entry-point.
}

use super::models::{self, Project, ProviderKind};
use super::store::AppSettings;
use super::store::AppStore;
use super::providers::ProviderRegistry;

// ---- Projects ----

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

// ---- Settings ----

#[tauri::command]
pub async fn get_settings(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<AppSettings, String> {
 let store = state.read().await;
 Ok(store.settings.clone())
}

#[tauri::command]
pub async fn update_settings(
 settings: AppSettings,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 store.settings = settings;
 store.save();
 Ok(())
}

// ---- Providers ----

#[tauri::command]
pub async fn get_providers() -> Result<Vec<String>, String> {
 let registry = ProviderRegistry::detect()?;
 Ok(registry.list().iter().map(|p| p.display_name().to_string()).collect())
}

#[tauri::command]
pub async fn get_models_for_provider(
 _provider: ProviderKind,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<models::ModelOption>, String> {
 let store = state.read().await;
 Ok(store.settings.model_list.clone())
}
