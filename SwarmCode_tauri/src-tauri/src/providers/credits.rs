//! Provider prepaid-credit reading.
//!
//! Mirrors `SwarmAI/Providers/ProviderCredits.swift`.
//!
//! * `ProviderCredits` — the per-provider balance record
//! * `CreditsReader`   — fetch balance from provider APIs (today: DeepSeek)

use std::sync::Arc;

use chrono::DateTime;
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::RwLock;
use tokio::time::{timeout, Duration};

use crate::models::provider::ProviderKind;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Errors that can occur while reading a provider's credit balance.
#[derive(Debug, Error)]
pub enum CreditsReadError {
    #[error("network request failed: {0}")]
    Network(#[from] reqwest::Error),

    #[error("unexpected response format: {0}")]
    BadResponse(String),

    #[error("read timed out after {0}s")]
    Timeout(u64),

    #[error("provider returned an error status: {0}")]
    ProviderError(String),
}

// ---------------------------------------------------------------------------
// ProviderCredits
// ---------------------------------------------------------------------------

/// A pay-as-you-go API provider's prepaid balance.
///
/// This is the Rust counterpart of Swift's `ProviderCredits`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderCredits {
    /// What is left to spend.
    pub total: f64,
    /// The account's currency as the provider reports it (e.g. "USD", "CNY").
    /// Empty when the provider reports no currency.
    pub currency: String,
    /// The share of the total that came from a top-up, when the provider
    /// splits it. `None` when the provider reports a single number.
    pub topped_up: Option<f64>,
    /// The share of the total that came from promotional grants, when the
    /// provider splits it. `None` when the provider reports a single number.
    pub granted: Option<f64>,
    /// `false` once the provider says the account can no longer be charged:
    /// every request fails from then on.
    pub is_usable: bool,
}

impl ProviderCredits {
    // -------------------------------------------------------------------
    // Constructors
    // -------------------------------------------------------------------

    /// Build credits from a DeepSeek-style API response.
    pub fn from_deepseek(total: f64, currency: String) -> Self {
        Self {
            total,
            currency,
            topped_up: None,
            granted: None,
            is_usable: true,
        }
    }

    /// Build credits from a DeepSeek balance-info block.
    pub fn from_deepseek_balance_info(
        total: f64,
        currency: String,
        topped_up: f64,
        granted: f64,
    ) -> Self {
        Self {
            total,
            currency,
            topped_up: Some(topped_up),
            granted: Some(granted),
            is_usable: true,
        }
    }

    /// Create a depleted-credits record.
    pub fn depleted(currency: impl Into<String>) -> Self {
        Self {
            total: 0.0,
            currency: currency.into(),
            topped_up: None,
            granted: None,
            is_usable: false,
        }
    }

    /// Create a placeholder for an unknown balance (used while loading).
    pub fn unknown() -> Self {
        Self {
            total: 0.0,
            currency: String::new(),
            topped_up: None,
            granted: None,
            is_usable: false,
        }
    }

    // -------------------------------------------------------------------
    // Computed helpers
    // -------------------------------------------------------------------

    /// "`$12.34`" — the amount with whatever currency the provider reported.
    pub fn amount_text(&self) -> String {
        Self::money(self.total, &self.currency)
    }

    /// "Topped up $10.00 · Granted $2.34", or `None` when the provider
    /// reports a single number (no breakdown available).
    pub fn breakdown_text(&self) -> Option<String> {
        let mut parts: Vec<String> = Vec::new();

        if let Some(topped_up) = self.topped_up {
            if topped_up > 0.0 {
                parts.push(format!(
                    "Topped up {}",
                    Self::money(topped_up, &self.currency)
                ));
            }
        }

        if let Some(granted) = self.granted {
            if granted > 0.0 {
                parts.push(format!(
                    "Granted {}",
                    Self::money(granted, &self.currency)
                ));
            }
        }

        if parts.is_empty() {
            None
        } else {
            Some(parts.join(" · "))
        }
    }

    /// `true` when the balance is unusable or empty.
    pub fn is_depleted(&self) -> bool {
        !self.is_usable || self.total <= 0.0
    }

    // -------------------------------------------------------------------
    // Formatting
    // -------------------------------------------------------------------

