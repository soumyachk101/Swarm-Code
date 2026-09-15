use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::models::provider::{ModelOption, ProviderKind, ProviderType};
use crate::providers::session::{ProviderError, ProviderSession, SessionStatus};
use crate::providers::plan_limits::PlanLimits;
use crate::types::{ProviderCredits, ProviderTestResult};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error, Clone)]
pub enum RegistryError {
    #[error("provider {0:?} is not registered")]
    NotRegistered(ProviderKind),

    #[error("provider {0:?} is not installed: {1}")]
    NotInstalled(ProviderKind, String),

    #[error("provider {0:?} is not authenticated: {1}")]
    NotAuthenticated(ProviderKind, String),

    #[error("provider {0:?} failed to start: {1}")]
    StartFailed(ProviderKind, String),

    #[error("no providers are available")]
    NoProvidersAvailable,

    #[error("no active session for provider {0:?}")]
    NoActiveSession(ProviderKind),

    #[error("duplicate provider kind {0:?}")]
    DuplicateProvider(ProviderKind),
}

pub type RegistryResult<T> = Result<T, RegistryError>;

// ---------------------------------------------------------------------------
// Provider capability metadata
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProviderCapabilities {
    /// Provider supports rewinding conversation history
    pub supports_rewind: bool,
    /// Provider can process image attachments
    pub supports_images: bool,
    /// Provider uses the Agent Client Protocol
    pub uses_acp: bool,
    /// Provider authenticates via API key rather than CLI login
    pub is_api_key_based: bool,
    /// CLI executable name (for non-API providers)
    pub executable_name: String,
    /// API host endpoint (for API-key providers)
    pub api_host: Option<String>,
    /// Environment variable name for the API key
    pub api_key_env_var: Option<String>,
    /// URL for obtaining an API key
    pub api_key_source_url: Option<String>,
    /// Login command for CLI-based providers
    pub login_command: String,
    /// Installation/documentation URL
    pub install_url: String,
    /// Human-readable icon name
    pub icon_name: String,
    /// Short description of the provider
    pub description: String,
}

impl ProviderCapabilities {
    /// Build capabilities from a ProviderKind using the static tables
    /// defined on ProviderKind.
    pub fn for_kind(kind: ProviderKind) -> Self {
        Self {
            supports_rewind: kind.supports_rewind(),
            supports_images: kind.supports_images(),
            uses_acp: kind.uses_acp(),
            is_api_key_based: kind.is_api_key_based(),
            executable_name: kind.executable_name().to_string(),
            api_host: kind.api_host().map(|s| s.to_string()),
            api_key_env_var: kind.api_key_env_var().map(|s| s.to_string()),
            api_key_source_url: kind.api_key_source().map(|s| s.to_string()),
            login_command: kind.login_command().to_string(),
            install_url: kind.install_url().to_string(),
            icon_name: kind.icon_name(),
            description: format!("{} coding agent", kind.display_name()),
        }
    }

    pub fn provider_type(&self) -> ProviderType {
        if self.uses_acp {
            ProviderType::Acp
        } else if self.is_api_key_based {
            ProviderType::ApiKey
        } else if matches!(
            self.executable_name.as_str(),
            "claude" | "codex" | "copilot"
        ) {
            ProviderType::Native
        } else {
            ProviderType::Cli
        }
    }
}

// ---------------------------------------------------------------------------
// Provider descriptor — full metadata for one registered provider
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderDescriptor {
    pub kind: ProviderKind,
    pub capabilities: ProviderCapabilities,
    pub provider_type: ProviderType,
    pub description: String,
    pub models: Vec<ModelOption>,
    pub default_model_id: Option<String>,
    pub enabled: bool,
    pub is_default: bool,
}

impl ProviderDescriptor {
    pub fn new(kind: ProviderKind) -> Self {
        let capabilities = ProviderCapabilities::for_kind(kind);
        let provider_type = capabilities.provider_type();
        Self {
            kind,
            capabilities,
            provider_type,
            description: format!("{} coding agent", kind.display_name()),
            models: Vec::new(),
            default_model_id: None,
            enabled: true,
            is_default: false,
        }
    }

