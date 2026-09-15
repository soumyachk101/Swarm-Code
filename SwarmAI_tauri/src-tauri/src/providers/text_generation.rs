use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::models::provider::{ModelOption, ProviderKind, RuntimeMode};
use crate::providers::session::{
 ProviderError, SessionEvent, SessionStatus, ToolCall, ToolKind, ToolStatus, TurnInput,
};

// ---------------------------------------------------------------------------
// Public re-exports
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Chat message
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChatMessage {
 pub role: MessageRole,
 pub content: String,
 pub images: Vec<ImageAttachment>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum MessageRole {
 #[default]
 User,
 Assistant,
 System,
}

impl std::fmt::Display for MessageRole {
 fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
 match self {
 Self::User => write!(f, "user"),
 Self::Assistant => write!(f, "assistant"),
 Self::System => write!(f, "system"),
 }
 }
}

// ---------------------------------------------------------------------------
// Image attachment
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImageAttachment {
 pub url: String,
 pub mime_type: String,
 pub data: Option<String>,
 pub filename: Option<String>,
}

impl ImageAttachment {
 pub fn is_image(&self) -> bool {
 self.mime_type.starts_with("image/")
 }
}

// ---------------------------------------------------------------------------
// Text generation request
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TextGenerationRequest {
 pub provider: ProviderKind,
 pub model: Option<String>,
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub messages: Vec<ChatMessage>,
 pub temperature: Option<f32>,
 pub max_tokens: Option<u32>,
 pub stop_sequences: Vec<String>,
 pub stream: bool,
 pub metadata: serde_json::Value,
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextGenerationResponse {
 pub id: Uuid,
 pub provider: ProviderKind,
 pub model: String,
 pub content: String,
 pub reasoning: Option<String>,
 pub usage: Option<TokenUsage>,
 pub finish_reason: Option<String>,
 pub tool_calls: Vec<ToolCallResult>,
 pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TokenUsage {
 pub prompt_tokens: i64,
 pub completion_tokens: i64,
 pub total_tokens: i64,
 pub cache_read_tokens: Option<i64>,
 pub cache_creation_tokens: Option<i64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ToolCallResult {
 pub id: String,
 pub name: String,
 pub arguments: serde_json::Value,
 pub result: Option<serde_json::Value>,
 pub status: ToolStatus,
}

// ---------------------------------------------------------------------------
// Streaming delta
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum StreamDelta {
 Text { delta: String },
 Reasoning { delta: String },
 ToolStart { id: String, call: ToolCall },
 ToolOutput { id: String, delta: String },
 ToolComplete { id: String, status: ToolStatus },
 Done,
 Error { message: String },
}

// ---------------------------------------------------------------------------
// SSE line helpers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct SseLine {
 pub event: Option<String>,
 pub data: String,
}

/// Parse a raw SSE text blob into (event_type, json_value) pairs.
pub fn parse_sse_events(raw: &str) -> Vec<Result<SseLine, serde_json::Error>> {
 raw
 .split("\n\n")
 .filter(|block| !block.trim().is_empty())
 .map(|block| {
 let mut event: Option<String> = None;
 let mut data = String::new();
 for line in block.lines() {
 if let Some(rest) = line.strip_prefix("event:") {
 event = Some(rest.trim().to_string());
 } else if let Some(rest) = line.strip_prefix("data:") {
 data = rest.trim().to_string();
 }
 }
 Ok(SseLine { event, data })
 })
 .collect()
}
