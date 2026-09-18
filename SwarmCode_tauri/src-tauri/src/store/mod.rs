use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use serde::{Deserialize, Serialize};
use std::fs;

use crate::mcp::store::MCPStore;
use crate::models::*;
use crate::types::Shortcut;
use crate::models::provider::WorkspaceMode;
use crate::support::migration;

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Library {
 pub projects: Vec<Project>,
 pub threads: Vec<ChatThread>,
 pub thread_documents: Vec<ThreadDocument>,
 pub hydra_pairs: Vec<HydraPair>,
 /// MCP server connections and their state
 pub mcp: MCPStore,
}

// ---------------------------------------------------------------------------
// TerminalProfile (mirrors Swift TerminalProfile)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TerminalProfile {
 pub id: String,
 pub name: String,
 pub shell: String,
 pub working_directory: Option<String>,
 pub environment: std::collections::HashMap<String, String>,
}

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppSettings {
 pub default_provider: Option<ProviderKind>,
 pub default_runtime_mode: Option<RuntimeMode>,
 pub default_workspace_mode: Option<WorkspaceMode>,
 pub notify_when_finished: bool,
 pub chime_when_finished: Option<String>,
 pub confirm_before_deleting: bool,
 pub auto_continue_after_limit: bool,
 pub show_reasoning: bool,
 pub chat_zoom: f64,
 pub sidebar_activity_view: bool,
 pub theme: Option<crate::models::theme::AppTheme>,
 pub backdrop_opacity: f64,
 pub binary_paths: std::collections::HashMap<String, String>,
 pub disabled_providers: Vec<ProviderKind>,
 pub model_list: Vec<ModelOption>,
 pub model_preferences: std::collections::HashMap<ProviderKind, ModelPreference>,
 pub api_keys: std::collections::HashMap<String, String>,
 pub hydra_enabled: bool,
 pub hydra_queue_heads: bool,
 pub hydra_always_heads: bool,
 pub hydra_isolate_heads: bool,
 pub hydra_auto_merge: bool,
 pub hydra_review_heads: bool,
 pub hydra_max_heads: Option<u32>,
 pub shortcuts: Vec<Shortcut>,
 pub terminal_profiles: Vec<TerminalProfile>,
 pub expert_mode: bool,
}

// ---------------------------------------------------------------------------
// ModelPreference
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelPreference {
 pub effort: Option<String>,
 pub fast_mode: bool,
}

impl Default for ModelPreference {
 fn default() -> Self {
 Self { effort: None, fast_mode: false }
 }
}

// ---------------------------------------------------------------------------
// AppStore
//
// Top-level persisted state. The `library` field is the canonical source of
// truth; the top-level `projects`, `threads`, `thread_documents`, and
// `hydra_pairs` fields are convenience accessors that mirror the Swift
// schema and are kept in sync via `sync_convenience_fields()`.
//
// Persisted state layout on disk:
//
// - For an unversioned legacy file: a bare `AppStore` JSON.
// - For a current-version file: a `VersionedStore` envelope with the
// `version` field. The migration logic in `support::migration` detects
// both shapes and upgrades as needed.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppStore {
 pub library: Library,
 pub settings: AppSettings,
 pub data_path: PathBuf,
 pub providers: Vec<crate::models::provider::Provider>,
 pub library_items: Vec<LibraryItem>,
 pub projects: Vec<Project>,
 pub threads: Vec<ChatThread>,
 pub thread_documents: Vec<ThreadDocument>,
 pub hydra_pairs: Vec<HydraPair>,
 /// MCP server connections and their state
 pub mcp: MCPStore,
}

/// Lightweight marker for items the user has pinned to their library
/// sidebar (separate from full ChatThreads / Projects).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LibraryItem {
 pub id: uuid::Uuid,
 pub kind: LibraryItemKind,
 pub label: String,
 pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LibraryItemKind {
 Snippet,
 SavedSearch,
 Note,
 Prompt,
}

impl Default for AppStore {
 fn default() -> Self {
 let data_path = dirs::data_local_dir()
 .unwrap_or_else(|| PathBuf::from("."))
 .join("swarmai")
 .join("store.json");
 Self {
 library: Library::default(),
 settings: AppSettings::default(),
 data_path,
 providers: Vec::new(),
 library_items: Vec::new(),
 projects: Vec::new(),
 threads: Vec::new(),
 thread_documents: Vec::new(),
 hydra_pairs: Vec::new(),
 mcp: MCPStore::default(),
 }
 }
}

impl AppStore {
 // ---------------------------------------------------------------------
 // Construction / persistence
 // ---------------------------------------------------------------------