    /// The default model for this provider, preferring the stored default
    /// model id, then any seeded default, then the first available model.
    pub fn default_model(&self) -> Option<&ModelOption> {
        if let Some(id) = &self.default_model_id {
            if let Some(m) = self.models.iter().find(|m| &m.id == id) {
                return Some(m);
            }
        }
        self.models.iter().find(|m| m.is_default).or_else(|| self.models.first())
    }

    /// Whether the provider currently has at least one known model.
    pub fn has_models(&self) -> bool {
        !self.models.is_empty()
    }

    /// Returns true if this provider appears installed / usable.
    pub fn is_usable(&self) -> bool {
        self.enabled && !self.models.is_empty()
    }
}

// ---------------------------------------------------------------------------
// Provider status — runtime state (installed, authenticated, version, …)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderStatus {
    pub provider: ProviderKind,
    pub is_installed: bool,
    pub is_authenticated: bool,
    pub version: Option<String>,
    pub last_checked: Option<DateTime<Utc>>,
    pub error: Option<String>,
    pub is_checking: bool,
}

impl ProviderStatus {
    pub fn not_installed(provider: ProviderKind, reason: impl Into<String>) -> Self {
        Self {
            provider,
            is_installed: false,
            is_authenticated: false,
            error: Some(reason.into()),
            ..Self::default()
        }
    }

    pub fn installed(provider: ProviderKind, version: Option<String>) -> Self {
        Self {
            provider,
            is_installed: true,
            is_authenticated: true,
            version,
            ..Self::default()
        }
    }

    pub fn summary(&self) -> String {
        if !self.is_installed {
            return format!("{} — Not installed", self.provider.display_name());
        }
        if !self.is_authenticated {
            return format!("{} — Not authenticated", self.provider.display_name());
        }
        if let Some(ref version) = self.version {
            format!("{} — Installed ({})", self.provider.display_name(), version)
        } else {
            format!("{} — Installed", self.provider.display_name())
        }
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
    pub checked_at: DateTime<Utc>,
}

impl ValidationResult {
    pub fn success(provider: ProviderKind) -> Self {
        Self {
            valid: true,
            provider,
            error: None,
            checked_at: Utc::now(),
        }
    }

    pub fn failure(provider: ProviderKind, error: impl Into<String>) -> Self {
        Self {
            valid: false,
            provider,
            error: Some(error.into()),
            checked_at: Utc::now(),
        }
    }
}

// ---------------------------------------------------------------------------
// Session factory type
// ---------------------------------------------------------------------------

pub type SessionFactory =
    Arc<dyn Fn(ProviderKind) -> Result<Box<dyn ProviderSession>, ProviderError> + Send + Sync>;

// ---------------------------------------------------------------------------
// Plan limits cache entry
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CachedPlanLimits {
    pub limits: Option<PlanLimits>,
    pub fetched_at: Option<DateTime<Utc>>,
}

impl CachedPlanLimits {
    pub fn new(limits: PlanLimits) -> Self {
        Self {
            limits: Some(limits),
            fetched_at: Some(Utc::now()),
        }
    }

    pub fn is_fresh(&self, max_age_seconds: i64) -> bool {
        match self.fetched_at {
            Some(fetched) => {
                let age = (Utc::now() - fetched).num_seconds();
                age < max_age_seconds
            }
            None => false,
        }
    }
}

// ---------------------------------------------------------------------------
// Credits cache entry
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CachedCredits {
    pub credits: Option<ProviderCredits>,
    pub fetched_at: Option<DateTime<Utc>>,
}

impl CachedCredits {
    pub fn new(credits: ProviderCredits) -> Self {
        Self {
            credits: Some(credits),
            fetched_at: Some(Utc::now()),
        }
    }

