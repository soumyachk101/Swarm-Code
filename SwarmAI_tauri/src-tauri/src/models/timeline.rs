use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// TimelineItem
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineItem {
 pub id: String,
 pub turn_id: Option<Uuid>,
 pub date: DateTime<Utc>,
 pub content: TimelineContent,
}

// Constructors for each TimelineContent variant

impl TimelineItem {
 pub fn user(text: String) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::User(UserMessage { text, attachments: Vec::new(), hydra_heads: None }),
 }
 }

 pub fn assistant(text: &str) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Assistant(AssistantMessage { text: text.to_string(), is_streaming: false }),
 }
 }

 pub fn reasoning(text: &str) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Reasoning(ReasoningBlock { text: text.to_string(), is_streaming: false }),
 }
 }

 pub fn tool(call: ToolCall) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Tool(call),
 }
 }

 pub fn notice(message: String, level: NoticeLevel) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Notice(Notice { level, message }),
 }
 }

 pub fn turn_end(summary: TurnSummary) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: Some(summary.turn_id),
 date: Utc::now(),
 content: TimelineContent::TurnEnd(summary),
 }
 }

 pub fn approval(request: String) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Notice(Notice { level: NoticeLevel::Info, message: format!("Approval required: {}", request) }),
 }
 }

 pub fn plan(markdown: String) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Plan(ProposedPlan { markdown, state: PlanState::Drafting }),
 }
 }

 pub fn todos(steps: Vec<TodoStep>) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 turn_id: None,
 date: Utc::now(),
 content: TimelineContent::Todos(steps),
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TimelineContent {
 User(UserMessage),
 Assistant(AssistantMessage),
 Reasoning(ReasoningBlock),
 Tool(ToolCall),
 Plan(ProposedPlan),
 Todos(Vec<TodoStep>),
 Notice(Notice),
 TurnEnd(TurnSummary),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserMessage {
 pub text: String,
 pub attachments: Vec<Attachment>,
 pub hydra_heads: Option<Vec<u32>>,
}

impl UserMessage {
 pub fn is_from_hydra(&self) -> bool {
 self.hydra_heads.is_some()
 }
 pub fn is_hydra_report(&self) -> bool {
 !(self.hydra_heads.clone().unwrap_or_default().is_empty())
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FollowUpPrompt {
 pub id: Uuid,
 pub text: String,
 pub attachments: Vec<Attachment>,
 pub created_at: DateTime<Utc>,
}

impl FollowUpPrompt {
 pub fn is_empty(&self) -> bool {
 self.text.trim().is_empty() && self.attachments.is_empty()
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attachment {
 pub id: Uuid,
 pub name: String,
 pub path: String,
 pub mime_type: String,
}

impl Attachment {
 pub fn is_image(&self) -> bool {
 self.mime_type.starts_with("image/")
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssistantMessage {
 pub text: String,
 pub is_streaming: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReasoningBlock {
 pub text: String,
 pub is_streaming: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolKind {
 Command,
 Read,
 Edit,
 Search,
 Web,
 Mcp,
 Agent,
 Other,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ToolStatus {
 Running,
 Completed,
 Failed,
 Declined,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
 pub kind: ToolKind,
 pub title: String,
 pub detail: Option<String>,
 pub output: String,
 pub status: ToolStatus,
 pub exit_code: Option<i32>,
 pub edits: Vec<FileEdit>,
 pub started_at: DateTime<Utc>,
 pub finished_at: Option<DateTime<Utc>>,
}

impl ToolCall {
 pub const OUTPUT_LIMIT: usize = 60_000;

 pub fn finish(&mut self, status: ToolStatus) {
 self.status = status;
 if self.finished_at.is_none() {
 self.finished_at = Some(Utc::now());
 }
 }

 pub fn append_output(&mut self, text: &str) {
 self.output.push_str(text);
 self.trim_output();
 }

 pub fn set_output(&mut self, text: String) {
 self.output = text;
 self.trim_output();
 }

 fn trim_output(&mut self) {
 if self.output.len() > Self::OUTPUT_LIMIT {
 let keep = Self::OUTPUT_LIMIT / 2;
 let cut = self.output.len() - keep;
 self.output = format!("…{}", &self.output[cut..]);
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEdit {
 pub path: String,
 pub diff: Option<String>,
 pub additions: i32,
 pub deletions: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PlanState {
 Drafting,
 Proposed,
 Accepted,
 Dismissed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposedPlan {
 pub markdown: String,
 pub state: PlanState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TodoStatus {
 Pending,
 Active,
 Done,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TodoStep {
 pub text: String,
 pub status: TodoStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NoticeLevel {
 Info,
 Warning,
 Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notice {
 pub level: NoticeLevel,
 pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TurnStatus {
 Running,
 Completed,
 Interrupted,
 Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurnSummary {
 pub turn_id: Uuid,
 pub status: TurnStatus,
 pub duration: f64,
 pub files_changed: u32,
 pub additions: u32,
 pub deletions: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurnRecord {
 pub id: Uuid,
 pub index: u32,
 pub provider_turn_id: Option<String>,
 pub started_at: DateTime<Utc>,
 pub completed_at: Option<DateTime<Utc>>,
 pub status: TurnStatus,
 pub base_checkpoint: Option<String>,
 pub end_checkpoint: Option<String>,
 pub user_item_id: Option<String>,
 pub provider_diff: Option<String>,
 pub provider_anchor: Option<String>,
 pub touched_paths: Option<Vec<String>>,
 pub hydra_merged: bool,
}

impl TurnRecord {
 pub fn new(index: u32) -> Self {
 Self {
 id: Uuid::new_v4(),
 index,
 provider_turn_id: None,
 started_at: Utc::now(),
 completed_at: None,
 status: TurnStatus::Running,
 base_checkpoint: None,
 end_checkpoint: None,
 user_item_id: None,
 provider_diff: None,
 provider_anchor: None,
 touched_paths: None,
 hydra_merged: false,
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextUsage {
 pub used_tokens: u64,
 pub window_tokens: Option<u64>,
}

impl ContextUsage {
 pub fn new(used: u64, window: u64) -> Self {
 Self {
 used_tokens: used,
 window_tokens: Some(window),
 }
 }

 pub fn fraction(&self) -> Option<f64> {
 match self.window_tokens {
 Some(w) if w > 0 => Some((self.used_tokens as f64 / w as f64).min(1.0)),
 _ => None,
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreadDocument {
 pub thread_id: Uuid,
 pub items: Vec<TimelineItem>,
 pub turns: Vec<TurnRecord>,
 pub usage: Option<ContextUsage>,
 pub follow_ups: Vec<FollowUpPrompt>,
}

impl ThreadDocument {
 pub fn new(thread_id: Uuid) -> Self {
 Self {
 thread_id,
 items: Vec::new(),
 turns: Vec::new(),
 usage: None,
 follow_ups: Vec::new(),
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptMessage {
 pub role: String,
 pub content: String,
 pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreadSummary {
 pub id: Uuid,
 pub name: String,
 pub project_id: Option<Uuid>,
 pub provider: crate::models::provider::ProviderKind,
 pub model: Option<String>,
 pub status: crate::models::ThreadStatus,
 pub created_at: DateTime<Utc>,
 pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ThreadDocumentSection {
 pub title: String,
 pub markdown: String,
 pub items: Vec<TimelineItem>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ThreadStatus {
 Idle,
 Running,
 Paused,
 Completed,
 Failed,
 Cancelled,
}

impl Default for ThreadStatus {
 fn default() -> Self {
 Self::Idle
 }
}

// ---------------------------------------------------------------------------
// TimelineEntry
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineEntry {
 pub id: String,
 pub item: TimelineItem,
 pub parent_entry: Option<String>,
}

impl TimelineEntry {
 pub fn new(item: TimelineItem) -> Self {
 Self {
 id: Uuid::new_v4().to_string(),
 item,
 parent_entry: None,
 }
 }
}