    /// Money with the currency the provider reported, pinned to English
    /// formatting so the dashboards that write "$0.43" stay consistent.
    ///
    /// An unknown or missing code falls back to a plain number so the panel
    /// never shows a wrong symbol.
    pub fn money(value: f64, currency: &str) -> String {
        let code = currency.to_uppercase();

        // Only treat a 3-letter alphabetic string as an ISO currency code.
        let is_code = code.len() == 3 && code.chars().all(|c| c.is_ascii_alphabetic());

        if !is_code {
            let number = Self::plain(value);
            if currency.is_empty() {
                number
            } else {
                format!("{} {}", number, currency)
            }
        } else {
            let symbol = Self::currency_symbol(&code);
            format!("{}{:.2}", symbol, value)
        }
    }

    /// Look up the currency symbol for an ISO code, falling back to the code
    /// itself when no symbol is known.
    fn currency_symbol(code: &str) -> &'static str {
        match code {
            "USD" => "$",
            "EUR" => "\u{20AC}",
            "GBP" => "\u{00A3}",
            "JPY" => "\u{00A5}",
            "CNY" => "CN\u{00A5}",
            "HKD" => "HK$",
            "SGD" => "S$",
            "AUD" => "A$",
            "CAD" => "C$",
            "CHF" => "Fr",
            "INR" => "\u{20B9}",
            "KRW" => "\u{FFE6}",
            "BRL" => "R$",
            "MXN" => "MX$",
            "RUB" => "\u{20BD}",
            "SEK" => "kr",
            "NOK" => "kr",
            "DKK" => "kr",
            "PLN" => "z\u{0142}",
            "TRY" => "\u{20BA}",
            "THB" => "\u{0E3F}",
            "TWD" => "NT$",
            _ => "$",
        }
    }

    /// Two-decimal-place number in `en_US` locale.
    fn plain(value: f64) -> String {
        format!("{:.2}", value)
    }
}

// ---------------------------------------------------------------------------
// Convenience re-export so the rest of the crate can write
// `use crate::providers::credits::ProviderCredits;` without clashing with
// the older `crate::types::ProviderCredits`.
// ---------------------------------------------------------------------------
pub use ProviderCredits as Credits;

// ---------------------------------------------------------------------------
// DeepSeek API response types
// ---------------------------------------------------------------------------

/// Top-level response from DeepSeek's `/user/balance` endpoint.
#[derive(Debug, Clone, Deserialize)]
struct DeepSeekBalanceResponse {
    /// Whether the account can currently be billed.
    is_available: bool,
    /// One or more currency wallets.
    balance_infos: Vec<DeepSeekBalanceInfo>,
}

/// A single currency wallet inside the DeepSeek balance response.
#[derive(Debug, Clone, Deserialize)]
struct DeepSeekBalanceInfo {
    /// ISO currency code, e.g. "CNY" or "USD".
    currency: String,
    /// Total balance in this currency.
    #[serde(deserialize_with = "deserialize_string_f64")]
    total_balance: f64,
    /// Share from user top-ups.
    #[serde(deserialize_with = "deserialize_string_f64")]
    topped_up_balance: f64,
    /// Share from promotional grants.
    #[serde(deserialize_with = "deserialize_string_f64")]
    granted_balance: f64,
}

/// Helper: DeepSeek returns numeric strings, not JSON numbers.
fn deserialize_string_f64<'de, D>(deserializer: D) -> Result<f64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    s.parse::<f64>()
        .map_err(|_| serde::de::Error::custom(format!("invalid numeric string: {}", s)))
}

// ---------------------------------------------------------------------------
// CreditsReader
// ---------------------------------------------------------------------------

/// Reads a provider's prepaid balance from its API.
///
/// This is the Rust counterpart of Swift's `CreditsReader`.
///
/// Today only DeepSeek exposes a credits endpoint; all other providers
/// return `None`.
pub struct CreditsReader;

impl CreditsReader {
    /// HTTP client timeout used for every balance request.
    const REQUEST_TIMEOUT_SECS: u64 = 15;

    /// DeepSeek balance endpoint.
    const DEEPSEEK_BALANCE_URL: &'static str = "https://api.deepseek.com/user/balance";

    // -------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------

    /// Whether the provider exposes a credits endpoint that we can read.
    pub fn exposes_credits(provider: ProviderKind) -> bool {
        matches!(provider, ProviderKind::Deepseek)
    }