    pub fn is_fresh(&self, max_age_seconds: i64) -> bool {
        match self.fetched_at {
            Some(fetched) => {
                let age = (Utc::now() - fetched).num_seconds();
                age < max_age_seconds
            }
            None => false,
        }
    }
}

// ---------------------------------------------------------------------------
// Provider registry
// ---------------------------------------------------------------------------

pub struct ProviderRegistry {
    /// All registered provider descriptors, keyed by kind.
    descriptors: HashMap<ProviderKind, ProviderDescriptor>,
    /// Runtime status for each provider.
    statuses: HashMap<ProviderKind, ProviderStatus>,
    /// Live model catalogs for each provider.
    catalogs: HashMap<ProviderKind, Vec<ModelOption>>,
    /// Cached plan limits for each provider.
    plan_limits: HashMap<ProviderKind, CachedPlanLimits>,
    /// Cached credit balances for pay-as-you-go providers.
    credits: HashMap<ProviderKind, CachedCredits>,
    /// Factory function for creating provider sessions.
    session_factory: Option<SessionFactory>,
    /// Seed model options for providers that have static model lists.
    seeded_catalogs: HashMap<ProviderKind, Vec<ModelOption>>,
    /// Which providers have had their catalogs loaded at least once this session.
    attempted_catalogs: HashSet<ProviderKind>,
    /// Which providers are currently loading their catalog.
    loading_catalogs: HashSet<ProviderKind>,
    /// Which providers are currently loading plan limits.
    loading_limits: HashSet<ProviderKind>,
    /// Which providers are currently loading credits.
    loading_credits: HashSet<ProviderKind>,
}

impl Default for ProviderRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl ProviderRegistry {
    /// Create a new registry with all built-in providers registered.
    pub fn new() -> Self {
        let mut reg = Self {
            descriptors: HashMap::new(),
            statuses: HashMap::new(),
            catalogs: HashMap::new(),
            plan_limits: HashMap::new(),
            credits: HashMap::new(),
            session_factory: None,
            seeded_catalogs: HashMap::new(),
            attempted_catalogs: HashSet::new(),
            loading_catalogs: HashSet::new(),
            loading_limits: HashSet::new(),
            loading_credits: HashSet::new(),
        };
        reg.register_defaults();
        reg
    }

    /// Try to detect available providers on the current system.
    pub fn detect() -> RegistryResult<Self> {
        let registry = Self::new();
        // In a real implementation this would probe the PATH, check API keys, etc.
        // For now we simply return the default registry — the Rust side is
        // responsible for probing binaries on demand during status refresh.
        Ok(registry)
    }

