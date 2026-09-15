use serde::{Deserialize, Serialize};

use uuid::Uuid;
use chrono::{DateTime, Utc};

use super::provider::ProviderKind;
use super::hydra::HydraHeadInfo;

// ---------------------------------------------------------------------------
// Message-level types (API request / response)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageOptions {
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub interaction_mode: Option<String>,
 pub attachments: Vec<AttachmentInfo>,
 pub hydra_enabled: bool,
 pub hydra_pair_id: Option<uuid::Uuid>,
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
 pub thread_id: uuid::Uuid,
 pub content: ChunkContent,
 pub timestamp: chrono::DateTime<chrono::Utc>,
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
 TurnEnd { turn_id: uuid::Uuid },
}

// ---------------------------------------------------------------------------
// Provider-related request types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderTestResult {
 pub success: bool,
 pub message: String,
 pub models: Vec<crate::models::provider::ModelInfo>,
 pub response_time_ms: Option<u64>,
}

// ---------------------------------------------------------------------------
// Hydra-related request types
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

// HydraRun is defined in `crate::types` and re-exported here for downstream use.
pub use crate::types::HydraRun;

// ---------------------------------------------------------------------------
// Approval / Question types (from Swift Requests.swift)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalRequest {
 pub id: String,
 pub kind: ApprovalKind,
 pub title: String,
 pub detail: Option<String>,
 pub reason: Option<String>,
 pub options: Vec<ApprovalOption>,
 pub tool_item_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalKind {
 Command,
 FileChange,
 Tool,
 Permissions,
 Plan,
}

impl ApprovalKind {
 pub fn headline(&self) -> &'static str {
 match self {
 Self::Command => "Run this command?",
 Self::FileChange => "Apply these changes?",
 Self::Tool => "Allow this action?",
 Self::Permissions => "Grant extra access?",
 Self::Plan => "Ready to build this plan?",
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalOption {
 pub id: String,
 pub title: String,
 pub role: ApprovalRole,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalRole {
 Approve,
 ApproveAlways,
 Decline,
 Cancel,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestionRequest {
 pub id: String,
 pub questions: Vec<Question>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Question {
 pub id: String,
 pub header: String,
 pub prompt: String,
 pub choices: Vec<QuestionChoice>,
 pub allows_multiple: bool,
 pub allows_other: bool,
 pub is_secret: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestionChoice {
 pub label: String,
 pub detail: Option<String>,
}