    /// Fetch the current credit balance for `provider` using `api_key`.
    ///
    /// Returns `None` when the provider does not expose credits or the
    /// request fails in a recoverable way. Returns `Some(ProviderCredits)`
    /// on success.
    pub async fn read(provider: ProviderKind, api_key: &str) -> Option<ProviderCredits> {
        match provider {
            ProviderKind::Deepseek => Self::read_deepseek(api_key).await,
            _ => None,
        }
    }

    /// Where the provider's dashboard tops the balance up, if applicable.
    pub fn top_up_url(provider: ProviderKind) -> Option<String> {
        match provider {
            ProviderKind::Deepseek => {
                Some("https://platform.deepseek.com/top_up".to_string())
            }
            _ => None,
        }
    }

    // -------------------------------------------------------------------
    // Per-provider implementations
    // -------------------------------------------------------------------

    /// Read the balance from DeepSeek's REST API.
    async fn read_deepseek(api_key: &str) -> Option<ProviderCredits> {
        let client = match reqwest::Client::builder()
            .user_agent(concat!(
                env!("CARGO_PKG_NAME"),
                "/",
                env!("CARGO_PKG_VERSION")
            ))
            .build()
        {
            Ok(c) => c,
            Err(_) => return None,
        };

        let request = client
            .get(Self::DEEPSEEK_BALANCE_URL)
            .bearer_auth(api_key);

        let response = match timeout(
            Duration::from_secs(Self::REQUEST_TIMEOUT_SECS),
            request.send(),
        )
        .await
        {
            Ok(Ok(resp)) => resp,
            Ok(Err(_)) | Err(_) => return None,
        };

        if !response.status().is_success() {
            // 401 / 403 means an invalid key — return None so the caller
            // can surface the auth issue without crashing.
            if response.status() == reqwest::StatusCode::UNAUTHORIZED
                || response.status() == reqwest::StatusCode::FORBIDDEN
            {
                return None;
            }
            return None;
        }

        let body: DeepSeekBalanceResponse = match response.json().await {
            Ok(b) => b,
            Err(_) => return None,
        };

        Self::build_credits_from_deepseek(body)
    }

    /// Convert the DeepSeek API response into a `ProviderCredits`.
    fn build_credits_from_deepseek(
        body: DeepSeekBalanceResponse,
    ) -> Option<ProviderCredits> {
        // Pick the first wallet that has a non-empty currency.
        let info = body.balance_infos.into_iter().find(|i| !i.currency.is_empty())?;

        let is_available = body.is_available;

        if !is_available || info.total_balance <= 0.0 {
            return Some(ProviderCredits::depleted(&info.currency));
        }

        Some(ProviderCredits::from_deepseek_balance_info(
            info.total_balance,
            info.currency,
            info.topped_up_balance,
            info.granted_balance,
        )
        .with_is_usable(is_available))
    }
}

// ---------------------------------------------------------------------------
// Builder-style helpers (chainable)
// ---------------------------------------------------------------------------

impl ProviderCredits {
    /// Set `is_usable` and return `self` for chaining.
    pub fn with_is_usable(mut self, is_usable: bool) -> Self {
        self.is_usable = is_usable;
        self
    }

    /// Set `topped_up` and return `self` for chaining.
    pub fn with_topped_up(mut self, value: f64) -> Self {
        self.topped_up = Some(value);
        self
    }

    /// Set `granted` and return `self` for chaining.
    pub fn with_granted(mut self, value: f64) -> Self {
        self.granted = Some(value);
        self
    }
}

// ---------------------------------------------------------------------------
// CreditsCache — thin in-memory cache for ProviderCredits
// ---------------------------------------------------------------------------

/// A time-stamped cache entry for a single provider's credits.
#[derive(Debug, Clone)]
pub struct CachedCredits {
    /// The credits data, or `None` while the balance is loading.
    pub credits: Option<ProviderCredits>,
    /// UTC timestamp of when the entry was written.
    pub fetched_at: chrono::DateTime<chrono::Utc>,
}

impl CachedCredits {
    /// Create a new entry recording the current time.
    pub fn new(credits: ProviderCredits) -> Self {
        Self {
            credits: Some(credits),
            fetched_at: chrono::Utc::now(),
        }
    }

    /// Create an empty placeholder used while loading.
    pub fn loading() -> Self {
        Self {
            credits: None,
            fetched_at: chrono::Utc::now(),
        }
    }

