use std::sync::Arc;
use tokio::sync::RwLock;

use tauri::State;

use crate::types::{ProviderTestResult, ModelInfo as TypesModelInfo, ProviderCredits};
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
 let (success, message, models, kind_str) = if statuses.is_empty() {
  (false, "No providers detected".to_string(), vec![], "none".to_string())
 } else {
  let (kind, status) = statuses[0].clone();
  let kind_str = kind.to_string();
  if status.api_key_configured {
   let provider_models = registry.models(kind);
   let infos: Vec<TypesModelInfo> = provider_models.into_iter().map(|m| TypesModelInfo {
    id: m.id,
    name: m.name,
    detail: m.detail,
    efforts: m.efforts,
    default_effort: m.default_effort,
    is_default: m.is_default,
    fast_tier: m.fast_tier,
   }).collect();
   (true, "Provider is configured".to_string(), infos, kind_str)
  } else {
   (false, format!("Provider not available: {}", status.error.as_deref().unwrap_or("unknown")), vec![], kind_str)
  }
 };
 let elapsed = start.elapsed().as_millis() as u64;
 Ok(ProviderTestResult {
  success,
  message,
  models,
  response_time_ms: Some(elapsed),
  kind: kind_str,
  tested_at: chrono::Utc::now(),
 })
}

#[tauri::command]
pub async fn get_available_models(
 provider_type: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<TypesModelInfo>, String> {
 let store = state.read().await;
 Ok(store.settings.model_list.iter().map(|m| TypesModelInfo {
  id: m.id.clone(),
  name: m.name.clone(),
  detail: m.detail.clone(),
  efforts: m.efforts.clone(),
  default_effort: m.default_effort.clone(),
  is_default: m.is_default,
  fast_tier: m.fast_tier.clone(),
 }).collect())
}

#[tauri::command]
pub async fn get_provider_credits(
 provider: String,
) -> Result<ProviderCredits, String> {
 Ok(ProviderCredits {
  provider_id: provider,
  remaining: None,
  unit: None,
  resets_at: None,
  is_unlimited: false,
 })
}
