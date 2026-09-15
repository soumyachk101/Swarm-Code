use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// init_types
//
// Module-level initializer. Stateless today, but kept so the rest of the
// app can call `init_types()` to give the runtime a chance to register
// anything it needs at startup (schema validators, default values, etc.).
// ---------------------------------------------------------------------------

pub fn init_types() {
 // Intentionally empty: types are pure data and need no runtime setup.
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageOptions {
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub interaction_mode: Option<String>,
 pub attachments: Vec<AttachmentInfo>,
 pub hydra_enabled: bool,
 pub hydra_pair_id: Option<Uuid>,
}

impl Default for MessageOptions {
 fn default() -> Self {
 Self {
 effort: None,
 fast_mode: false,
 interaction_mode: None,
 attachments: Vec::new(),
 hydra_enabled: false,
 hydra_pair_id: None,
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentInfo {
 pub id: String,
 pub name: String,
 pub path: String,
 pub mime_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageChunk {
 pub thread_id: Uuid,
 pub content: ChunkContent,
 pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ChunkContent {
 Text { delta: String },
 Reasoning { delta: String },
 ToolStart { id: String, kind: String, title: String },
 ToolOutput { id: String, delta: String },
 ToolComplete { id: String, status: String },
 PlanDraft { markdown: String },
 Notice { level: String, message: String },
 TurnEnd { turn_id: Uuid },
}

// ---------------------------------------------------------------------------
// Provider types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderTestResult {
 pub success: bool,
 pub message: String,
 pub models: Vec<ModelInfo>,
 pub response_time_ms: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
 pub id: String,
 pub name: String,
 pub detail: Option<String>,
 pub efforts: Vec<String>,
 pub default_effort: Option<String>,
 pub is_default: bool,
 pub fast_tier: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderCredits {
 pub provider_id: String,
 pub remaining: Option<f64>,
 pub unit: Option<String>,
 pub resets_at: Option<DateTime<Utc>>,
 pub is_unlimited: bool,
}

// ---------------------------------------------------------------------------
// Hydra types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraConfig {
 pub provider: String,
 pub model: Option<String>,
 pub effort: Option<String>,
 pub max_heads: Option<u32>,
 pub worker_provider: Option<String>,
 pub worker_model: Option<String>,
 pub worker_effort: Option<String>,
 pub auto_merge: bool,
 pub reviews_heads: bool,
 pub isolates_heads: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraRun {
 pub id: Uuid,
 pub hydra_id: Uuid,
 pub prompt: String,
 pub heads: Vec<HydraHeadStatus>,
 pub status: HydraRunStatus,
 pub started_at: DateTime<Utc>,
 pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HydraRunStatus {
 Running,
 Completed,
 Failed,
 Stopped,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraHeadStatus {
 pub index: u32,
 pub name: String,
 pub task: String,
 pub status: String,
 pub progress: f64,
 pub summary: Option<String>,
 pub started_at: DateTime<Utc>,
 pub finished_at: Option<DateTime<Utc>>,
}

// ---------------------------------------------------------------------------
// Git types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GitStatus {
 pub branch: Option<String>,
 pub upstream: Option<String>,
 pub ahead: u32,
 pub behind: u32,
 pub modified: Vec<String>,
 pub added: Vec<String>,
 pub deleted: Vec<String>,
 pub renamed: Vec<String>,
 pub untracked: Vec<String>,
 pub staged: Vec<String>,
 pub is_repo: bool,
}

impl GitStatus {
 pub fn is_dirty(&self) -> bool {
 !self.modified.is_empty() || !self.added.is_empty() || !self.deleted.is_empty() || !self.untracked.is_empty()
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffEntry {
 pub path: String,
 pub old_path: Option<String>,
 pub change_type: DiffChangeType,
 pub additions: u32,
 pub deletions: u32,
 pub diff: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DiffChangeType {
 Added,
 Modified,
 Deleted,
 Renamed,
 Copied,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommit {
 pub hash: String,
 pub short_hash: String,
 pub author: String,
 pub email: String,
 pub date: DateTime<Utc>,
 pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBlame {
 pub line: usize,
 pub commit_hash: String,
 pub author: String,
 pub date: DateTime<Utc>,
 pub summary: String,
}

// ---------------------------------------------------------------------------
// Terminal types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalSession {
 pub id: Uuid,
 pub thread_id: Uuid,
 pub directory: String,
 pub title: String,
 pub is_running: bool,
 pub cols: u16,
 pub rows: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TerminalStream {
 Stdout,
 Stderr,
 System,
}

// ---------------------------------------------------------------------------
// Filesystem types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirEntry {
 pub name: String,
 pub path: String,
 pub is_directory: bool,
 pub size: Option<u64>,
 pub modified: Option<DateTime<Utc>>,
 pub extension: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePreview {
 pub path: String,
 pub name: String,
 pub extension: String,
 pub size: u64,
 pub lines: u32,
 pub preview: String,
 pub is_text: bool,
}

// ---------------------------------------------------------------------------
// Shortcut types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Shortcut {
 pub action: String,
 pub key: String,
 pub modifiers: Vec<String>,
 pub display: String,
}

// ---------------------------------------------------------------------------
// Event types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreadUpdate {
 pub thread_id: Uuid,
 pub field: String,
 pub value: serde_json::Value,
}
