use std::fmt;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// ProviderKind (mirrors Swift ProviderKind exactly)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum ProviderKind {
 Codex,
 Claude,
 Cursor,
 Opencode,
 Grok,
 Deepseek,
 Meta,
 Devin,
 Antigravity,
 Copilot,
 OpenAi,
 Gemini,
 ACP,
}

impl Default for ProviderKind {
 fn default() -> Self {
 Self::Codex
 }
}

impl fmt::Display for ProviderKind {
 fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
 let s = match self {
 Self::Codex => "codex",
 Self::Claude => "claude",
 Self::Cursor => "cursor",
 Self::Opencode => "opencode",
 Self::Grok => "grok",
 Self::Deepseek => "deepseek",
 Self::Meta => "meta",
 Self::Devin => "devin",
 Self::Antigravity => "antigravity",
 Self::Copilot => "copilot",
 Self::OpenAi => "openai",
 Self::Gemini => "gemini",
 Self::ACP => "acp",
 };
 write!(f, "{s}")
 }
}

impl ProviderKind {
 pub const ALL: &'static [ProviderKind] = &[
 Self::Codex,
 Self::Claude,
 Self::Cursor,
 Self::Opencode,
 Self::Grok,
 Self::Deepseek,
 Self::Meta,
 Self::Devin,
 Self::Antigravity,
 Self::Copilot,
 Self::OpenAi,
 Self::Gemini,
 Self::ACP,
 ];

 pub fn display_name(&self) -> &'static str {
 match self {
 Self::Codex => "Codex",
 Self::Claude => "Claude",
 Self::Cursor => "Cursor",
 Self::Opencode => "OpenCode",
 Self::Grok => "Grok",
 Self::Deepseek => "DeepSeek",
 Self::Meta => "Meta",
 Self::Devin => "Devin",
 Self::Antigravity => "Antigravity",
 Self::Copilot => "Copilot",
 Self::OpenAi => "OpenAI",
 Self::Gemini => "Gemini",
 Self::ACP => "ACP",
 }
 }

 pub fn executable_name(&self) -> &'static str {
 match self {
 Self::Codex => "codex",
 Self::Claude => "claude",
 Self::Cursor => "cursor-agent",
 Self::Opencode => "opencode",
 Self::Grok => "grok",
 Self::Deepseek => "",
 Self::Meta => "",
 Self::Devin => "devin",
 Self::Antigravity => "agy",
 Self::Copilot => "copilot",
 Self::OpenAi => "",
 Self::Gemini => "",
 Self::ACP => "acp",
 }
 }

 pub fn icon_name(&self) -> String {
 format!("provider-{}", self)
 }

 pub fn login_command(&self) -> &'static str {
 match self {
 Self::Codex => "codex login",
 Self::Claude => "claude auth login",
 Self::Cursor => "cursor-agent login",
 Self::Opencode => "opencode auth login",
 Self::Grok => "grok login",
 Self::Deepseek => "DEEPSEEK_API_KEY=sk-...",
 Self::Meta => "MODEL_API_KEY=...",
 Self::Devin => "devin auth login",
 Self::Antigravity => "agy",
 Self::Copilot => "copilot login",
 Self::OpenAi => "OPENAI_API_KEY=sk-...",
 Self::Gemini => "GEMINI_API_KEY=...",
 Self::ACP => "acp",
 }
 }

 pub fn install_url(&self) -> &'static str {
 match self {
 Self::Codex => "https://developers.openai.com/codex/cli",
 Self::Claude => "https://claude.com/product/claude-code",
 Self::Cursor => "https://cursor.com/cli",
 Self::Opencode => "https://opencode.ai",
 Self::Grok => "https://x.ai/cli",
 Self::Deepseek => "https://platform.deepseek.com/api_keys",
 Self::Meta => "https://dev.meta.ai/",
 Self::Devin => "https://cli.devin.ai",
 Self::Antigravity => "antigravity.google/docs/cli/overview",
 Self::Copilot => "https://github.com/github/copilot-cli",
 Self::OpenAi | Self::Gemini | Self::ACP => "",
 }
 }

 pub fn is_api_key_based(&self) -> bool {
 matches!(self, Self::Deepseek | Self::Meta | Self::OpenAi | Self::Gemini)
 }

 pub fn api_host(&self) -> Option<&'static str> {
 match self {
 Self::Deepseek => Some("api.deepseek.com"),
 Self::Meta => Some("api.meta.ai/v1"),
 Self::OpenAi => Some("api.openai.com"),
 Self::Gemini => Some("generativelanguage.googleapis.com"),
 _ => None,
 }
 }

 pub fn api_key_source(&self) -> Option<&'static str> {
 match self {
 Self::Deepseek => Some("platform.deepseek.com"),
 Self::Meta => Some("dev.meta.ai"),
 Self::OpenAi => Some("platform.openai.com"),
 Self::Gemini => Some("aistudio.google.com"),
 _ => None,
 }
 }

 pub fn api_key_env_var(&self) -> Option<&'static str> {
 match self {
 Self::Deepseek => Some("DEEPSEEK_API_KEY"),
 Self::Meta => Some("MODEL_API_KEY"),
 Self::OpenAi => Some("OPENAI_API_KEY"),
 Self::Gemini => Some("GEMINI_API_KEY"),
 _ => None,
 }
 }

 pub fn supports_rewind(&self) -> bool {
 matches!(self, Self::Codex | Self::Claude | Self::Copilot)
 }

 pub fn supports_images(&self) -> bool {
 !matches!(self, Self::Grok | Self::Antigravity)
 }

 pub fn uses_acp(&self) -> bool {
 matches!(self, Self::Cursor | Self::Opencode | Self::Grok | Self::Devin | Self::ACP)
 }
}