    /// Register all built-in providers with their seed models and metadata.
    fn register_defaults(&mut self) {
        // -- Claude --
        let claude_seed = vec![
            ModelOption {
                id: "default".to_string(),
                name: "Default".to_string(),
                detail: Some("Claude Code's recommended model".to_string()),
                efforts: vec!["low", "medium", "high", "xhigh", "max"],
                default_effort: Some("high".to_string()),
                is_default: true,
                fast_tier: Some("fast".to_string()),
            },
            ModelOption {
                id: "opus".to_string(),
                name: "Opus".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high", "xhigh", "max"],
                default_effort: None,
                is_default: false,
                fast_tier: Some("fast".to_string()),
            },
            ModelOption {
                id: "claude-fable-5-1[1m]".to_string(),
                name: "Fable".to_string(),
                detail: Some("Fable 5.1 · Most capable for your hardest and longest-running tasks".to_string()),
                efforts: vec!["low", "medium", "high", "xhigh", "max"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "sonnet".to_string(),
                name: "Sonnet".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high", "xhigh", "max"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "haiku".to_string(),
                name: "Haiku".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
        ];
        self.register_provider_with_seed(ProviderKind::Claude, claude_seed);

        // -- Codex --
        let codex_descriptor = ProviderDescriptor::new(ProviderKind::Codex);
        self.descriptors.insert(ProviderKind::Codex, codex_descriptor);

        // -- Copilot --
        let copilot_seed = vec![ModelOption {
            id: "auto".to_string(),
            name: "Auto".to_string(),
            detail: Some("Copilot picks the model for each request".to_string()),
            efforts: vec![],
            default_effort: None,
            is_default: true,
            fast_tier: None,
        }];
        self.seeded_catalogs
            .insert(ProviderKind::Copilot, copilot_seed.clone());
        self.register_provider_with_seed(ProviderKind::Copilot, copilot_seed);

        // -- DeepSeek --
        let deepseek_seed = vec![
            ModelOption {
                id: "deepseek-v4-pro".to_string(),
                name: "DeepSeek V4 Pro".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: Some("medium".to_string()),
                is_default: true,
                fast_tier: None,
            },
            ModelOption {
                id: "deepseek-flash".to_string(),
                name: "DeepSeek Flash".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: Some("fast".to_string()),
            },
        ];
        self.seeded_catalogs
            .insert(ProviderKind::Deepseek, deepseek_seed.clone());
        self.register_provider_with_seed(ProviderKind::Deepseek, deepseek_seed);

        // -- Meta --
        let meta_seed = vec![
            ModelOption {
                id: "muse-spark-1.3".to_string(),
                name: "Muse Spark 1.3".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: true,
                fast_tier: None,
            },
            ModelOption {
                id: "muse-spark-1.3-contributor".to_string(),
                name: "Muse Spark 1.3 Contributor".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "muse-spark-1.2".to_string(),
                name: "Muse Spark 1.2".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "muse-spark-1.2-contributor".to_string(),
                name: "Muse Spark 1.2 Contributor".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "muse-spark-1.1".to_string(),
                name: "Muse Spark 1.1".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
        ];
        self.seeded_catalogs
            .insert(ProviderKind::Meta, meta_seed.clone());
        self.register_provider_with_seed(ProviderKind::Meta, meta_seed);

        // -- Antigravity --
        let antigravity_seed = vec![
            ModelOption {
                id: "gemini-3.8-flash".to_string(),
                name: "Gemini 3.8 Flash".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: Some("high".to_string()),
                is_default: true,
                fast_tier: None,
            },
            ModelOption {
                id: "gemini-3.7-flash".to_string(),
                name: "Gemini 3.7 Flash".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: Some("high".to_string()),
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "gemini-3.6-flash".to_string(),
                name: "Gemini 3.6 Flash".to_string(),
                detail: None,
                efforts: vec!["low", "medium", "high"],
                default_effort: Some("high".to_string()),
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "gemini-3.1-pro".to_string(),
                name: "Gemini 3.1 Pro".to_string(),
                detail: None,
                efforts: vec!["low", "high"],
                default_effort: Some("high".to_string()),
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "claude-sonnet-4-6".to_string(),
                name: "Claude Sonnet 4.6 (Thinking)".to_string(),
                detail: None,
                efforts: vec![],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "claude-opus-4-6-thinking".to_string(),
                name: "Claude Opus 4.6 (Thinking)".to_string(),
                detail: None,
                efforts: vec![],
                default_effort: None,
                is_default: false,
                fast_tier: None,
            },
            ModelOption {
                id: "gpt-oss-120b".to_string(),
                name: "GPT-OSS 120B".to_string(),
                detail: None,
                efforts: vec!["medium"],
                default_effort: Some("medium".to_string()),
                is_default: false,
                fast_tier: None,
            },
        ];
        self.seeded_catalogs
            .insert(ProviderKind::Antigravity, antigravity_seed.clone());
        self.register_provider_with_seed(ProviderKind::Antigravity, antigravity_seed);

        // -- Remaining providers without seed models --
        let remaining = [
            ProviderKind::Cursor,
            ProviderKind::Opencode,
            ProviderKind::Grok,
            ProviderKind::Devin,
            ProviderKind::OpenAi,
            ProviderKind::Gemini,
            ProviderKind::ACP,
        ];
        for kind in &remaining {
            self.descriptors.insert(*kind, ProviderDescriptor::new(*kind));
        }
    }

    fn register_provider_with_seed(&mut self, kind: ProviderKind, seed: Vec<ModelOption>) {
        let mut descriptor = ProviderDescriptor::new(kind);
        descriptor.models = seed.clone();
        self.catalogs.insert(kind, seed);
        self.descriptors.insert(kind, descriptor);
    }

    // -----------------------------------------------------------------------
    // Session factory
    // -----------------------------------------------------------------------

    /// Set the factory used to create provider sessions on demand.
    pub fn set_session_factory(&mut self, factory: SessionFactory) {
        self.session_factory = Some(factory);
    }

    /// Create a new session for the given provider kind.
    pub fn create_session(
        &self,
        kind: ProviderKind,
    ) -> RegistryResult<Box<dyn ProviderSession>> {
        let factory = self.session_factory.as_ref().ok_or_else(|| {
            RegistryError::StartFailed(kind, "no session factory configured".to_string())
        })?;
        factory(kind).map_err(|e| RegistryError::StartFailed(kind, e.message))
    }

    // -----------------------------------------------------------------------
    // Registration / access
    // -----------------------------------------------------------------------

    /// Get a provider descriptor by kind.
    pub fn get(&self, kind: ProviderKind) -> Option<&ProviderDescriptor> {
        self.descriptors.get(&kind)
    }

    /// Get a mutable provider descriptor by kind.
    pub fn get_mut(&mut self, kind: ProviderKind) -> Option<&mut ProviderDescriptor> {
        self.descriptors.get_mut(&kind)
    }

    /// List all registered provider kinds.
    pub fn list(&self) -> Vec<ProviderKind> {
        let mut kinds: Vec<_> = self.descriptors.keys().copied().collect();
        kinds.sort_by_key(|k| k.display_name());
        kinds
    }

    /// List only the enabled provider kinds.
    pub fn list_enabled(&self) -> Vec<ProviderKind> {
        self.list()
            .into_iter()
            .filter(|k| {
                self.descriptors
                    .get(k)
                    .map(|d| d.enabled)
                    .unwrap_or(false)
            })
            .collect()
    }

    /// List provider kinds that are currently usable (enabled and have models).
    pub fn list_available(&self) -> Vec<ProviderKind> {
        self.list()
            .into_iter()
            .filter(|k| {
                self.descriptors
                    .get(k)
                    .map(|d| d.is_usable())
                    .unwrap_or(false)
            })
            .collect()
    }

    /// Register a new provider descriptor. Returns Err if the kind is already registered.
    pub fn register(&mut self, descriptor: ProviderDescriptor) -> RegistryResult<()> {
        let kind = descriptor.kind;
        if self.descriptors.contains_key(&kind) {
            return Err(RegistryError::DuplicateProvider(kind));
        }
        self.descriptors.insert(kind, descriptor);
        Ok(())
    }

    /// Update an existing provider descriptor.
    pub fn update(&mut self, descriptor: ProviderDescriptor) -> RegistryResult<()> {
        let kind = descriptor.kind;
        if !self.descriptors.contains_key(&kind) {
            return Err(RegistryError::NotRegistered(kind));
        }
        self.descriptors.insert(kind, descriptor);
        Ok(())
    }

    /// Enable a provider.
    pub fn enable(&mut self, kind: ProviderKind) -> RegistryResult<()> {
        self.get_mut(kind)
            .map(|d| d.enabled = true)
            .ok_or_else(|| RegistryError::NotRegistered(kind))
    }

    /// Disable a provider.
    pub fn disable(&mut self, kind: ProviderKind) -> RegistryResult<()> {
        self.get_mut(kind)
            .map(|d| d.enabled = false)
            .ok_or_else(|| RegistryError::NotRegistered(kind))
    }

    /// Check whether a provider is registered.
    pub fn has(&self, kind: ProviderKind) -> bool {
        self.descriptors.contains_key(&kind)
    }

    /// Check whether a provider is enabled.
    pub fn is_enabled(&self, kind: ProviderKind) -> bool {
        self.descriptors
            .get(&kind)
            .map(|d| d.enabled)
            .unwrap_or(false)
    }

    /// Set the default provider.
    pub fn set_default(&mut self, kind: ProviderKind) -> RegistryResult<()> {
        // Unset previous default.
        for (_, desc) in self.descriptors.iter_mut() {
            desc.is_default = false;
        }
        self.get_mut(kind)
            .map(|d| d.is_default = true)
            .ok_or_else(|| RegistryError::NotRegistered(kind))
    }

    /// Get the current default provider, if any.
    pub fn default_provider(&self) -> Option<&ProviderDescriptor> {
        self.descriptors
            .values()
            .find(|d| d.is_default && d.enabled)
    }

    // -----------------------------------------------------------------------
    // Model / catalog management
    // -----------------------------------------------------------------------

    /// Get the model catalog for a provider.
    pub fn models(&self, kind: ProviderKind) -> Vec<ModelOption> {
        self.catalogs.get(&kind).cloned().unwrap_or_default()
    }

    /// Get a single model by id from a provider's catalog.
    pub fn model(&self, kind: ProviderKind, id: &str) -> Option<&ModelOption> {
        self.catalogs.get(&kind).and_then(|list| list.iter().find(|m| m.id == id))
    }

    /// Update the model catalog for a provider.
    pub fn update_catalog(&mut self, kind: ProviderKind, models: Vec<ModelOption>) {
        if models.is_empty() {
            return;
        }
        let is_new = self.catalogs.get(&kind).map(|c| c.is_empty()).unwrap_or(true);
        self.catalogs.insert(kind, models);
        // Also update the descriptor's model list.
        if let Some(descriptor) = self.descriptors.get_mut(&kind) {
            descriptor.models = self.catalogs.get(&kind).cloned().unwrap_or_default();
        }
        // If this was the first successful load, remove the seed so a later
        // reload can replace it with the live catalog.
        if is_new {
            self.seeded_catalogs.remove(&kind);
        }
        self.attempted_catalogs.insert(kind);
    }

    /// Set a seed model list (static defaults) for a provider.
    pub fn seed_catalog(&mut self, kind: ProviderKind, models: Vec<ModelOption>) {
        self.seeded_catalogs.insert(kind, models.clone());
        // Only seed if the catalog is currently empty.
        if self.catalogs.get(&kind).map(|c| c.is_empty()).unwrap_or(true) {
            self.catalogs.insert(kind, models);
            if let Some(descriptor) = self.descriptors.get_mut(&kind) {
                descriptor.models = self.catalogs.get(&kind).cloned().unwrap_or_default();
            }
        }
    }

    /// Whether a provider has at least one model available.
    pub fn has_models(&self, kind: ProviderKind) -> bool {
        self.catalogs
            .get(&kind)
            .map(|c| !c.is_empty())
            .unwrap_or(false)
    }

    /// Whether the catalog for a provider was already attempted this session.
    pub fn catalog_attempted(&self, kind: ProviderKind) -> bool {
        self.attempted_catalogs.contains(&kind)
    }

    /// Mark the catalog for a provider as loading.
    pub fn set_catalog_loading(&mut self, kind: ProviderKind, loading: bool) {
        if loading {
            self.loading_catalogs.insert(kind);
        } else {
            self.loading_catalogs.remove(&kind);
        }
    }

    /// Whether a provider's catalog is currently loading.
    pub fn is_catalog_loading(&self, kind: ProviderKind) -> bool {
        self.loading_catalogs.contains(&kind)
    }

    // -----------------------------------------------------------------------
    // Plan limits
    // -----------------------------------------------------------------------

    /// Get cached plan limits for a provider.
    pub fn plan_limits(&self, kind: ProviderKind) -> Option<&PlanLimits> {
        self.plan_limits.get(&kind).and_then(|c| c.limits.as_ref())
    }

    /// Set plan limits for a provider.
    pub fn set_plan_limits(&mut self, kind: ProviderKind, limits: PlanLimits) {
        self.plan_limits
            .insert(kind, CachedPlanLimits::new(limits));
    }

    /// Whether plan limits for a provider are fresh enough.
    pub fn plan_limits_are_fresh(&self, kind: ProviderKind, max_age_seconds: i64) -> bool {
        self.plan_limits
            .get(&kind)
            .map(|c| c.is_fresh(max_age_seconds))
            .unwrap_or(false)
    }

    /// Whether plan limits are currently loading for a provider.
    pub fn is_loading_limits(&self, kind: ProviderKind) -> bool {
        self.loading_limits.contains(&kind)
    }

    /// Set plan-limits loading state for a provider.
    pub fn set_loading_limits(&mut self, kind: ProviderKind, loading: bool) {
        if loading {
            self.loading_limits.insert(kind);
        } else {
            self.loading_limits.remove(&kind);
        }
    }

    // -----------------------------------------------------------------------
    // Credits
    // -----------------------------------------------------------------------

    /// Get cached credits for a provider.
    pub fn credits(&self, kind: ProviderKind) -> Option<&ProviderCredits> {
        self.credits.get(&kind).and_then(|c| c.credits.as_ref())
    }

    /// Set credits for a provider.
    pub fn set_credits(&mut self, kind: ProviderKind, credits: ProviderCredits) {
        self.credits
            .insert(kind, CachedCredits::new(credits));
    }

    /// Whether credits for a provider are fresh enough.
    pub fn credits_are_fresh(&self, kind: ProviderKind, max_age_seconds: i64) -> bool {
        self.credits
            .get(&kind)
            .map(|c| c.is_fresh(max_age_seconds))
            .unwrap_or(false)
    }

    /// Whether credits are currently loading for a provider.
    pub fn is_loading_credits(&self, kind: ProviderKind) -> bool {
        self.loading_credits.contains(&kind)
    }

    /// Set credits loading state for a provider.
    pub fn set_loading_credits(&mut self, kind: ProviderKind, loading: bool) {
        if loading {
            self.loading_credits.insert(kind);
        } else {
            self.loading_credits.remove(&kind);
        }
    }

    // -----------------------------------------------------------------------
    // Validation
    // -----------------------------------------------------------------------

    /// Validate a provider: returns true if it is registered and usable.
    pub fn validate(&self, kind: ProviderKind) -> ValidationResult {
        match self.descriptors.get(&kind) {
            None => ValidationResult::failure(kind, format!("{:?} is not registered", kind)),
            Some(desc) if !desc.enabled => {
                ValidationResult::failure(kind, format!("{:?} is disabled", kind))
            }
            Some(desc) if desc.models.is_empty() => {
                ValidationResult::failure(kind, format!("{:?} has no available models", kind))
            }
            Some(desc) => ValidationResult::success(kind),
        }
    }

    /// Check whether a provider is installed. For CLI providers this means
    /// the executable was found; for API-key providers it means a key is set.
    pub fn is_installed(&self, kind: ProviderKind) -> bool {
        self.statuses
            .get(&kind)
            .map(|s| s.is_installed)
            .unwrap_or_else(|| {
                // Fallback: API-key-based providers with no status are
                // considered potentially installed.
                kind.is_api_key_based()
            })
    }

    /// Check whether a provider is authenticated.
    pub fn is_authenticated(&self, kind: ProviderKind) -> bool {
        self.statuses
            .get(&kind)
            .map(|s| s.is_authenticated)
            .unwrap_or(false)
    }

    /// Validate and return an error if the provider is not ready to use.
    pub fn ensure_available(&self, kind: ProviderKind) -> RegistryResult<()> {
        if !self.has(kind) {
            return Err(RegistryError::NotRegistered(kind));
        }
        if !self.is_enabled(kind) {
            return Err(RegistryError::NotInstalled(
                kind,
                format!("{:?} is disabled", kind),
            ));
        }
        if !self.is_installed(kind) {
            return Err(RegistryError::NotInstalled(
                kind,
                format!("{:?} is not installed", kind),
            ));
        }
        if !self.is_authenticated(kind) {
            return Err(RegistryError::NotAuthenticated(
                kind,
                format!("{:?} is not authenticated", kind),
            ));
        }
        if !self.has_models(kind) {
            return Err(RegistryError::NotInstalled(
                kind,
                format!("{:?} has no available models", kind),
            ));
        }
        Ok(())
    }

    /// Validate all registered providers and return a map of results.
    pub fn validate_all(&self) -> HashMap<ProviderKind, ValidationResult> {
        ProviderKind::ALL
            .iter()
            .map(|&k| (k, self.validate(k)))
            .collect()
    }

    /// Validate only the currently enabled providers.
    pub fn validate_enabled(&self) -> HashMap<ProviderKind, ValidationResult> {
        self.list_enabled()
            .into_iter()
            .map(|k| (k, self.validate(k)))
            .collect()
    }

    // -----------------------------------------------------------------------
    // Runtime status
    // -----------------------------------------------------------------------

    /// Get the runtime status for a provider.
    pub fn status(&self, kind: ProviderKind) -> ProviderStatus {
        self.statuses.get(&kind).cloned().unwrap_or_else(|| {
            ProviderStatus::not_installed(kind, "not yet checked")
        })
    }

    /// Get statuses for all providers.
    pub fn all_statuses(&self) -> Vec<(ProviderKind, ProviderStatus)> {
        ProviderKind::ALL
            .iter()
            .map(|&k| (k, self.status(k)))
            .collect()
    }

    /// Update the runtime status for a provider.
    pub fn set_status(&mut self, kind: ProviderKind, status: ProviderStatus) {
        self.statuses.insert(kind, status);
    }

    /// Set a provider as installed and authenticated with an optional version.
    pub fn mark_installed(&mut self, kind: ProviderKind, version: Option<String>) {
        self.statuses
            .insert(kind, ProviderStatus::installed(kind, version));
    }

    /// Mark a provider as not installed with a reason.
    pub fn mark_not_installed(&mut self, kind: ProviderKind, reason: impl Into<String>) {
        self.statuses
            .insert(kind, ProviderStatus::not_installed(kind, reason));
    }

    /// Check if any provider is currently being refreshed.
    pub fn is_refreshing(&self) -> bool {
        self.statuses
            .values()
            .any(|s| s.is_checking)
            || !self.loading_catalogs.is_empty()
            || !self.loading_limits.is_empty()
            || !self.loading_credits.is_empty()
    }
}

// ---------------------------------------------------------------------------
// ProviderTestResult helpers
// ---------------------------------------------------------------------------

impl ProviderTestResult {
    /// Build a test result from a registry validation.
    pub fn from_validation(kind: ProviderKind, validation: &ValidationResult) -> Self {
        Self {
            kind,
            success: validation.valid,
            message: validation.error.clone(),
            tested_at: validation.checked_at,
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_registry_creation() {
        let registry = ProviderRegistry::new();
        // All 13 provider kinds should be registered.
        assert_eq!(registry.list().len(), 13);
    }

    #[test]
    fn test_default_provider_seeds() {
        let registry = ProviderRegistry::new();
        // Claude should have seed models.
        assert!(registry.has_models(ProviderKind::Claude));
        // Copilot should have the Auto seed row.
        let copilot_models = registry.models(ProviderKind::Copilot);
        assert!(!copilot_models.is_empty());
        assert!(copilot_models.iter().any(|m| m.id == "auto"));
    }

    #[test]
    fn test_validation() {
        let registry = ProviderRegistry::new();
        // All registered providers pass basic validation (enabled, have seeds).
        for kind in ProviderKind::ALL {
            let result = registry.validate(*kind);
            if registry.is_enabled(*kind) && registry.has_models(*kind) {
                assert!(result.valid, "expected {:?} to be valid", kind);
            }
        }
    }

    #[test]
    fn test_enable_disable() {
        let mut registry = ProviderRegistry::new();
        assert!(registry.is_enabled(ProviderKind::Claude));
        registry.disable(ProviderKind::Claude).unwrap();
        assert!(!registry.is_enabled(ProviderKind::Claude));
        registry.enable(ProviderKind::Claude).unwrap();
        assert!(registry.is_enabled(ProviderKind::Claude));
    }

    #[test]
    fn test_default_provider() {
        let mut registry = ProviderRegistry::new();
        assert!(registry.default_provider().is_none());
        registry.set_default(ProviderKind::Claude).unwrap();
        let default = registry.default_provider();
        assert!(default.is_some());
        assert_eq!(default.unwrap().kind, ProviderKind::Claude);
    }

    #[test]
    fn test_catalog_update() {
        let mut registry = ProviderRegistry::new();
        let new_models = vec![ModelOption {
            id: "test-model".to_string(),
            name: "Test Model".to_string(),
            detail: None,
            efforts: vec!["high".to_string()],
            default_effort: None,
            is_default: true,
            fast_tier: None,
        }];
        registry.update_catalog(ProviderKind::Codex, new_models.clone());
        let models = registry.models(ProviderKind::Codex);
        assert_eq!(models.len(), 1);
        assert_eq!(models[0].id, "test-model");
    }

    #[test]
    fn test_ensure_available() {
        let registry = ProviderRegistry::new();
        // Claude has seeds and is enabled, so it should pass basic availability.
        assert!(registry.ensure_available(ProviderKind::Claude).is_ok());
    }

    #[test]
    fn test_descriptor_default_model() {
        let mut registry = ProviderRegistry::new();
        let desc = registry.get_mut(ProviderKind::Claude).unwrap();
        // Claude's default model in the seed is "default".
        let default = desc.default_model();
        assert!(default.is_some());
        assert_eq!(default.unwrap().id, "default");
    }
}
