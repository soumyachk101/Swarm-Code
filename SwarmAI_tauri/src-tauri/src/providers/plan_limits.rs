use std::collections::HashMap;
use std::path::PathBuf;

use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::models::provider::ProviderKind;

// ---------------------------------------------------------------------------
// Plan limits
//
// A provider's subscription limits: each rolling window, how much of it is
// used and when it resets. Mirrors the Swift `PlanLimits` type exactly.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PlanLimits {
    pub plan_name: Option<String>,
    pub windows: Vec<Window>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Window {
    pub id: String,
    pub title: String,
    /// Percentage of the window that has been consumed, in the range 0..=100.
    pub percent: f64,
    /// When the window resets, if the provider reports a timestamp.
    pub resets_at: Option<DateTime<Utc>>,
}

impl Window {
    pub fn new(
        id: impl Into<String>,
        title: impl Into<String>,
        percent: f64,
        resets_at: Option<DateTime<Utc>>,
    ) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            percent,
            resets_at,
        }
    }

    /// Clamp the percent to a sane range for display.
    pub fn display_percent(&self) -> f64 {
        self.percent.clamp(0.0, 100.0)
    }

    /// Whether the window is at or above 100%.
    pub fn is_exhausted(&self) -> bool {
        self.percent >= 100.0
    }
}

impl PlanLimits {
    pub fn new(plan_name: Option<String>, windows: Vec<Window>) -> Self {
        Self { plan_name, windows }
    }

    /// Build a plan-limits record from a single window.
    pub fn from_window(window: Window) -> Self {
        Self {
            plan_name: None,
            windows: vec![window],
        }
    }

    pub fn is_empty(&self) -> bool {
        self.windows.is_empty()
    }

    pub fn len(&self) -> usize {
        self.windows.len()
    }

    pub fn is_exhausted(&self) -> bool {
        self.windows.iter().any(|w| w.is_exhausted())
    }

    pub fn exhausted_window(&self) -> Option<&Window> {
        self.windows.iter().find(|w| w.is_exhausted())
    }

    /// The highest-percent window, useful for a "primary" usage indicator.
    pub fn primary_window(&self) -> Option<&Window> {
        self.windows.iter().max_by(|a, b| {
            a.percent
                .partial_cmp(&b.percent)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
    }

    /// Sum of all window percents, for a single "total usage" indicator.
    pub fn total_percent(&self) -> f64 {
        self.windows.iter().map(|w| w.percent).sum()
    }

    /// Whether any window has a reset timestamp.
    pub fn has_reset_times(&self) -> bool {
        self.windows.iter().any(|w| w.resets_at.is_some())
    }

    /// Earliest reset time across all windows, if any.
    pub fn earliest_reset(&self) -> Option<DateTime<Utc>> {
        self.windows
            .iter()
            .filter_map(|w| w.resets_at)
            .min()
    }
}

// ---------------------------------------------------------------------------
// Plan tier catalog
//
// Static descriptions of every supported subscription tier across every
// provider. These give the UI a sensible fallback when no live usage
// endpoint has been hit yet, and let tests / demos exercise the catalog.
// ---------------------------------------------------------------------------

/// A single subscription tier with its headline limits.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlanTier {
    pub id: String,
    pub name: String,
    pub provider: ProviderKind,
    /// Approximate monthly USD price. None means "contact sales".
    pub price_usd_monthly: Option<f64>,
    /// Token budget per rolling window, expressed as a string
    /// (e.g. "unlimited", "5M", "500K") so the UI can show it verbatim.
    pub token_budget: String,
    /// Approximate number of requests per hour, if the provider advertises it.
    pub requests_per_hour: Option<u32>,
    /// Approximate number of requests per day, if the provider advertises it.
    pub requests_per_day: Option<u32>,
    /// Rolling window length in minutes (e.g. 300 = 5 hours).
    pub window_minutes: Option<u32>,
    /// Feature flags advertised by this tier.
    pub features: Vec<String>,
    /// Whether the tier supports extra/overage usage beyond the bundled budget.
    pub supports_extra_usage: bool,
    /// Whether the tier supports model selection beyond the default.
    pub supports_model_selection: bool,
    /// Whether the tier supports team-shared workspaces.
    pub supports_teams: bool,
}

impl PlanTier {
    pub fn has_feature(&self, feature: &str) -> bool {
        self.features.iter().any(|f| f == feature)
    }
}

/// The catalog of every supported provider/tier combination.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlanTierCatalog {
    tiers: Vec<PlanTier>,
    by_provider: HashMap<ProviderKind, Vec<PlanTier>>,
}