 /// Build a fresh store rooted at `app_data_dir`. Creates the directory
 /// tree on the way down, runs any pending migrations, and returns the
 /// store ready to be managed by Tauri.
 pub fn new<P: Into<PathBuf>>(app_data_dir: P) -> Self {
 let dir: PathBuf = app_data_dir.into();
 let _ = fs::create_dir_all(&dir);

 let data_path = dir.join("store.json");
 let mut store = Self::default();
 store.data_path = data_path.clone();

 // Run migrations; if the file doesn't exist yet, migration returns an
 // error and we fall back to the default (empty) store.
 match migration::run_migrations(&data_path) {
 Ok((json, _result)) => {
 if let Ok(loaded) = serde_json::from_value::<Self>(json) {
 store = loaded;
 store.data_path = data_path;
 store.sync_convenience_fields();
 return store;
 }
 }
 Err(_) => {
 // No file or empty file -- use defaults.
 }
 }

 store.sync_convenience_fields();
 store
 }

 /// Persist the store to `data_path` (or the legacy `library.json` if
 /// `data_path` is empty). Convenience wrapper around `persist`.
 pub fn save(&self) {
 self.persist();
 }

 /// Persist the store to `self.data_path`. Creates the parent directory if
 /// necessary. Writes go through a tmp-then-rename so a crash mid-write
 /// cannot leave a partial JSON file.
 pub fn persist(&self) {
 let path = if self.data_path.as_os_str().is_empty() {
 dirs::data_local_dir()
 .unwrap_or_else(|| PathBuf::from("."))
 .join("swarmai")
 .join("library.json")
 } else {
 self.data_path.clone()
 };

 if let Some(parent) = path.parent() {
 let _ = fs::create_dir_all(parent);
 }

 let wrapped = match serde_json::to_value(self.clone()) {
 Ok(value) => migration::VersionedStore::wrap(value),
 Err(_) => return,
 };
 if let Ok(json) = serde_json::to_string_pretty(&wrapped) {
 let tmp = path.with_extension("json.tmp");
 if fs::write(&tmp, json.as_bytes()).is_ok() {
 let _ = fs::rename(&tmp, &path);
 }
 }
 }

 /// Load the store from disk. The migration layer handles version
 /// detection and upgrading; this is a thin wrapper.
 pub fn load(path: &Path) -> Result<Self, String> {
 match migration::run_migrations(path) {
 Ok((json, _result)) => {
 let mut store: Self = serde_json::from_value(json)
 .map_err(|e| e.to_string())?;
 store.data_path = path.to_path_buf();
 store.sync_convenience_fields();
 Ok(store)
 }
 Err(_) => {
 // Could not migrate -- try to parse directly as fallback.
 let mut store = Self::default();
 store.data_path = path.to_path_buf();
 Ok(store)
 }
 }
 }

 /// Pull `library` into the top-level convenience accessors. Called
 /// after construction, after `load`, and after any field that mutates
 /// the library directly.
 pub fn sync_convenience_fields(&mut self) {
 self.projects = self.library.projects.clone();
 self.threads = self.library.threads.clone();
 self.thread_documents = self.library.thread_documents.clone();
 self.hydra_pairs = self.library.hydra_pairs.clone();
 }

 // ---------------------------------------------------------------------
 // Project CRUD
 // ---------------------------------------------------------------------

 pub fn add_project(&mut self, project: Project) {
 self.library.projects.push(project);
 self.projects = self.library.projects.clone();
 self.persist();
 }

 pub fn delete_project(&mut self, id: uuid::Uuid) -> bool {
 let before = self.library.projects.len();
 self.library.projects.retain(|p| p.id != id);
 self.projects = self.library.projects.clone();
 let removed = self.library.projects.len() != before;
 if removed {
 self.persist();
 }
 removed
 }

 pub fn get_project(&self, id: uuid::Uuid) -> Option<&Project> {
 self.library.projects.iter().find(|p| p.id == id)
 }

 pub fn update_project(&mut self, project: Project) {
 if let Some(slot) = self.library.projects.iter_mut().find(|p| p.id == project.id) {
 *slot = project;
 self.projects = self.library.projects.clone();
 self.persist();
 }
 }

 // ---------------------------------------------------------------------
 // Thread CRUD
 // ---------------------------------------------------------------------

 pub fn add_thread(&mut self, thread: ChatThread) {
 self.library.threads.push(thread);
 self.threads = self.library.threads.clone();
 self.persist();
 }

 pub fn delete_thread(&mut self, id: uuid::Uuid) -> bool {
 let before = self.library.threads.len();
 self.library.threads.retain(|t| t.id != id);
 self.threads = self.library.threads.clone();
 let removed = self.library.threads.len() != before;
 if removed {
 self.persist();
 }
 removed
 }

 pub fn get_thread(&self, id: uuid::Uuid) -> Option<&ChatThread> {
 self.library.threads.iter().find(|t| t.id == id)
 }