// ---------------------------------------------------------------------------
// RuntimeMode (mirrors Swift RuntimeMode)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RuntimeMode {
 Supervised,
 AutoAcceptEdits,
 Auto,
 FullAccess,
}

impl Default for RuntimeMode {
 fn default() -> Self {
 Self::Supervised
 }
}

impl fmt::Display for RuntimeMode {
 fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
 let s = match self {
 Self::Supervised => "supervised",
 Self::AutoAcceptEdits => "auto_accept_edits",
 Self::Auto => "auto",
 Self::FullAccess => "full_access",
 };
 write!(f, "{s}")
 }
}

impl RuntimeMode {
 pub fn title(&self) -> &'static str {
 match self {
 Self::Supervised => "Supervised",
 Self::AutoAcceptEdits => "Auto-accept edits",
 Self::Auto => "Auto",
 Self::FullAccess => "Full access",
 }
 }

 pub fn summary(&self) -> &'static str {
 match self {
 Self::Supervised => "Asks before commands and file changes",
 Self::AutoAcceptEdits => "Edits files freely, asks before other actions",
 Self::Auto => "The provider's reviewer approves routine actions",
 Self::FullAccess => "Runs commands and edits without asking",
 }
 }

 pub fn symbol(&self) -> &'static str {
 match self {
 Self::Supervised => "hand.raised",
 Self::AutoAcceptEdits => "pencil.line",
 Self::Auto => "wand.and.sparkles",
 Self::FullAccess => "lock.open",
 }
 }
}

// ---------------------------------------------------------------------------
// InteractionMode (mirrors Swift InteractionMode)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum InteractionMode {
 Build,
 Plan,
}

impl Default for InteractionMode {
 fn default() -> Self {
 Self::Build
 }
}

impl fmt::Display for InteractionMode {
 fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
 let s = match self {
 Self::Build => "build",
 Self::Plan => "plan",
 };
 write!(f, "{s}")
 }
}

// ---------------------------------------------------------------------------
// WorkspaceMode (mirrors Swift WorkspaceMode)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum WorkspaceMode {
 Local,
 Worktree,
}

impl Default for WorkspaceMode {
 fn default() -> Self {
 Self::Local
 }
}

impl fmt::Display for WorkspaceMode {
 fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
 let s = match self {
 Self::Local => "local",
 Self::Worktree => "worktree",
 };
 write!(f, "{s}")
 }
}

impl WorkspaceMode {
 pub fn title(&self) -> &'static str {
 match self {
 Self::Local => "Local",
 Self::Worktree => "New worktree",
 }
 }
}

// ---------------------------------------------------------------------------
// Provider status (whether the CLI is installed, authenticated, etc.)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProviderStatus {
 pub provider: ProviderKind,
 pub is_installed: bool,
 pub is_authenticated: bool,
 pub version: Option<String>,
 pub last_checked: Option<chrono::DateTime<chrono::Utc>>,
 pub error: Option<String>,
}