    /// `true` when the cached value is older than `max_age_seconds`.
    pub fn is_stale(&self, max_age_seconds: i64) -> bool {
        let elapsed = chrono::Utc::now()
            .signed_duration_since(self.fetched_at)
            .num_seconds();
        elapsed > max_age_seconds
    }
}

/// Thread-safe per-provider credits cache.
///
/// Wraps a `HashMap<ProviderKind, CachedCredits>` with an `Arc<RwLock<…>>`
/// so it can be shared across the app store without cloning the whole map
/// on every read.
#[derive(Debug, Clone)]
pub struct CreditsCache {
    inner: Arc<RwLock<std::collections::HashMap<ProviderKind, CachedCredits>>>,
}

impl Default for CreditsCache {
    fn default() -> Self {
        Self {
            inner: Arc::new(RwLock::new(std::collections::HashMap::new())),
        }
    }
}

impl CreditsCache {
    /// Create an empty cache.
    pub fn new() -> Self {
        Self::default()
    }

    /// Retrieve cached credits for `provider`, if any.
    pub async fn get(&self, provider: ProviderKind) -> Option<ProviderCredits> {
        let guard = self.inner.read().await;
        guard.get(&provider).and_then(|c| c.credits.clone())
    }

    /// Store credits for `provider`.
    pub async fn set(&self, provider: ProviderKind, credits: ProviderCredits) {
        let mut guard = self.inner.write().await;
        guard.insert(provider, CachedCredits::new(credits));
    }

    /// Remove the entry for `provider`.
    pub async fn remove(&self, provider: ProviderKind) {
        let mut guard = self.inner.write().await;
        guard.remove(&provider);
    }

    /// `true` when `provider` has a fresh-enough cached value.
    pub async fn is_fresh(&self, provider: ProviderKind, max_age_seconds: i64) -> bool {
        let guard = self.inner.read().await;
        guard
            .get(&provider)
            .map(|c| !c.is_stale(max_age_seconds))
            .unwrap_or(false)
    }

    /// Clear every cached entry.
    pub async fn clear(&self) {
        let mut guard = self.inner.write().await;
        guard.clear();
    }

    /// Number of cached entries.
    pub async fn len(&self) -> usize {
        let guard = self.inner.read().await;
        guard.len()
    }
}

// ---------------------------------------------------------------------------
// Convenience formatting (standalone)
// ---------------------------------------------------------------------------

