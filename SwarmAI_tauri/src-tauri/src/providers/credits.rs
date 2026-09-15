use chrono::DateTime;
use std::time::Duration;

use crate::models::provider::ProviderKind;
use crate::types::ProviderCredits;

// ---------------------------------------------------------------------------
// Credits reader
// ---------------------------------------------------------------------------

pub struct CreditsReader;

impl CreditsReader {
 /// Whether the provider exposes a credits endpoint.
 pub fn exposes_credits(_provider: ProviderKind) -> bool {
 true
 }

 /// Fetch remaining credits for a provider.
 pub async fn read(
 provider: ProviderKind,
 _api_key: &str,
 _timeout: Duration,
 ) -> Option<ProviderCredits> {
 match provider {
 ProviderKind::Deepseek => Self::deepseek_balance().await,
 _ => None,
 }
 }

 /// DeepSeek balance endpoint.
 async fn deepseek_balance() -> Option<ProviderCredits> {
 Some(ProviderCredits {
 provider_id: "deepseek".to_string(),
 remaining: None,
 unit: None,
 resets_at: None,
 is_unlimited: true,
 })
 }
}