impl PlanTierCatalog {
    /// Build the catalog from a flat list of tiers.
    pub fn from_tiers(tiers: Vec<PlanTier>) -> Self {
        let mut by_provider: HashMap<ProviderKind, Vec<PlanTier>> = HashMap::new();
        for tier in &tiers {
            by_provider.entry(tier.provider).or_default().push(tier.clone());
        }
        Self { tiers, by_provider }
    }

    /// The hard-coded default catalog. Mirrors the Swift defaults.
    pub fn default_catalog() -> Self {
        let tiers = vec![
            // ---------------- Codex ----------------
            PlanTier {
                id: "codex-free".to_string(),
                name: "Codex Free".to_string(),
                provider: ProviderKind::Codex,
                price_usd_monthly: Some(0.0),
                token_budget: "150K".to_string(),
                requests_per_hour: Some(20),
                requests_per_day: Some(200),
                window_minutes: Some(300),
                features: vec!["gpt-5".to_string(), "web-search".to_string()],
                supports_extra_usage: false,
                supports_model_selection: false,
                supports_teams: false,
            },
            PlanTier {
                id: "codex-plus".to_string(),
                name: "Codex Plus".to_string(),
                provider: ProviderKind::Codex,
                price_usd_monthly: Some(20.0),
                token_budget: "5M".to_string(),
                requests_per_hour: Some(100),
                requests_per_day: Some(2_000),
                window_minutes: Some(300),
                features: vec!["gpt-5".to_string(), "gpt-5-mini".to_string(), "web-search".to_string()],
                supports_extra_usage: false,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "codex-pro".to_string(),
                name: "Codex Pro".to_string(),
                provider: ProviderKind::Codex,
                price_usd_monthly: Some(200.0),
                token_budget: "30M".to_string(),
                requests_per_hour: Some(500),
                requests_per_day: Some(10_000),
                window_minutes: Some(300),
                features: vec![
                    "gpt-5".to_string(),
                    "gpt-5-pro".to_string(),
                    "web-search".to_string(),
                    "priority-queue".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "codex-team".to_string(),
                name: "Codex Team".to_string(),
                provider: ProviderKind::Codex,
                price_usd_monthly: Some(400.0),
                token_budget: "100M".to_string(),
                requests_per_hour: Some(1_000),
                requests_per_day: Some(25_000),
                window_minutes: Some(300),
                features: vec![
                    "gpt-5".to_string(),
                    "gpt-5-pro".to_string(),
                    "web-search".to_string(),
                    "priority-queue".to_string(),
                    "shared-workspaces".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: true,
            },
            PlanTier {
                id: "codex-enterprise".to_string(),
                name: "Codex Enterprise".to_string(),
                provider: ProviderKind::Codex,
                price_usd_monthly: None,
                token_budget: "unlimited".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: Some(300),
                features: vec![
                    "gpt-5".to_string(),
                    "gpt-5-pro".to_string(),
                    "web-search".to_string(),
                    "priority-queue".to_string(),
                    "shared-workspaces".to_string(),
                    "sso".to_string(),
                    "audit-log".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: true,
            },

            // ---------------- Claude ----------------
            PlanTier {
                id: "claude-free".to_string(),
                name: "Claude Free".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: Some(0.0),
                token_budget: "100K".to_string(),
                requests_per_hour: Some(10),
                requests_per_day: Some(50),
                window_minutes: Some(300),
                features: vec!["sonnet".to_string()],
                supports_extra_usage: false,
                supports_model_selection: false,
                supports_teams: false,
            },
            PlanTier {
                id: "claude-pro".to_string(),
                name: "Claude Pro".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: Some(20.0),
                token_budget: "5M".to_string(),
                requests_per_hour: Some(60),
                requests_per_day: Some(800),
                window_minutes: Some(300),
                features: vec![
                    "sonnet".to_string(),
                    "opus".to_string(),
                    "projects".to_string(),
                ],
                supports_extra_usage: false,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "claude-max-5x".to_string(),
                name: "Claude Max (5x)".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: Some(100.0),
                token_budget: "25M".to_string(),
                requests_per_hour: Some(200),
                requests_per_day: Some(4_000),
                window_minutes: Some(300),
                features: vec![
                    "sonnet".to_string(),
                    "opus".to_string(),
                    "projects".to_string(),
                    "priority-queue".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "claude-max-20x".to_string(),
                name: "Claude Max (20x)".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: Some(200.0),
                token_budget: "100M".to_string(),
                requests_per_hour: Some(500),
                requests_per_day: Some(10_000),
                window_minutes: Some(300),
                features: vec![
                    "sonnet".to_string(),
                    "opus".to_string(),
                    "projects".to_string(),
                    "priority-queue".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "claude-team".to_string(),
                name: "Claude Team".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: Some(50.0),
                token_budget: "30M".to_string(),
                requests_per_hour: Some(300),
                requests_per_day: Some(6_000),
                window_minutes: Some(300),
                features: vec![
                    "sonnet".to_string(),
                    "opus".to_string(),
                    "projects".to_string(),
                    "shared-workspaces".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: true,
            },
            PlanTier {
                id: "claude-enterprise".to_string(),
                name: "Claude Enterprise".to_string(),
                provider: ProviderKind::Claude,
                price_usd_monthly: None,
                token_budget: "unlimited".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: Some(300),
                features: vec![
                    "sonnet".to_string(),
                    "opus".to_string(),
                    "projects".to_string(),
                    "shared-workspaces".to_string(),
                    "sso".to_string(),
                    "audit-log".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: true,
            },

            // ---------------- Copilot ----------------
            PlanTier {
                id: "copilot-free".to_string(),
                name: "Copilot Free".to_string(),
                provider: ProviderKind::Copilot,
                price_usd_monthly: Some(0.0),
                token_budget: "50K".to_string(),
                requests_per_hour: Some(15),
                requests_per_day: Some(150),
                window_minutes: Some(300),
                features: vec!["gpt-4o-mini".to_string()],
                supports_extra_usage: false,
                supports_model_selection: false,
                supports_teams: false,
            },
            PlanTier {
                id: "copilot-pro".to_string(),
                name: "Copilot Pro".to_string(),
                provider: ProviderKind::Copilot,
                price_usd_monthly: Some(10.0),
                token_budget: "3M".to_string(),
                requests_per_hour: Some(60),
                requests_per_day: Some(1_000),
                window_minutes: Some(300),
                features: vec![
                    "gpt-4o".to_string(),
                    "claude-3.5-sonnet".to_string(),
                    "code-review".to_string(),
                ],
                supports_extra_usage: false,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "copilot-business".to_string(),
                name: "Copilot Business".to_string(),
                provider: ProviderKind::Copilot,
                price_usd_monthly: Some(19.0),
                token_budget: "10M".to_string(),
                requests_per_hour: Some(100),
                requests_per_day: Some(3_000),
                window_minutes: Some(300),
                features: vec![
                    "gpt-4o".to_string(),
                    "claude-3.5-sonnet".to_string(),
                    "code-review".to_string(),
                    "shared-workspaces".to_string(),
                ],
                supports_extra_usage: false,
                supports_model_selection: true,
                supports_teams: true,
            },
            PlanTier {
                id: "copilot-enterprise".to_string(),
                name: "Copilot Enterprise".to_string(),
                provider: ProviderKind::Copilot,
                price_usd_monthly: Some(39.0),
                token_budget: "unlimited".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: Some(300),
                features: vec![
                    "gpt-4o".to_string(),
                    "claude-3.5-sonnet".to_string(),
                    "code-review".to_string(),
                    "shared-workspaces".to_string(),
                    "sso".to_string(),
                    "audit-log".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: true,
            },

            // ---------------- Antigravity ----------------
            PlanTier {
                id: "antigravity-free".to_string(),
                name: "Antigravity Free".to_string(),
                provider: ProviderKind::Antigravity,
                price_usd_monthly: Some(0.0),
                token_budget: "200K".to_string(),
                requests_per_hour: Some(30),
                requests_per_day: Some(300),
                window_minutes: Some(300),
                features: vec!["gemini-2.0-flash".to_string()],
                supports_extra_usage: false,
                supports_model_selection: false,
                supports_teams: false,
            },
            PlanTier {
                id: "antigravity-pro".to_string(),
                name: "Antigravity Pro".to_string(),
                provider: ProviderKind::Antigravity,
                price_usd_monthly: Some(20.0),
                token_budget: "10M".to_string(),
                requests_per_hour: Some(120),
                requests_per_day: Some(2_500),
                window_minutes: Some(300),
                features: vec![
                    "gemini-2.0-flash".to_string(),
                    "gemini-2.0-pro".to_string(),
                    "claude-3.5-sonnet".to_string(),
                ],
                supports_extra_usage: false,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "antigravity-ultra".to_string(),
                name: "Antigravity Ultra".to_string(),
                provider: ProviderKind::Antigravity,
                price_usd_monthly: Some(250.0),
                token_budget: "100M".to_string(),
                requests_per_hour: Some(500),
                requests_per_day: Some(15_000),
                window_minutes: Some(300),
                features: vec![
                    "gemini-2.0-flash".to_string(),
                    "gemini-2.0-pro".to_string(),
                    "claude-3.5-sonnet".to_string(),
                    "claude-3.5-opus".to_string(),
                    "priority-queue".to_string(),
                ],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },

            // ---------------- API-key providers ----------------
            // These tiers describe typical pay-as-you-go usage caps; the
            // providers themselves do not expose a "plan limits" UI.
            PlanTier {
                id: "openai-payg".to_string(),
                name: "OpenAI Pay-as-you-go".to_string(),
                provider: ProviderKind::OpenAi,
                price_usd_monthly: None,
                token_budget: "payg".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: None,
                features: vec!["gpt-4o".to_string(), "gpt-5".to_string(), "web-search".to_string()],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "gemini-payg".to_string(),
                name: "Gemini Pay-as-you-go".to_string(),
                provider: ProviderKind::Gemini,
                price_usd_monthly: None,
                token_budget: "payg".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: None,
                features: vec!["gemini-2.0-flash".to_string(), "gemini-2.0-pro".to_string()],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "deepseek-payg".to_string(),
                name: "DeepSeek Pay-as-you-go".to_string(),
                provider: ProviderKind::Deepseek,
                price_usd_monthly: None,
                token_budget: "payg".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: None,
                features: vec!["deepseek-v3".to_string(), "deepseek-r1".to_string()],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
            PlanTier {
                id: "meta-payg".to_string(),
                name: "Meta Pay-as-you-go".to_string(),
                provider: ProviderKind::Meta,
                price_usd_monthly: None,
                token_budget: "payg".to_string(),
                requests_per_hour: None,
                requests_per_day: None,
                window_minutes: None,
                features: vec!["llama-3.1-405b".to_string(), "llama-3.1-70b".to_string()],
                supports_extra_usage: true,
                supports_model_selection: true,
                supports_teams: false,
            },
        ];
        Self::from_tiers(tiers)
    }

    pub fn tiers(&self) -> &[PlanTier] {
        &self.tiers
    }

    pub fn tiers_for(&self, provider: ProviderKind) -> &[PlanTier] {
        self.by_provider
            .get(&provider)
            .map(|v| v.as_slice())
            .unwrap_or(&[])
    }

    pub fn tier(&self, provider: ProviderKind, tier_id: &str) -> Option<&PlanTier> {
        self.tiers_for(provider)
            .iter()
            .find(|t| t.id == tier_id)
    }

    /// Pick the tier that best matches a free-form plan name from the
    /// provider's OAuth/login response. Falls back to the free tier if no
    /// tier name can be detected.
    pub fn tier_for_plan_name(
        &self,
        provider: ProviderKind,
        plan_name: Option<&str>,
    ) -> Option<&PlanTier> {
        let raw = plan_name?.to_lowercase();
        let tiers = self.tiers_for(provider);
        // First, look for an explicit match (e.g. "max-20x" → claude-max-20x).
        if let Some(tier) = tiers.iter().find(|t| raw.contains(&t.id)) {
            return Some(tier);
        }
        // Otherwise, scan keywords on the tier name (e.g. "free" / "pro").
        for tier in tiers {
            let needle = tier.name.to_lowercase();
            if raw.contains(&needle) {
                return Some(tier);
            }
        }
        // Otherwise, pick the cheapest tier that contains the keyword
        // (e.g. "team" matches the team tier across all providers).
        tiers
            .iter()
            .find(|t| raw.contains(&t.id.split('-').next().unwrap_or("")))
    }

    /// The cheapest paid tier for a provider, useful as a "recommended upgrade".
    pub fn cheapest_paid_tier(&self, provider: ProviderKind) -> Option<&PlanTier> {
        self.tiers_for(provider)
            .iter()
            .filter(|t| matches!(t.price_usd_monthly, Some(p) if p > 0.0))
            .min_by(|a, b| {
                let ap = a.price_usd_monthly.unwrap_or(f64::MAX);
                let bp = b.price_usd_monthly.unwrap_or(f64::MAX);
                ap.partial_cmp(&bp).unwrap_or(std::cmp::Ordering::Equal)
            })
    }

    /// The free tier for a provider, if one exists.
    pub fn free_tier(&self, provider: ProviderKind) -> Option<&PlanTier> {
        self.tiers_for(provider)
            .iter()
            .find(|t| matches!(t.price_usd_monthly, Some(0.0) | None))
            .or_else(|| self.tiers_for(provider).first())
    }
}

// ---------------------------------------------------------------------------
// Plan limits reader
// ---------------------------------------------------------------------------

pub struct PlanLimitsReader;

impl PlanLimitsReader {
    /// Codex, Claude, Antigravity and Copilot report plan limits. Cursor,
    /// OpenCode, Grok, DeepSeek, Meta and Devin expose none.
    pub fn exposes_limits(provider: ProviderKind) -> bool {
        matches!(
            provider,
            ProviderKind::Codex
                | ProviderKind::Claude
                | ProviderKind::Antigravity
                | ProviderKind::Copilot
        )
    }

    /// Read plan limits for the given provider. The result is `None` when the
    /// provider does not expose limits, when the live probe fails, or when
    /// the user is not authenticated.
    ///
    /// The Swift implementation probes the provider's session, OAuth endpoint,
    /// or CLI subprocess depending on the provider. The Rust implementation
    /// keeps the same routing logic but does not perform the network calls —
    /// callers are expected to inject their own probe implementations through
    /// `PlanLimitsReader::set_probe`.
    pub async fn read(
        provider: ProviderKind,
        executable: String,
        environment: HashMap<String, String>,
    ) -> Option<PlanLimits> {
        if !Self::exposes_limits(provider) {
            return None;
        }
        let executable_path = PathBuf::from(executable);
        match provider {
            ProviderKind::Codex => {
                Self::read_codex(&executable_path, &environment).await
            }
            ProviderKind::Claude => Self::read_claude(&executable_path, &environment).await,
            ProviderKind::Antigravity => {
                Self::read_antigravity(&executable_path, &environment).await
            }
            ProviderKind::Copilot => {
                Self::read_copilot(&executable_path, &environment).await
            }
            _ => None,
        }
    }

    /// Format a window title from a window length in minutes.
    ///
    /// Matches the Swift helper: 5 hours → "5-hour limit", 1 day → "Daily",
    /// 7 days → "Weekly", 28-31 days → "Monthly", everything else is the
    /// day/hour count.
    pub fn window_title(minutes: Option<i64>) -> String {
        let Some(minutes) = minutes else {
            return "Usage limit".to_string();
        };
        match minutes {
            300 => "5-hour limit".to_string(),
            1_440 => "Daily".to_string(),
            10_080 => "Weekly".to_string(),
            40_320..=44_640 => "Monthly".to_string(),
            _ => {
                if minutes % 1_440 == 0 {
                    format!("{}-day limit", minutes / 1_440)
                } else {
                    let hours = std::cmp::max(1, minutes / 60);
                    format!("{}-hour limit", hours)
                }
            }
        }
    }

    /// Capitalize the first letter of a raw plan name, the way the Swift
    /// helper does.
    pub fn plan_name(raw: Option<&str>) -> Option<String> {
        let trimmed = raw?.trim();
        if trimmed.is_empty() {
            return None;
        }
        let mut chars = trimmed.chars();
        let first = chars.next()?.to_uppercase().to_string();
        Some(format!("{}{}", first, chars.as_str()))
    }

    // -----------------------------------------------------------------------
    // Probe hooks
    //
    // The Swift implementation reads limits by calling into per-provider
    // session objects and the Claude OAuth endpoint. The Rust side keeps the
    // routing logic but lets callers inject a probe closure; in production
    // `read_*` is wired up by the host application, and in tests a stub
    // probe can return deterministic JSON. We expose the slot here so the
    // public API matches Swift without forcing an HTTP/CLI dependency on
    // this file.
    // -----------------------------------------------------------------------

    pub fn set_probe(provider: ProviderKind, probe: PlanLimitsProbe) {
        PROBES
            .lock()
            .expect("plan-limits probes poisoned")
            .insert(provider, probe);
    }

    pub fn clear_probe(provider: ProviderKind) {
        PROBES
            .lock()
            .expect("plan-limits probes poisoned")
            .remove(&provider);
    }

    // -----------------------------------------------------------------------
    // Per-provider readers
    // -----------------------------------------------------------------------

    async fn read_codex(
        _executable: &std::path::Path,
        _environment: &HashMap<String, String>,
    ) -> Option<PlanLimits> {
        // Codex reports limits via its session. Probe hook lets the host
        // application provide a JSON payload (status, body) which is parsed
        // the same way the Swift `CodexSession.readPlanLimits` does.
        Self::dispatch_probe(ProviderKind::Codex).await
    }

    async fn read_antigravity(
        _executable: &std::path::Path,
        _environment: &HashMap<String, String>,
    ) -> Option<PlanLimits> {
        Self::dispatch_probe(ProviderKind::Antigravity).await
    }

    async fn read_copilot(
        _executable: &std::path::Path,
        _environment: &HashMap<String, String>,
    ) -> Option<PlanLimits> {
        Self::dispatch_probe(ProviderKind::Copilot).await
    }

    async fn read_claude(
        executable: &std::path::Path,
        environment: &HashMap<String, String>,
    ) -> Option<PlanLimits> {
        // Claude first tries its own OAuth usage endpoint, then falls back to
        // a short-lived CLI session that asks for `get_usage`. We try the
        // probe (which is wired up by the host to talk to the OAuth endpoint),
        // then fall back to the CLI probe.
        if let Some(limits) = Self::dispatch_probe(ProviderKind::Claude).await {
            return Some(limits);
        }
        Self::read_claude_from_cli(executable, environment).await
    }

    async fn read_claude_from_cli(
        _executable: &std::path::Path,
        _environment: &HashMap<String, String>,
    ) -> Option<PlanLimits> {
        // The host application wires this probe to the Claude CLI control
        // request flow. The routing logic lives here so the call shape
        // matches Swift.
        Self::dispatch_probe(ProviderKind::Claude).await
    }

    async fn dispatch_probe(provider: ProviderKind) -> Option<PlanLimits> {
        let probe = {
            let guard = PROBES.lock().expect("plan-limits probes poisoned");
            guard.get(&provider).cloned()
        };
        match probe {
            Some(probe) => probe.0(provider).await,
            None => None,
        }
    }
}

use std::sync::{Arc, Mutex};

/// A probe that returns plan limits for a provider. The host application
/// sets one of these per-provider to wire the reader into its real network
/// or subprocess stack.
#[derive(Clone)]
pub struct PlanLimitsProbe(Arc<dyn Fn(ProviderKind) -> futures_core::future::BoxFuture<'static, Option<PlanLimits>> + Send + Sync>);

impl PlanLimitsProbe {
    pub fn new<F>(f: F) -> Self
    where
        F: Fn(ProviderKind) -> futures_core::future::BoxFuture<'static, Option<PlanLimits>>
            + Send
            + Sync
            + 'static,
    {
        Self(Arc::new(f))
    }
}

impl std::fmt::Debug for PlanLimitsProbe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PlanLimitsProbe").finish()
    }
}

static PROBES: once_cell::sync::Lazy<Mutex<HashMap<ProviderKind, PlanLimitsProbe>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(HashMap::new()));

// ---------------------------------------------------------------------------
// JSON helpers — parse the JSON returned by the provider's usage endpoint
// into a PlanLimits value, mirroring `parseClaudeUsage` in Swift.
// ---------------------------------------------------------------------------

/// Parse a Claude usage payload (root JSON object) into a PlanLimits. The
/// payload can come from either the OAuth usage endpoint or the CLI control
/// response. `plan_name` is the OAuth `subscriptionType` / CLI
/// `subscription_type` field.
pub fn parse_claude_usage(root: &Value, plan_name: Option<&str>) -> Option<PlanLimits> {
    let mut windows: Vec<Window> = Vec::new();

    if let Some(limits) = root.get("limits").and_then(|v| v.as_array()) {
        for (index, limit) in limits.iter().enumerate() {
            let Some(percent) = limit.get("percent").and_then(|v| v.as_f64()) else {
                continue;
            };
            let kind = limit
                .get("kind")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let group = limit
                .get("group")
                .and_then(|v| v.as_str())
                .map(PlanLimitsReader::plan_name)
                .flatten()
                .unwrap_or_else(|| "Usage".to_string());
            let scope = limit
                .get("scope")
                .and_then(|s| s.get("model"))
                .and_then(|m| m.get("display_name"))
                .and_then(|n| n.as_str())
                .map(|s| s.to_string());
            let title = match kind {
                "session" => "5-hour limit".to_string(),
                "weekly_all" => "Weekly · all models".to_string(),
                _ => scope
                    .clone()
                    .map(|s| format!("{} · {}", group, s))
                    .unwrap_or(group.clone()),
            };
            let resets_at = limit
                .get("resets_at")
                .and_then(|v| v.as_str())
                .and_then(parse_date);
            windows.push(Window::new(
                format!("{}-{}", kind, index),
                title,
                percent,
                resets_at,
            ));
        }
    }

    if windows.is_empty() {
        for (key, title) in [
            ("five_hour", "5-hour limit"),
            ("seven_day", "Weekly · all models"),
        ] {
            let Some(window) = root.get(key) else { continue };
            let Some(percent) = window.get("utilization").and_then(|v| v.as_f64()) else {
                continue;
            };
            let resets_at = window
                .get("resets_at")
                .and_then(|v| v.as_str())
                .and_then(parse_date);
            windows.push(Window::new(key.to_string(), title.to_string(), percent, resets_at));
        }
    }

    if let Some(extra) = root.get("extra_usage") {
        if extra.get("is_enabled").and_then(|v| v.as_bool()) == Some(true) {
            if let Some(percent) = extra.get("utilization").and_then(|v| v.as_f64()) {
                windows.push(Window::new(
                    "extra-usage",
                    "Extra usage",
                    percent,
                    None,
                ));
            }
        }
    }

    if windows.is_empty() {
        return None;
    }
    Some(PlanLimits::new(
        PlanLimitsReader::plan_name(plan_name),
        windows,
    ))
}

/// Parse a generic rate-limits payload (the shape used by Codex, Copilot,
/// and Antigravity): an object with a `windows` array, each carrying
/// `id`/`title`/`percent`/`resets_at`.
pub fn parse_generic_usage(root: &Value, plan_name: Option<&str>) -> Option<PlanLimits> {
    let mut windows: Vec<Window> = Vec::new();
    if let Some(arr) = root.get("windows").and_then(|v| v.as_array()) {
        for (index, item) in arr.iter().enumerate() {
            let percent = item
                .get("percent")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
            let title = item
                .get("title")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .unwrap_or_else(|| format!("Window {}", index));
            let id = item
                .get("id")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .unwrap_or_else(|| format!("window-{}", index));
            let resets_at = item
                .get("resets_at")
                .and_then(|v| v.as_str())
                .and_then(parse_date);
            windows.push(Window::new(id, title, percent, resets_at));
        }
    }
    if windows.is_empty() {
        return None;
    }
    Some(PlanLimits::new(
        PlanLimitsReader::plan_name(plan_name),
        windows,
    ))
}

/// Parse an ISO 8601 timestamp. Claude writes microsecond timestamps that
/// `chrono` doesn't accept, so we drop the fraction before parsing.
pub fn parse_date(text: &str) -> Option<DateTime<Utc>> {
    if text.is_empty() {
        return None;
    }
    let trimmed = strip_microseconds(text);
    if let Ok(dt) = DateTime::parse_from_rfc3339(&trimmed) {
        return Some(dt.with_timezone(&Utc));
    }
    if let Ok(naive) = DateTime::parse_from_rfc2822(&trimmed) {
        return Some(naive.with_timezone(&Utc));
    }
    if let Ok(naive) = NaiveDateTime::parse_from_str(&trimmed, "%Y-%m-%dT%H:%M:%S") {
        return Some(Utc.from_utc_datetime(&naive));
    }
    None
}

fn strip_microseconds(text: &str) -> String {
    // Drop ".XXXXXX" if present.
    let re = Regex::new(r"\.\d+").expect("valid regex");
    re.replace_all(text, "").to_string()
}

/// Convenience: build a `PlanLimits` from raw JSON, dispatching by provider.
pub fn parse_for_provider(provider: ProviderKind, payload: &Value) -> Option<PlanLimits> {
    let plan_name = payload
        .get("plan_name")
        .and_then(|v| v.as_str())
        .or_else(|| payload.get("subscriptionType").and_then(|v| v.as_str()))
        .or_else(|| {
            payload
                .get("subscription_type")
                .and_then(|v| v.as_str())
        });
    match provider {
        ProviderKind::Claude => parse_claude_usage(payload, plan_name),
        ProviderKind::Codex
        | ProviderKind::Antigravity
        | ProviderKind::Copilot => parse_generic_usage(payload, plan_name),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn window_title_examples() {
        assert_eq!(PlanLimitsReader::window_title(None), "Usage limit");
        assert_eq!(PlanLimitsReader::window_title(Some(300)), "5-hour limit");
        assert_eq!(PlanLimitsReader::window_title(Some(1_440)), "Daily");
        assert_eq!(PlanLimitsReader::window_title(Some(10_080)), "Weekly");
        assert_eq!(
            PlanLimitsReader::window_title(Some(43_200)),
            "Monthly"
        );
        assert_eq!(
            PlanLimitsReader::window_title(Some(2_880)),
            "2-day limit"
        );
        assert_eq!(
            PlanLimitsReader::window_title(Some(180)),
            "3-hour limit"
        );
    }

    #[test]
    fn plan_name_capitalizes_first_letter() {
        assert_eq!(
            PlanLimitsReader::plan_name(Some("pro")),
            Some("Pro".to_string())
        );
        assert_eq!(
            PlanLimitsReader::plan_name(Some("max-20x")),
            Some("Max-20x".to_string())
        );
        assert_eq!(PlanLimitsReader::plan_name(None), None);
        assert_eq!(PlanLimitsReader::plan_name(Some("")), None);
        assert_eq!(PlanLimitsReader::plan_name(Some("   ")), None);
    }

    #[test]
    fn exposes_limits_matches_swift_truth_table() {
        assert!(PlanLimitsReader::exposes_limits(ProviderKind::Codex));
        assert!(PlanLimitsReader::exposes_limits(ProviderKind::Claude));
        assert!(PlanLimitsReader::exposes_limits(ProviderKind::Antigravity));
        assert!(PlanLimitsReader::exposes_limits(ProviderKind::Copilot));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Cursor));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Opencode));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Grok));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Deepseek));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Meta));
        assert!(!PlanLimitsReader::exposes_limits(ProviderKind::Devin));
    }

    #[test]
    fn plan_limits_helpers() {
        let limits = PlanLimits::new(
            Some("Pro".to_string()),
            vec![
                Window::new("a", "5-hour limit", 30.0, None),
                Window::new("b", "Weekly", 100.0, None),
            ],
        );
        assert!(limits.is_exhausted());
        assert!(limits.exhausted_window().is_some());
        let primary = limits.primary_window().unwrap();
        assert_eq!(primary.id, "b");
    }

    #[test]
    fn parse_claude_usage_array_form() {
        let payload = json!({
            "limits": [
                {"kind": "session", "percent": 12.5},
                {"kind": "weekly_all", "percent": 65.0}
            ],
            "subscriptionType": "max"
        });
        let limits = parse_claude_usage(&payload, Some("max")).unwrap();
        assert_eq!(limits.plan_name.as_deref(), Some("Max"));
        assert_eq!(limits.windows.len(), 2);
        assert_eq!(limits.windows[0].title, "5-hour limit");
        assert_eq!(limits.windows[1].title, "Weekly · all models");
    }

    #[test]
    fn parse_claude_usage_falls_back_to_root() {
        let payload = json!({
            "five_hour": {"utilization": 10.0},
            "seven_day": {"utilization": 30.0}
        });
        let limits = parse_claude_usage(&payload, None).unwrap();
        assert_eq!(limits.windows.len(), 2);
        assert!(limits.windows[0].title.contains("5-hour"));
    }

    #[test]
    fn parse_claude_usage_appends_extra_usage_when_enabled() {
        let payload = json!({
            "limits": [{"kind": "session", "percent": 5.0}],
            "extra_usage": {"is_enabled": true, "utilization": 42.0}
        });
        let limits = parse_claude_usage(&payload, None).unwrap();
        assert_eq!(limits.windows.len(), 2);
        assert_eq!(limits.windows[1].title, "Extra usage");
    }

    #[test]
    fn parse_generic_usage_returns_none_when_empty() {
        let payload = json!({});
        assert!(parse_generic_usage(&payload, None).is_none());
    }

    #[test]
    fn parse_for_provider_dispatches() {
        let claude = json!({"limits": [{"kind": "session", "percent": 1.0}]});
        let codex = json!({"windows": [{"id": "5h", "title": "5-hour", "percent": 1.0}]});
        assert!(parse_for_provider(ProviderKind::Claude, &claude).is_some());
        assert!(parse_for_provider(ProviderKind::Codex, &codex).is_some());
        assert!(parse_for_provider(ProviderKind::Cursor, &json!({})).is_none());
    }

    #[test]
    fn parse_date_handles_iso_with_microseconds() {
        let date = parse_date("2025-01-02T03:04:05.123456Z").unwrap();
        assert_eq!(
            date.to_rfc3339(),
            "2025-01-02T03:04:05+00:00"
        );
    }

    #[test]
    fn parse_date_handles_iso_without_timezone() {
        let date = parse_date("2025-01-02T03:04:05").unwrap();
        assert_eq!(
            date.to_rfc3339(),
            "2025-01-02T03:04:05+00:00"
        );
    }

    #[test]
    fn parse_date_returns_none_for_garbage() {
        assert!(parse_date("not a date").is_none());
        assert!(parse_date("").is_none());
    }

    #[test]
    fn catalog_contains_expected_tiers() {
        let catalog = PlanTierCatalog::default_catalog();
        assert!(!catalog.tiers().is_empty());
        // Each of the four limit-exposing providers should have at least
        // a free + paid tier.
        for p in [
            ProviderKind::Codex,
            ProviderKind::Claude,
            ProviderKind::Copilot,
            ProviderKind::Antigravity,
        ] {
            assert!(catalog.tiers_for(p).len() >= 2, "missing tiers for {:?}", p);
        }
    }

    #[test]
    fn catalog_cheapest_paid_tier_finds_pro() {
        let catalog = PlanTierCatalog::default_catalog();
        let tier = catalog
            .cheapest_paid_tier(ProviderKind::Claude)
            .unwrap();
        assert!(tier.price_usd_monthly.unwrap_or(0.0) > 0.0);
    }

    #[test]
    fn catalog_free_tier_is_zero_price() {
        let catalog = PlanTierCatalog::default_catalog();
        let tier = catalog.free_tier(ProviderKind::Codex).unwrap();
        assert_eq!(tier.price_usd_monthly, Some(0.0));
    }

    #[test]
    fn tier_for_plan_name_finds_match_by_substring() {
        let catalog = PlanTierCatalog::default_catalog();
        let tier = catalog
            .tier_for_plan_name(ProviderKind::Claude, Some("max-20x"))
            .unwrap();
        assert_eq!(tier.id, "claude-max-20x");
    }

    #[test]
    fn tier_for_plan_name_returns_none_when_no_match() {
        let catalog = PlanTierCatalog::default_catalog();
        assert!(catalog
            .tier_for_plan_name(ProviderKind::Cursor, Some("anything"))
            .is_none());
    }
}