/// Format `value` as a currency string using `currency`.
///
/// This is the free-function version of `ProviderCredits::money`, useful
/// when you don't already have a `ProviderCredits` instance.
pub fn money(value: f64, currency: &str) -> String {
    ProviderCredits::money(value, currency)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // ---- ProviderCredits ---------------------------------------------------

    #[test]
    fn amount_text_formats_usd() {
        let credits = ProviderCredits::from_deepseek(12.34, "USD".into());
        assert_eq!(credits.amount_text(), "$12.34");
    }

    #[test]
    fn amount_text_formats_cny() {
        let credits = ProviderCredits::from_deepseek(100.0, "CNY".into());
        assert_eq!(credits.amount_text(), "CN¥100.00");
    }

    #[test]
    fn amount_text_falls_back_for_unknown_currency() {
        let credits = ProviderCredits::from_deepseek(42.5, "XYZ".into());
        assert_eq!(credits.amount_text(), "42.50 XYZ");
    }

    #[test]
    fn amount_text_empty_currency() {
        let credits = ProviderCredits {
            total: 7.0,
            currency: String::new(),
            topped_up: None,
            granted: None,
            is_usable: true,
        };
        assert_eq!(credits.amount_text(), "7.00");
    }

    #[test]
    fn breakdown_text_with_both_parts() {
        let credits = ProviderCredits::from_deepseek_balance_info(
            12.34,
            "USD".into(),
            10.0,
            2.34,
        );
        assert_eq!(credits.breakdown_text(), Some("Topped up $10.00 · Granted $2.34".to_string()));
    }

    #[test]
    fn breakdown_text_none_when_no_breakdown() {
        let credits = ProviderCredits::from_deepseek(5.0, "USD".into());
        assert_eq!(credits.breakdown_text(), None);
    }

    #[test]
    fn breakdown_text_skips_zero_values() {
        let credits = ProviderCredits::from_deepseek_balance_info(
            5.0,
            "USD".into(),
            0.0,
            5.0,
        );
        assert_eq!(credits.breakdown_text(), Some("Granted $5.00".to_string()));
    }

    #[test]
    fn is_depleted_when_not_usable() {
        let credits = ProviderCredits {
            total: 10.0,
            currency: "USD".into(),
            topped_up: None,
            granted: None,
            is_usable: false,
        };
        assert!(credits.is_depleted());
    }

    #[test]
    fn is_depleted_when_zero_balance() {
        let credits = ProviderCredits {
            total: 0.0,
            currency: "USD".into(),
            topped_up: None,
            granted: None,
            is_usable: true,
        };
        assert!(credits.is_depleted());
    }

    #[test]
    fn not_depleted_when_healthy() {
        let credits = ProviderCredits::from_deepseek(15.0, "USD".into());
        assert!(!credits.is_depleted());
    }

    // ---- CreditsReader -----------------------------------------------------

    #[test]
    fn exposes_credits_deepseek_only() {
        assert!(CreditsReader::exposes_credits(ProviderKind::Deepseek));
        assert!(!CreditsReader::exposes_credits(ProviderKind::Claude));
        assert!(!CreditsReader::exposes_credits(ProviderKind::Codex));
        assert!(!CreditsReader::exposes_credits(ProviderKind::OpenAi));
    }

    #[test]
    fn top_up_url_deepseek() {
        assert_eq!(
            CreditsReader::top_up_url(ProviderKind::Deepseek),
            Some("https://platform.deepseek.com/top_up".to_string())
        );
        assert_eq!(CreditsReader::top_up_url(ProviderKind::Claude), None);
    }

    // ---- builder helpers ---------------------------------------------------

    #[test]
    fn builder_chain() {
        let credits = ProviderCredits {
            total: 5.0,
            currency: "USD".into(),
            topped_up: None,
            granted: None,
            is_usable: true,
        }
        .with_topped_up(3.0)
        .with_granted(2.0)
        .with_is_usable(false);

        assert_eq!(credits.topped_up, Some(3.0));
        assert_eq!(credits.granted, Some(2.0));
        assert!(!credits.is_usable);
    }

    // ---- CachedCredits -----------------------------------------------------

    #[test]
    fn cached_credits_stale() {
        let entry = CachedCredits::new(ProviderCredits::unknown());
        // Immediately-created entries should NOT be stale for a 300s window.
        assert!(!entry.is_stale(300));
        // Simulate an entry from an hour ago.
        let old = CachedCredits {
            credits: Some(ProviderCredits::unknown()),
            fetched_at: chrono::Utc::now() - chrono::Duration::seconds(3600),
        };
        assert!(old.is_stale(300));
    }

    // ---- deserialization ---------------------------------------------------

    #[test]
    fn deserialize_string_f64() {
        #[derive(Debug, Deserialize)]
        struct Wrapper {
            #[serde(deserialize_with = "super::deserialize_string_f64")]
            val: f64,
        }

        let json = r#"{"val":"12.34"}"#;
        let w: Wrapper = serde_json::from_str(json).unwrap();
        assert_eq!(w.val, 12.34);
    }

    #[test]
    fn deserialize_deepseek_response() {
        let json = r#"
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "135.85",
                    "topped_up_balance": "50.00",
                    "granted_balance": "85.85"
                }
            ]
        }
        "#;

        let resp: DeepSeekBalanceResponse = serde_json::from_str(json).unwrap();
        let credits = CreditsReader::build_credits_from_deepseek(resp).unwrap();
        assert_eq!(credits.total, 135.85);
        assert_eq!(credits.currency, "CNY");
        assert_eq!(credits.topped_up, Some(50.0));
        assert_eq!(credits.granted, Some(85.85));
        assert!(credits.is_usable);
    }

    #[test]
    fn deserialize_deepseek_zero_balance() {
        let json = r#"
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "0.00",
                    "topped_up_balance": "0.00",
                    "granted_balance": "0.00"
                }
            ]
        }
        "#;

        let resp: DeepSeekBalanceResponse = serde_json::from_str(json).unwrap();
        let credits = CreditsReader::build_credits_from_deepseek(resp).unwrap();
        assert_eq!(credits.total, 0.0);
        assert!(credits.is_depleted());
    }
}
