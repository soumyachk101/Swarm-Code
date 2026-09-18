use std::sync::Arc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::models::provider::{ModelOption, ProviderKind, RuntimeMode, InteractionMode};
use crate::models::requests::{ApprovalOption, ApprovalRequest, Question, QuestionRequest};
use crate::models::{ContextUsage, HydraHeadInfo, HydraHeadStatus, TodoStep};
use crate::types::{HydraRun, HydraRunStatus, ProviderCredits, ProviderTestResult, ThreadUpdate};

// ---------------------------------------------------------------------------
// Session status
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
 Idle,
 Running,
 Interrupted,
 Completed,
 Failed,
 Stopped,
}

impl Default for SessionStatus {
 fn default() -> Self {
 Self::Idle
 }
}

// ---------------------------------------------------------------------------
// Turn input
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TurnInput {
 pub text: String,
 pub images: Vec<AttachmentInfo>,
 pub model: Option<String>,
 pub effort: Option<String>,
 pub service_tier: Option<String>,
 pub runtime_mode: RuntimeMode,
 pub interaction_mode: InteractionMode,
 pub is_final_report: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AttachmentInfo {
 pub id: String,
 pub name: String,
 pub path: String,
 pub mime_type: String,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub content: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MessageOptions {
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub runtime_mode: RuntimeMode,
 pub model: Option<String>,
 pub images: Vec<String>,
 pub files: Vec<String>,
 pub is_final_report: bool,
 pub skip_reasoning: bool,
}

// ---------------------------------------------------------------------------
// Tool types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
 pub id: String,
 pub name: String,
 pub kind: ToolKind,
 pub title: String,
 pub detail: Option<String>,
}

impl ToolCall {
 pub fn new(id: impl Into<String>, name: impl Into<String>, kind: ToolKind, title: impl Into<String>) -> Self {
 Self {
 id: id.into(),
 name: name.into(),
 kind,
 title: title.into(),
 detail: None,
 }
 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolKind {
 Command,
 Edit,
 Read,
 Search,
 Web,
 Agent,
 Mcp,
 Other,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ToolUpdate {
 pub title: Option<String>,
 pub detail: Option<String>,
 pub output: Option<String>,
 pub status: Option<ToolStatus>,
 pub exit_code: Option<i32>,
 pub edits: Option<Vec<FileEdit>>,
 pub kind: Option<ToolKind>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolStatus {
 Running,
 Completed,
 Failed,
 Declined,
}

impl Default for ToolStatus {
 fn default() -> Self {
 Self::Running
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEdit {
 pub path: String,
 pub old: Option<String>,
 pub new: String,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub diff: Option<String>,
 pub additions: i32,
 pub deletions: i32,
}

impl FileEdit {
 pub fn new(path: impl Into<String>, new: impl Into<String>) -> Self {
 Self {
 path: path.into(),
 old: None,
 new: new.into(),
 diff: None,
 additions: 0,
 deletions: 0,
 }
 }
}

// ---------------------------------------------------------------------------
// Agent spawn
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSpawn {
 pub id: String,
 pub task_id: Option<String>,
 pub tool_use_id: Option<String>,
 pub description: String,
 pub prompt: Option<String>,
 pub model: Option<String>,
 pub is_background: bool,
}

// ---------------------------------------------------------------------------
// Session configuration
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SessionConfiguration {
 pub provider: ProviderKind,
 pub executable: Option<String>,
 pub working_directory: String,
 pub environment: std::collections::HashMap<String, String>,
 pub resume_id: Option<String>,
 pub resume_at: Option<String>,
 pub model: Option<String>,
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub runtime_mode: RuntimeMode,
 pub interaction_mode: InteractionMode,
 pub api_key: Option<String>,
 pub hydra: Option<HydraLaunch>,
 pub transcript: Vec<TranscriptMessage>,
 pub is_hydra_head: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraLaunch {
 pub runs_natively: bool,
 pub max_heads: Option<u32>,
 pub auto_merges: bool,
 pub reviews_heads: bool,
 pub isolates_heads: bool,
 pub head_provider: Option<ProviderKind>,
 pub head_model: Option<String>,
 pub head_effort: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptMessage {
 pub role: MessageRole,
 pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageRole {
 User,
 Assistant,
}

// ---------------------------------------------------------------------------
// Notice
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notice {
 pub level: String,
 pub message: String,
}

impl Notice {
 pub fn new(level: impl Into<String>, message: impl Into<String>) -> Self {
 Self {
 level: level.into(),
 message: message.into(),
 }
 }
}

// ---------------------------------------------------------------------------
// Session event
// ---------------------------------------------------------------------------

// Session event - alias for ProviderEvent
// ---------------------------------------------------------------------------

pub type SessionEvent = crate::runtime::thread_runtime::ProviderEvent;

// ---------------------------------------------------------------------------
// Provider session trait
// ---------------------------------------------------------------------------

#[async_trait::async_trait]
pub trait ProviderSession: Send + Sync {
 fn on_event(&self) -> Option<Arc<dyn Fn(SessionEvent) + Send + Sync>>;
 fn set_on_event(&mut self, _handler: Arc<dyn Fn(SessionEvent) + Send + Sync>);

 fn status(&self) -> SessionStatus;
 fn is_running(&self) -> bool;

 fn provider_kind(&self) -> ProviderKind;

 /// Launches the provider and returns its session id.
 async fn start(&mut self, _config: SessionConfiguration) -> Result<String, ProviderError>;

 async fn send(&mut self, _input: TurnInput) -> Result<(), ProviderError>;
 async fn interrupt(&mut self);
 async fn resolve_approval(&mut self, _request_id: String, _option_id: String);
 async fn answer_question(&mut self, _request_id: String, _answers: std::collections::HashMap<String, Vec<String>>);
 async fn compact(&mut self) -> Result<(), ProviderError>;
 async fn stop(&mut self);
 async fn stop_agent(&mut self, _id: String) -> bool {
 false
 }
}

// ---------------------------------------------------------------------------
// Provider errors
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, thiserror::Error)]
#[error("{message}")]
pub struct ProviderError {
 pub kind: ProviderErrorKind,
 pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderErrorKind {
 NotInstalled,
 NotRunning,
 Failed,
}

impl ProviderError {
 pub fn not_installed(provider: ProviderKind) -> Self {
 Self {
 kind: ProviderErrorKind::NotInstalled,
 message: format!(
 "{} is not installed. Install it and sign in, or configure an API key in Settings.",
 provider.display_name()
 ),
 }
 }

 pub fn not_running() -> Self {
 Self {
 kind: ProviderErrorKind::NotRunning,
 message: "The agent session is not running.".to_string(),
 }
 }

 pub fn failed(message: impl Into<String>) -> Self {
 Self {
 kind: ProviderErrorKind::Failed,
 message: message.into(),
 }
 }
}
