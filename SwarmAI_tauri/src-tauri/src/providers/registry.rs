use std::collections::HashMap;
use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::models::provider::{ModelOption, ProviderKind};

// ---------------------------------------------------------------------------
// Provider status
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderStatus {
 pub executable: Option<String>,
 pub version: Option<String>,
 pub api_key_configured: bool,
 pub last_error: Option<String>,
}

impl ProviderStatus {
 pub fn is_installed(&self) -> bool {
 self.executable.is_some() || self.api_key_configured
 }
}

// ---------------------------------------------------------------------------
// Validation result
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
 pub valid: bool,
 pub provider: ProviderKind,
 pub error: Option<String>,
 pub checked_at: chrono::DateTime<chrono::Utc>,
}

impl ValidationResult {
 pub fn success(provider: ProviderKind) -> Self {
 Self {
 valid: true,
 provider,
 error: None,
 checked_at: chrono::Utc::now(),
 }
 }

 pub fn failure(provider: ProviderKind, error: impl Into<String>) -> Self {
 Self {
 valid: false,
 provider,
 error: Some(error.into()),
 checked_at: chrono::Utc::now(),
 }
 }
}

// ---------------------------------------------------------------------------
// Provider descriptor
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderDescriptor {
 pub kind: ProviderKind,
 pub metadata: ProviderMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProviderMetadata {
 pub supports_rewind: bool,
 pub supports_images: bool,
 pub uses_acp: bool,
 pub is_api_key_based: bool,
 pub executable_name: String,
}

// ---------------------------------------------------------------------------
// Provider registry
// ---------------------------------------------------------------------------

pub type SessionFactory = Arc<dyn Fn(ProviderKind) -> Result<Box<dyn crate::providers::session::ProviderSession>, String> + Send + Sync>;

pub struct ProviderRegistry {
 providers: HashMap<ProviderKind, ProviderDescriptor>,
}

impl Default for ProviderRegistry {
 fn default() -> Self {
 Self::new()
 }
}

impl ProviderRegistry {
 pub fn new() -> Self {
 let mut reg = Self {
 providers: HashMap::new(),
 };
 reg.init();
 reg
 }

 fn init(&mut self) {
 // Register built-in providers with basic metadata
 self.providers.insert(ProviderKind::Claude, ProviderDescriptor {
 kind: ProviderKind::Claude,
 metadata: ProviderMetadata {
 supports_rewind: true,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: false,
 executable_name: "claude".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Codex, ProviderDescriptor {
 kind: ProviderKind::Codex,
 metadata: ProviderMetadata {
 supports_rewind: true,
 supports_images: false,
 uses_acp: false,
 is_api_key_based: false,
 executable_name: "codex".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Grok, ProviderDescriptor {
 kind: ProviderKind::Grok,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: false,
 uses_acp: true,
 is_api_key_based: false,
 executable_name: "grok".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Cursor, ProviderDescriptor {
 kind: ProviderKind::Cursor,
 metadata: ProviderMetadata {
 supports_rewind: true,
 supports_images: true,
 uses_acp: true,
 is_api_key_based: false,
 executable_name: "cursor-agent".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Deepseek, ProviderDescriptor {
 kind: ProviderKind::Deepseek,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: true,
 executable_name: "".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Meta, ProviderDescriptor {
 kind: ProviderKind::Meta,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: true,
 executable_name: "".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Devin, ProviderDescriptor {
 kind: ProviderKind::Devin,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: true,
 is_api_key_based: false,
 executable_name: "devin".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Antigravity, ProviderDescriptor {
 kind: ProviderKind::Antigravity,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: false,
 uses_acp: false,
 is_api_key_based: false,
 executable_name: "agy".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Copilot, ProviderDescriptor {
 kind: ProviderKind::Copilot,
 metadata: ProviderMetadata {
 supports_rewind: true,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: true,
 executable_name: "copilot".to_string(),
 },
 });
 self.providers.insert(ProviderKind::OpenAi, ProviderDescriptor {
 kind: ProviderKind::OpenAi,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: true,
 executable_name: "".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Gemini, ProviderDescriptor {
 kind: ProviderKind::Gemini,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: false,
 is_api_key_based: true,
 executable_name: "".to_string(),
 },
 });
 self.providers.insert(ProviderKind::Opencode, ProviderDescriptor {
 kind: ProviderKind::Opencode,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: true,
 is_api_key_based: false,
 executable_name: "opencode".to_string(),
 },
 });
 self.providers.insert(ProviderKind::ACP, ProviderDescriptor {
 kind: ProviderKind::ACP,
 metadata: ProviderMetadata {
 supports_rewind: false,
 supports_images: true,
 uses_acp: true,
 is_api_key_based: false,
 executable_name: "acp".to_string(),
 },
 });
 }

 pub fn detect() -> Result<Self, String> {
 Ok(Self::new())
 }

 pub fn list(&self) -> Vec<ProviderKind> {
 let mut kinds: Vec<_> = self.providers.keys().copied().collect();
 kinds.sort_by_key(|k| k.display_name());
 kinds
 }

 pub fn get(&self, kind: ProviderKind) -> Option<&ProviderDescriptor> {
 self.providers.get(&kind)
 }

 pub fn models(&self, _kind: ProviderKind) -> Vec<ModelOption> {
 vec![]
 }

 pub fn statuses(&self) -> Vec<(ProviderKind, ProviderStatus)> {
 self.providers.keys().map(|k| (*k, ProviderStatus::default())).collect()
 }
}
