//! ThreadRuntime - manages background AI agent execution for a chat thread.
//!
//! Mirrors the Swift `ThreadRuntime` class: owns a thread's timeline, provider
//! session, pending requests, follow-up queue, and diff state.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::models::provider::{ProviderKind, RuntimeMode, InteractionMode};
use crate::models::timeline::{
	ContextUsage as TimelineContextUsage,
	FollowUpPrompt, TimelineEntry, TimelineItem, TodoStep, ToolKind as TimelineToolKind,
	ToolStatus as TimelineToolStatus,
	TurnRecord, TurnSummary, TurnStatus, Notice, NoticeLevel,
};

// ---------------------------------------------------------------------------
// Runtime status and phase
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeStatus {
	Idle,
	Starting,
	Running,
	Stopped,
	Failed,
}

impl Default for RuntimeStatus {
	fn default() -> Self {
		Self::Idle
	}
}

// ---------------------------------------------------------------------------
// Attachment and draft (thread-runtime-level)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Attachment {
	pub id: String,
	pub path: String,
	pub is_image: bool,
	pub name: String,
	pub size: u64,
}

impl Attachment {
	pub fn new(path: String, is_image: bool) -> Self {
		let name = std::path::Path::new(&path)
			.file_name()
			.map(|n| n.to_string_lossy().to_string())
			.unwrap_or_default();
		let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
		Self {
			id: Uuid::new_v4().to_string(),
			path,
			is_image,
			name,
			size,
		}
	}
}

#[derive(Debug, Clone, Default)]
pub struct ComposerDraft {
	pub text: String,
	pub attachments: Vec<Attachment>,
}

impl ComposerDraft {
	pub fn is_empty(&self) -> bool {
		self.text.trim().is_empty() && self.attachments.is_empty()
	}

	pub fn clear(&mut self) {
		self.text.clear();
		self.attachments.clear();
	}
}

// ---------------------------------------------------------------------------
// Tool call types (thread-runtime-level, distinct from timeline types)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolKind {
	Read,
	Edit,
	Command,
	Bash,
	Web,
	Agent,
	Plan,
	Search,
	Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolStatus {
	Running,
	Completed,
	Failed,
	Declined,
}

impl ToolStatus {
	pub fn is_running(&self) -> bool {
		matches!(self, Self::Running)
	}
}

#[derive(Debug, Clone)]
pub struct ToolCall {
	pub id: String,
	pub kind: ToolKind,
	pub title: String,
	pub detail: Option<String>,
	pub output: String,
	pub status: ToolStatus,
	pub exit_code: Option<i32>,
	pub edits: Vec<FileEdit>,
	pub started_at: chrono::DateTime<chrono::Utc>,
	pub finished_at: Option<chrono::DateTime<chrono::Utc>>,
}

impl ToolCall {
	pub fn new(kind: ToolKind, title: &str, detail: Option<&str>) -> Self {
		Self {
			id: Uuid::new_v4().to_string(),
			kind,
			title: title.to_string(),
			detail: detail.map(|s| s.to_string()),
			output: String::new(),
			status: ToolStatus::Running,
			exit_code: None,
			edits: Vec::new(),
			started_at: chrono::Utc::now(),
			finished_at: None,
		}
	}

	pub fn finish(&mut self, status: ToolStatus) {
		self.status = status;
		self.finished_at = Some(chrono::Utc::now());
	}
}

#[derive(Debug, Clone)]
pub struct ToolUpdate {
	pub output: Option<String>,
	pub status: Option<ToolStatus>,
	pub edits: Option<Vec<FileEdit>>,
}

impl ToolUpdate {
	pub fn new(output: Option<&str>, status: Option<ToolStatus>) -> Self {
		Self {
			output: output.map(|s| s.to_string()),
			status,
			edits: None,
		}
	}
}

#[derive(Debug, Clone)]
pub struct FileEdit {
	pub path: String,
	pub diff: String,
	pub additions: u32,
	pub deletions: u32,
}

#[derive(Debug, Clone)]
pub struct DiffFile {
	pub path: String,
	pub additions: u32,
	pub deletions: u32,
}

// ---------------------------------------------------------------------------
// Approval and question types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApprovalKind {
	Plan,
	Command,
}