// ---------------------------------------------------------------------------
// ModelInfo (mirrors Swift ModelOption)
// ---------------------------------------------------------------------------

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

impl ModelInfo {
 pub fn supports_fast(&self) -> bool {
 self.fast_tier.is_some()
 }
}

/// Backwards-compat alias used throughout the codebase.
pub type ModelOption = ModelInfo;

// ---------------------------------------------------------------------------
// ProviderType — a more general enum to mirror Swift's "provider type" concept
// (CLI vs API-key, native vs ACP). Stored alongside Provider for metadata.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderType {
 /// Talks to a local CLI subprocess
 Cli,
 /// Talks to a cloud API directly with an API key
 ApiKey,
 /// ACP-based integration
 Acp,
 /// Native agent framework (Claude, Codex, Copilot style)
 Native,
}

impl ProviderType {
 pub fn for_kind(kind: ProviderKind) -> Self {
 if kind.uses_acp() {
 Self::Acp
 } else if kind.is_api_key_based() {
 Self::ApiKey
 } else if matches!(kind, ProviderKind::Claude | ProviderKind::Codex | ProviderKind::Copilot) {
 Self::Native
 } else {
 Self::Cli
 }
 }
}

// ---------------------------------------------------------------------------
// A pinned model reference used in AppSettings.model_list.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct ModelPin {
 pub provider: ProviderKind,
 pub model_id: String,
}

impl ModelPin {
 pub fn id(&self) -> String {
 format!("{}/{}", self.provider, self.model_id)
 }
}

// ---------------------------------------------------------------------------
// Provider — the persisted record for a configured provider
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provider {
 pub id: Uuid,
 pub provider_type: ProviderType,
 pub kind: ProviderKind,
 pub name: String,
 pub api_key: Option<String>,
 pub base_url: Option<String>,
 pub executable_path: Option<String>,
 pub models: Vec<ModelInfo>,
 pub default_model_id: Option<String>,
 pub enabled: bool,
 pub is_default: bool,
 pub installed: bool,
 pub authenticated: bool,
 pub version: Option<String>,
 pub status_message: Option<String>,
 pub created_at: chrono::DateTime<chrono::Utc>,
 pub updated_at: chrono::DateTime<chrono::Utc>,
 pub last_tested_at: Option<chrono::DateTime<chrono::Utc>>,
}

impl Default for Provider {
 fn default() -> Self {
 let now = chrono::Utc::now();
 Self {
 id: Uuid::new_v4(),
 provider_type: ProviderType::Cli,
 kind: ProviderKind::Codex,
 name: ProviderKind::Codex.display_name().to_string(),
 api_key: None,
 base_url: None,
 executable_path: None,
 models: Vec::new(),
 default_model_id: None,
 enabled: true,
 is_default: false,
 installed: false,
 authenticated: false,
 version: None,
 status_message: None,
 created_at: now,
 updated_at: now,
 last_tested_at: None,
 }
 }
}

impl Provider {
 pub fn new(kind: ProviderKind) -> Self {
 let now = chrono::Utc::now();
 Self {
 id: Uuid::new_v4(),
 provider_type: ProviderType::for_kind(kind),
 kind,
 name: kind.display_name().to_string(),
 api_key: None,
 base_url: kind.api_host().map(|s| s.to_string()),
 executable_path: None,
 models: Vec::new(),
 default_model_id: None,
 enabled: true,
 is_default: false,
 installed: false,
 authenticated: false,
 version: None,
 status_message: None,
 created_at: now,
 updated_at: now,
 last_tested_at: None,
 }
 }

 pub fn default_model(&self) -> Option<&ModelInfo> {
 if let Some(id) = &self.default_model_id {
 self.models.iter().find(|m| &m.id == id)
 } else {
 self.models.iter().find(|m| m.is_default).or_else(|| self.models.first())
 }
 }

 pub fn touch(&mut self) {
 self.updated_at = chrono::Utc::now();
 }
}

// ---------------------------------------------------------------------------
// SlashCommand (mirrors Swift SlashCommand)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlashCommand {
 pub name: String,
 pub detail: String,
 pub is_built_in: bool,
}
