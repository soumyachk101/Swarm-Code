use std::sync::Arc;
use tokio::sync::RwLock;

use tauri::State;

use crate::types::{ProviderTestResult, ModelInfo, ProviderCredits};
use crate::models::provider::ProviderKind;
use crate::providers::registry::ProviderRegistry;
use crate::store::AppStore;

#[tauri::command]
pub async fn get_provider_descriptors(
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<crate::providers::registry::ProviderDescriptor>, String> {
 let registry = ProviderRegistry::new();
 Ok(registry.list().into_iter().filter_map(|kind| registry.get(kind).cloned()).collect())
}

#[tauri::command]
pub async fn save_provider(
 provider: crate::providers::registry::ProviderDescriptor,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::providers::registry::ProviderDescriptor, String> {
 Ok(provider)
}

#[tauri::command]
pub async fn delete_provider(
 provider_id: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let _ = provider_id;
 Ok(())
}

#[tauri::command]
pub async fn test_provider(
 provider_id: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ProviderTestResult, String> {
 let _ = provider_id;
 let start = std::time::Instant::now();
 let detection = ProviderRegistry::detect();
 let registry = match detection {
 Ok(r) => r,
 Err(_) => ProviderRegistry::new(),
 };
 let statuses = registry.statuses();
 let (success, message, models) = if statuses.is_empty() {
 (false, "No providers detected".to_string(), vec![])
 } else {
 let (kind, status) = statuses[0].clone();
 if status.api_key_configured {
 let provider_models = registry.models(kind);
 let infos: Vec<ModelInfo> = provider_models.into_iter().map(|m| ModelInfo {
 id: m.id,
 name: m.name,
 detail: m.detail,
 efforts: m.efforts,
 default_effort: m.default_effort,
 is_default: m.is_default,
 fast_tier: m.fast_tier,
 }).collect();
 (true, "Provider is configured".to_string(), infos)
 } else {
 (false, format!("Provider not configured: {}", status.last_error.as_deref().unwrap_or("unknown")), vec![])
 }
 };
 let elapsed = start.elapsed().as_millis() as u64;
 Ok(ProviderTestResult {
 success,
 message,
 models,
 response_time_ms: Some(elapsed),
 })
}

#[tauri::command]
pub async fn get_available_models(
 provider_type: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<ModelInfo>, String> {
 let store = state.read().await;

 let kind = match provider_type.to_lowercase().as_str() {
 "codex" => ProviderKind::Codex,
 "claude" => ProviderKind::Claude,
 "openai" => ProviderKind::OpenAi,
 "cursor" => ProviderKind::Cursor,
 "opencode" => ProviderKind::Opencode,
 "grok" => ProviderKind::Grok,
 "deepseek" => ProviderKind::Deepseek,
 "gemini" => ProviderKind::Gemini,
 "meta" => ProviderKind::Meta,
 "devin" => ProviderKind::Devin,
 "antigravity" => ProviderKind::Antigravity,
 "copilot" => ProviderKind::Copilot,
 "acp" => ProviderKind::ACP,
 _ => return Err(format!("Unknown provider type: {}", provider_type)),
 };

 let models: Vec<ModelInfo> = store
 .settings
 .model_list
 .iter()
 .map(|m| ModelInfo {
 id: m.id.clone(),
 name: m.name.clone(),
 detail: m.detail.clone(),
 efforts: m.efforts.clone(),
 default_effort: m.default_effort.clone(),
 is_default: m.is_default,
 fast_tier: m.fast_tier.clone(),
 })
 .collect();

 if models.is_empty() {
 let registry = ProviderRegistry::new();
 let registry_models = registry.models(kind);
 Ok(registry_models.into_iter().map(|m| ModelInfo {
 id: m.id,
 name: m.name,
 detail: m.detail,
 efforts: m.efforts,
 default_effort: m.default_effort,
 is_default: m.is_default,
 fast_tier: m.fast_tier,
 }).collect())
 } else {
 Ok(models)
 }
}

#[tauri::command]
pub async fn get_provider_credits(
 provider_id: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<ProviderCredits, String> {
 Ok(ProviderCredits {
 provider_id,
 remaining: None,
 unit: None,
 resets_at: None,
 is_unlimited: true,
 })
}