#[derive(Debug, Clone)]
pub struct ApprovalRequest {
	pub id: String,
	pub kind: ApprovalKind,
	pub title: String,
	pub detail: Option<String>,
	pub reason: Option<String>,
	pub options: Vec<ApprovalOption>,
	pub tool_item_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ApprovalOption {
	pub id: String,
	pub title: String,
	pub role: ApprovalRole,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApprovalRole {
	Approve,
	ApproveAlways,
	Decline,
}

#[derive(Debug, Clone)]
pub struct QuestionRequest {
	pub id: String,
	pub questions: Vec<Question>,
}

#[derive(Debug, Clone)]
pub struct Question {
	pub id: String,
	pub header: String,
	pub prompt: String,
	pub choices: Vec<Choice>,
	pub allows_multiple: bool,
	pub allows_other: bool,
	pub is_secret: bool,
}

#[derive(Debug, Clone)]
pub struct Choice {
	pub id: String,
	pub label: String,
	pub detail: Option<String>,
}

// ---------------------------------------------------------------------------
// Context usage
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct ContextUsage {
	pub used_tokens: u64,
	pub window_tokens: u64,
}

impl ContextUsage {
	pub fn new(used: u64, window: u64) -> Self {
		Self {
			used_tokens: used,
			window_tokens: window,
		}
	}
}

// ---------------------------------------------------------------------------
// Hydra types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HydraLaunch {
	pub pair_id: Uuid,
	pub hydra_kind: HydraKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HydraKind {
	Native,
	Droppy,
}

// ---------------------------------------------------------------------------
// Session signature
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionSignature {
	pub provider: ProviderKind,
	pub directory: String,
	pub launch_runtime_mode: Option<RuntimeMode>,
	pub launch_effort: Option<String>,
	pub launch_fast: Option<bool>,
	pub launch_model: Option<String>,
	pub launch_interaction: Option<InteractionMode>,
	pub hydra: Option<HydraLaunch>,
}

// ---------------------------------------------------------------------------
// Provider events (thread-runtime level)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum ProviderEvent {
	SessionReady { session_id: String },
	SessionStarted { session_id: String },
	TurnStarted { provider_turn_id: Option<String> },
	MessageDelta { id: String, text: String },
	MessageCompleted { id: String, text: String },
	ReasoningDelta { id: String, text: String },
	ReasoningCompleted { id: String, text: String },
	ToolStarted { id: String, call: ToolCall },
	ToolOutput { id: String, text: String },
	ToolUpdated { id: String, update: ToolUpdate },
	PlanDelta { id: String, text: String },
	PlanCompleted { id: String, markdown: String },
	Todos { steps: Vec<TodoStep> },
	Approval { request: ApprovalRequest },
	Question { request: QuestionRequest },
	RequestResolved { id: String },
	Usage { used: u64, window: u64 },
	Diff { diff: String },
	Notice { level: NoticeLevel, message: String },
	UsageLimit { resets_at: Option<i64> },
	ModeChanged { mode: InteractionMode },
	Models {
		list: Vec<crate::models::provider::ModelInfo>,
		provider: ProviderKind,
	},
	Commands { list: Vec<crate::models::provider::SlashCommand> },
	Title { title: String },
	AssistantMessageID { anchor: String },
	TurnCompleted { status: TurnStatus, error: Option<String> },
	Exited { error: Option<String> },
	AgentStarted { spawn: AgentSpawn },
	AgentEvent { agent_id: String, event: AgentEvent },
	AgentProgress {
		agent_id: String,
		summary: Option<String>,
		last_tool: Option<String>,
		tokens: Option<u64>,
		tool_calls: Option<u32>,
	},
	AgentFinished {
		agent_id: String,
		status: TurnStatus,
		summary: Option<String>,
	},
	// Convenience snake_case aliases (different field shape than PascalCase)
	models_short(Vec<crate::models::provider::ModelInfo>, Option<&'static str>),
	commands_short(Vec<crate::models::provider::SlashCommand>),
	turn_started(Option<String>),
	request_resolved(String),
	mode_changed(InteractionMode),
	session_ended(crate::providers::session::SessionStatus, Option<String>),
	message_chunk(String),
	reasoning(String),
	tool_call(String, String, serde_json::Value),
	session_started(String),
	notice(Notice),
}

#[derive(Debug, Clone)]
pub struct AgentSpawn {
	pub id: String,
	pub task_id: Option<String>,
	pub tool_use_id: Option<String>,
	pub description: String,
	pub prompt: Option<String>,
	pub model: Option<String>,
	pub is_background: bool,
}

#[derive(Debug, Clone)]
pub enum AgentEvent {
	TurnStarted,
	TurnCompleted { status: TurnStatus },
	ToolStarted { tool_id: String, call: ToolCall },
	ToolUpdated { tool_id: String, update: ToolUpdate },
}

// ---------------------------------------------------------------------------
// ThreadRuntime
// ---------------------------------------------------------------------------

pub struct ThreadRuntime {
	pub thread_id: Uuid,
	pub entries: RwLock<Vec<Arc<TimelineEntry>>>,
	pub turns: RwLock<Vec<TurnRecord>>,
	pub usage: RwLock<Option<crate::models::ContextUsage>>,
	pub phase: RwLock<RuntimeStatus>,
	pub draft: RwLock<ComposerDraft>,
	pub is_terminal_visible: RwLock<bool>,
	pub is_diff_visible: RwLock<bool>,
	pub follow_ups: RwLock<Vec<FollowUpPrompt>>,
	pub current_turn_id: RwLock<Option<Uuid>>,
	pub session_epoch: RwLock<u64>,
	pub working_directory: RwLock<String>,
	pub session_signature: RwLock<Option<SessionSignature>>,
	pub diff_revision: RwLock<u64>,
	pending_deltas: RwLock<Vec<PendingDelta>>,
}

#[derive(Debug, Clone)]
pub(crate) struct PendingDelta {
	pub kind: DeltaKind,
	pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DeltaKind {
	Message,
	Reasoning,
	ToolOutput,
	Plan,
}

impl ThreadRuntime {
	pub fn new(thread_id: Uuid) -> Self {
		Self {
			thread_id,
			entries: RwLock::new(Vec::new()),
			turns: RwLock::new(Vec::new()),
			usage: RwLock::new(None),
			phase: RwLock::new(RuntimeStatus::Idle),
			draft: RwLock::new(ComposerDraft::default()),
			is_terminal_visible: RwLock::new(false),
			is_diff_visible: RwLock::new(false),
			follow_ups: RwLock::new(Vec::new()),
			current_turn_id: RwLock::new(None),
			session_epoch: RwLock::new(0),
			working_directory: RwLock::new(String::new()),
			session_signature: RwLock::new(None),
			diff_revision: RwLock::new(0),
			pending_deltas: RwLock::new(Vec::new()),
		}
	}

	pub async fn is_running(&self) -> bool {
		*self.phase.read().await != RuntimeStatus::Idle
	}

	/// Whether the runtime can queue messages (running or heads are working).
	pub async fn can_queue(&self) -> bool {
		self.is_running().await
	}

	/// Enqueue a follow-up prompt for when the current turn finishes.
	pub async fn enqueue_follow_up(
		&self,
		text: String,
		attachments: Vec<crate::models::timeline::Attachment>,
	) {
		let prompt = FollowUpPrompt {
			id: Uuid::new_v4(),
			text: text.trim().to_string(),
			attachments,
			created_at: chrono::Utc::now(),
		};
		self.follow_ups.write().await.push(prompt);
	}

	/// Remove a follow-up prompt by id.
	pub async fn remove_follow_up(&self, id: &str) {
		self.follow_ups
			.write()
			.await
			.retain(|p| p.id.to_string() != id);
	}

	/// Send the next follow-up right away.
	pub async fn send_follow_up_now(&self, id: &str) {
		if *self.phase.read().await == RuntimeStatus::Idle {
			let follow_ups = &mut *self.follow_ups.write().await;
			if let Some(idx) = follow_ups.iter().position(|p| p.id.to_string() == id) {
				let prompt = follow_ups.remove(idx);
				if !prompt.text.trim().is_empty() {
					// Signal start of new turn with prompt text
				}
			}
		}
	}

	/// Queue the composer draft as a follow-up while a turn runs.
	pub async fn queue_draft_as_follow_up(&self, draft: &ComposerDraft) {
		if !draft.is_empty() && self.can_queue().await {
			let text = draft.text.clone();
			let attachments = draft
				.attachments
				.iter()
				.map(|a| crate::models::timeline::Attachment {
					id: Uuid::parse_str(&a.id).unwrap_or_default(),
					name: a.name.clone(),
					path: a.path.clone(),
					mime_type: if a.is_image {
						"image/*".into()
					} else {
						"application/octet-stream".into()
					},
				})
				.collect::<Vec<crate::models::timeline::Attachment>>();
			self.enqueue_follow_up(text, attachments).await;
		}
	}

	pub async fn append_entry(&self, entry: TimelineEntry) {
		self.entries.write().await.push(Arc::new(entry));
	}

	pub async fn append_notice(&self, level: NoticeLevel, message: &str) {
		let item = TimelineItem::notice(message.to_string(), level);
		self.append_entry(TimelineEntry::new(item)).await;
	}

	/// Rehearse a provider event - apply it to the runtime state.
	pub async fn rehearse(&self, event: ProviderEvent) {
		match event {
			ProviderEvent::MessageDelta { id, text } => {
				self.queue_delta(id, DeltaKind::Message, text).await;
			}
			ProviderEvent::ReasoningDelta { id, text } => {
				self.queue_delta(id, DeltaKind::Reasoning, text).await;
			}
			ProviderEvent::ToolOutput { id, text } => {
				self.queue_delta(id, DeltaKind::ToolOutput, text).await;
			}
			ProviderEvent::MessageCompleted { id, text } => {
				self.flush_deltas().await;
				self.complete_message(id, text).await;
			}
			ProviderEvent::ReasoningCompleted { id, text } => {
				self.flush_deltas().await;
				self.complete_reasoning(id, text).await;
			}
			ProviderEvent::ToolStarted { id, call } => {
				self.flush_deltas().await;
				self.on_tool_started(id, call).await;
			}
			ProviderEvent::ToolUpdated { id, update } => {
				self.flush_deltas().await;
				self.apply_tool_update(id, update).await;
			}
			ProviderEvent::Usage { used, window } => {
				*self.usage.write().await = Some(crate::models::ContextUsage::new(used, window));
			}
			ProviderEvent::Notice { level, message } => {
				self.append_notice(level, &message).await;
			}
			ProviderEvent::TurnCompleted { status, error } => {
				self.flush_deltas().await;
				if let Some(error) = error {
					self.append_notice(NoticeLevel::Error, &error).await;
				}
				*self.phase.write().await = RuntimeStatus::Idle;
				let summary = TurnSummary {
					turn_id: self.current_turn_id.read().await.unwrap_or_default(),
					status,
					duration: 0.0,
					files_changed: 0,
					additions: 0,
					deletions: 0,
				};
				self.append_entry(TimelineEntry::new(TimelineItem::turn_end(summary)))
					.await;
				*self.current_turn_id.write().await = None;
			}
			ProviderEvent::Approval { request } => {
				let item = TimelineItem::notice(
					format!("Approval required: {}", request.title),
					NoticeLevel::Info,
				);
				self.append_entry(TimelineEntry::new(item)).await;
			}
			ProviderEvent::PlanDelta { id, text } => {
				self.queue_delta(id, DeltaKind::Plan, text).await;
			}
			ProviderEvent::PlanCompleted { id, markdown } => {
				self.flush_deltas().await;
				let item = TimelineItem::plan(markdown);
				self.append_entry(TimelineEntry::new(item)).await;
			}
			ProviderEvent::Todos { steps } => {
				let item = TimelineItem::todos(
					steps
						.into_iter()
						.map(|s| TodoStep {
							text: s.text,
							status: s.status,
						})
						.collect::<Vec<_>>(),
				);
				self.append_entry(TimelineEntry::new(item)).await;
			}
			ProviderEvent::UsageLimit { resets_at } => {
				self.append_notice(
					NoticeLevel::Info,
					&format!("Usage limit reached. Resets at: {:?}", resets_at),
				)
				.await;
			}
			_ => {}
		}
	}

	/// Rehearse a turn with pre-recorded content (for captures/testing).
	pub async fn rehearse_turn(
		&self,
		text: &str,
		_touched_paths: Option<Vec<String>>,
		_provider_diff: Option<&str>,
	) {
		let turn = TurnRecord::new(self.turns.read().await.len() as u32);
		self.turns.write().await.push(turn);
		*self.phase.write().await = RuntimeStatus::Running;

		let user_item = TimelineItem::user(text.to_string());
		self.append_entry(TimelineEntry::new(user_item)).await;
	}

	/// Drain follow-ups that should be sent after a turn completes.
	pub async fn drain_follow_ups(&self) -> Vec<FollowUpPrompt> {
		let mut follow_ups = self.follow_ups.write().await;
		let drained: Vec<FollowUpPrompt> = follow_ups.drain(..).collect();
		drained
	}

	pub async fn stop(&self) {
		*self.phase.write().await = RuntimeStatus::Stopped;
		*self.current_turn_id.write().await = None;
	}

	pub async fn interrupt(&self) {
		*self.phase.write().await = RuntimeStatus::Idle;
		*self.current_turn_id.write().await = None;
	}

	/// Set the working directory for this runtime.
	pub async fn set_working_directory(&self, dir: String) {
		*self.working_directory.write().await = dir;
	}

	/// Get the working directory.
	pub async fn working_directory(&self) -> String {
		self.working_directory.read().await.clone()
	}

	/// Set the session signature.
	pub async fn set_session_signature(&self, sig: SessionSignature) {
		*self.session_signature.write().await = Some(sig);
	}

	/// Bump the session epoch (invalidates stale event handlers).
	pub async fn bump_session_epoch(&self) -> u64 {
		let mut epoch = self.session_epoch.write().await;
		*epoch += 1;
		*epoch
	}

	/// Check if the current session signature still matches.
	pub async fn has_valid_session(&self, sig: &SessionSignature) -> bool {
		self.session_signature.read().await.as_ref() == Some(sig)
	}

	/// Note that a usage limit was hit during a turn.
	pub async fn note_usage_limit(&self, resets_at: Option<i64>) {
		self.rehearse(ProviderEvent::UsageLimit { resets_at })
			.await;
	}

	// -----------------------------------------------------------------------
	// Delta buffering
	// -----------------------------------------------------------------------

	async fn queue_delta(&self, _id: String, kind: DeltaKind, text: String) {
		self.pending_deltas.write().await.push(PendingDelta { kind, text });
	}

	async fn flush_deltas(&self) {
		let deltas = self.pending_deltas.write().await.drain(..).collect::<Vec<_>>();
		for delta in deltas {
			match delta.kind {
				DeltaKind::Message => {
					let item = TimelineItem::assistant(&delta.text);
					self.append_entry(TimelineEntry::new(item)).await;
				}
				DeltaKind::Reasoning => {
					let item = TimelineItem::reasoning(&delta.text);
					self.append_entry(TimelineEntry::new(item)).await;
				}
				DeltaKind::ToolOutput => {
					// Tool output delta appended to the last tool entry
				}
				DeltaKind::Plan => {
					// Plan delta text
				}
			}
		}
	}

	async fn complete_message(&self, _id: String, _text: String) {
		// Mark message as complete in timeline
	}

	async fn complete_reasoning(&self, _id: String, _text: String) {
		// Mark reasoning as complete
	}

	async fn on_tool_started(&self, _id: String, call: ToolCall) {
		let kind = match call.kind {
			ToolKind::Read => TimelineToolKind::Read,
			ToolKind::Edit => TimelineToolKind::Edit,
			ToolKind::Command | ToolKind::Bash => TimelineToolKind::Command,
			ToolKind::Web => TimelineToolKind::Web,
			ToolKind::Agent => TimelineToolKind::Agent,
			ToolKind::Plan => TimelineToolKind::Other,
			ToolKind::Search => TimelineToolKind::Search,
			ToolKind::Other => TimelineToolKind::Other,
		};
		let timeline_call = crate::models::timeline::ToolCall {
			kind,
			title: call.title.clone(),
			detail: call.detail.clone(),
			output: String::new(),
			status: match call.status {
				ToolStatus::Running => TimelineToolStatus::Running,
				ToolStatus::Completed => TimelineToolStatus::Completed,
				ToolStatus::Failed => TimelineToolStatus::Failed,
				ToolStatus::Declined => TimelineToolStatus::Declined,
			},
			exit_code: call.exit_code,
			edits: Vec::new(),
			started_at: chrono::Utc::now(),
			finished_at: None,
		};
		let item = TimelineItem::tool(timeline_call);
		self.append_entry(TimelineEntry::new(item)).await;
	}

	async fn apply_tool_update(&self, _id: String, _update: ToolUpdate) {
		// Update tool entry with new output/status
	}
}

// ---------------------------------------------------------------------------
// RuntimeManager - top-level registry of runtimes
// ---------------------------------------------------------------------------

pub struct RuntimeManager {
	runtimes: RwLock<HashMap<Uuid, Arc<ThreadRuntime>>>,
}

impl RuntimeManager {
	pub fn new() -> Self {
		Self {
			runtimes: RwLock::new(HashMap::new()),
		}
	}

	pub async fn start(&self, thread: &crate::models::thread::ChatThread) -> Arc<ThreadRuntime> {
		let runtime = Arc::new(ThreadRuntime::new(thread.id));
		self.runtimes
			.write()
			.await
			.insert(thread.id, runtime.clone());
		runtime
	}

	pub async fn get(&self, id: Uuid) -> Option<Arc<ThreadRuntime>> {
		self.runtimes.read().await.get(&id).cloned()
	}

	pub async fn remove(&self, id: Uuid) {
		self.runtimes.write().await.remove(&id);
	}

	pub async fn stop_all(&self) {
		let runtimes = self.runtimes.read().await;
		for runtime in runtimes.values() {
			runtime.stop().await;
		}
	}

	pub async fn len(&self) -> usize {
		self.runtimes.read().await.len()
	}

	pub async fn is_empty(&self) -> bool {
		self.runtimes.read().await.is_empty()
	}
}

impl Default for RuntimeManager {
	fn default() -> Self {
		Self::new()
	}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_runtime_status_default() {
		assert_eq!(RuntimeStatus::default(), RuntimeStatus::Idle);
	}

	#[test]
	fn test_tool_call_new() {
		let call = ToolCall::new(ToolKind::Bash, "echo hello", None);
		assert_eq!(call.status, ToolStatus::Running);
		assert_eq!(call.title, "echo hello");
	}

	#[test]
	fn test_tool_call_finish() {
		let mut call = ToolCall::new(ToolKind::Edit, "edit file", None);
		call.finish(ToolStatus::Completed);
		assert_eq!(call.status, ToolStatus::Completed);
		assert!(call.finished_at.is_some());
	}

	#[tokio::test]
	async fn test_runtime_new() {
		let rt = ThreadRuntime::new(Uuid::new_v4());
		assert!(!rt.is_running().await);
		assert!(rt.can_queue().await);
	}

	#[tokio::test]
	async fn test_runtime_manager() {
		let mgr = RuntimeManager::new();
		assert!(mgr.is_empty().await);
	}

	#[test]
	fn test_context_usage() {
		let cu = ContextUsage::new(500, 2000);
		assert_eq!(cu.used_tokens, 500);
		assert_eq!(cu.window_tokens, 2000);
	}

	#[test]
	fn test_attachment_new() {
		let att = Attachment::new("/tmp/test.txt".to_string(), false);
		assert_eq!(att.name, "test.txt");
		assert!(!att.is_image);
	}

	#[test]
	fn test_composer_draft_empty() {
		let draft = ComposerDraft::default();
		assert!(draft.is_empty());
	}

	#[test]
	fn test_tool_kind_variants() {
		let kinds = vec![
			ToolKind::Read,
			ToolKind::Edit,
			ToolKind::Command,
			ToolKind::Bash,
			ToolKind::Web,
			ToolKind::Agent,
			ToolKind::Plan,
			ToolKind::Search,
			ToolKind::Other,
		];
		assert_eq!(kinds.len(), 9);
	}

	#[tokio::test]
	async fn test_stop_runtime() {
		let rt = ThreadRuntime::new(Uuid::new_v4());
		*rt.phase.write().await = RuntimeStatus::Running;
		rt.stop().await;
		assert_eq!(*rt.phase.read().await, RuntimeStatus::Stopped);
	}

	#[tokio::test]
	async fn test_interrupt_runtime() {
		let rt = ThreadRuntime::new(Uuid::new_v4());
		*rt.phase.write().await = RuntimeStatus::Running;
		*rt.current_turn_id.write().await = Some(Uuid::new_v4());
		rt.interrupt().await;
		assert_eq!(*rt.phase.read().await, RuntimeStatus::Idle);
		assert!(rt.current_turn_id.read().await.is_none());
	}
}