 pub fn update_thread(&mut self, thread: ChatThread) {
 if let Some(slot) = self.library.threads.iter_mut().find(|t| t.id == thread.id) {
 *slot = thread;
 self.threads = self.library.threads.clone();
 self.persist();
 }
 }

 // ---------------------------------------------------------------------
 // Hydra CRUD
 // ---------------------------------------------------------------------

 pub fn add_hydra(&mut self, hydra: HydraPair) {
 self.library.hydra_pairs.push(hydra);
 self.hydra_pairs = self.library.hydra_pairs.clone();
 self.persist();
 }

 pub fn delete_hydra(&mut self, id: uuid::Uuid) -> bool {
 let before = self.library.hydra_pairs.len();
 self.library.hydra_pairs.retain(|h| h.id != id);
 self.hydra_pairs = self.library.hydra_pairs.clone();
 let removed = self.library.hydra_pairs.len() != before;
 if removed {
 self.persist();
 }
 removed
 }

 pub fn get_hydra(&self, id: uuid::Uuid) -> Option<&HydraPair> {
 self.library.hydra_pairs.iter().find(|h| h.id == id)
 }

 pub fn update_hydra_pair(&mut self, hydra: HydraPair) {
 if let Some(slot) = self.library.hydra_pairs.iter_mut().find(|h| h.id == hydra.id) {
 *slot = hydra;
 self.hydra_pairs = self.library.hydra_pairs.clone();
 self.persist();
 }
 }

 // ---------------------------------------------------------------------
 // Provider CRUD
 // ---------------------------------------------------------------------

 pub fn add_provider(&mut self, provider: crate::models::provider::Provider) {
 self.providers.push(provider);
 self.persist();
 }

 pub fn delete_provider(&mut self, id: uuid::Uuid) -> bool {
 let before = self.providers.len();
 self.providers.retain(|p| p.id != id);
 let removed = self.providers.len() != before;
 if removed {
 self.persist();
 }
 removed
 }

 pub fn get_provider(&self, id: uuid::Uuid) -> Option<&crate::models::provider::Provider> {
 self.providers.iter().find(|p| p.id == id)
 }

 pub fn update_provider(&mut self, provider: crate::models::provider::Provider) {
 if let Some(slot) = self.providers.iter_mut().find(|p| p.id == provider.id) {
 *slot = provider;
 self.persist();
 }
 }
 // -------------------------------------------------------------------------
 // MCP connections
 // -------------------------------------------------------------------------

 pub fn add_mcp_connection(&mut self, conn: crate::mcp::store::MCPConnection) {
  self.mcp.connections.push(conn);
  self.persist();
 }

 pub fn delete_mcp_connection(&mut self, catalog_id: &str) -> bool {
  let before = self.mcp.connections.len();
  self.mcp.connections.retain(|c| c.catalog_id != catalog_id);
  let removed = self.mcp.connections.len() != before;
  if removed {
   self.persist();
  }
  removed
 }

 pub fn get_mcp_connection(&self, catalog_id: &str) -> Option<&crate::mcp::store::MCPConnection> {
  self.mcp.connections.iter().find(|c| c.catalog_id == catalog_id)
 }

 pub fn update_mcp_connection(&mut self, conn: crate::mcp::store::MCPConnection) {
  if let Some(slot) = self.mcp.connections.iter_mut().find(|c| c.catalog_id == conn.catalog_id) {
   *slot = conn;
   self.persist();
  }
 }


 // ---------------------------------------------------------------------
 // Library item CRUD
 // ---------------------------------------------------------------------

 pub fn add_library_item(&mut self, item: LibraryItem) {
 self.library_items.push(item);
 self.persist();
 }

 pub fn delete_library_item(&mut self, id: uuid::Uuid) -> bool {
 let before = self.library_items.len();
 self.library_items.retain(|i| i.id != id);
 let removed = self.library_items.len() != before;
 if removed {
 self.persist();
 }
 removed
 }

 pub fn get_library_item(&self, id: uuid::Uuid) -> Option<&LibraryItem> {
 self.library_items.iter().find(|i| i.id == id)
 }

 // ---------------------------------------------------------------------
 // Settings
 // ---------------------------------------------------------------------

 pub fn update_settings(&mut self, settings: AppSettings) {
 self.settings = settings;
 self.persist();
 }

 pub fn update_setting<F>(&mut self, mutate: F)
 where
 F: FnOnce(&mut AppSettings),
 {
 mutate(&mut self.settings);
 self.persist();
 }
}

// ---------------------------------------------------------------------------
// Shared alias used throughout commands.
// ---------------------------------------------------------------------------

pub type SharedStore = Arc<RwLock<AppStore>>;
