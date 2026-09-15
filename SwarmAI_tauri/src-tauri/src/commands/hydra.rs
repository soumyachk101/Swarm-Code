use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use tauri::State;

use crate::types::{HydraConfig, HydraRun, HydraHeadStatus, HydraRunStatus};
use crate::models::hydra::HydraPair;
use crate::models::provider::ProviderKind;
use crate::store::AppStore;

fn parse_provider_kind(s: &str) -> Option<ProviderKind> {
 match s.to_lowercase().as_str() {
 "codex" => Some(ProviderKind::Codex),
 "claude" => Some(ProviderKind::Claude),
 "cursor" => Some(ProviderKind::Cursor),
 "opencode" => Some(ProviderKind::Opencode),
 "grok" => Some(ProviderKind::Grok),
 "deepseek" | "deep-seek" => Some(ProviderKind::Deepseek),
 "meta" => Some(ProviderKind::Meta),
 "devin" => Some(ProviderKind::Devin),
 "antigravity" | "anti-gravity" => Some(ProviderKind::Antigravity),
 "copilot" => Some(ProviderKind::Copilot),
 _ => None,
 }
}

#[tauri::command]
pub async fn create_hydra(
 config: HydraConfig,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<HydraPair, String> {
 let provider_kind = parse_provider_kind(&config.provider)
 .ok_or_else(|| format!("Unknown provider: {}", config.provider))?;

 let mut store = state.write().await;
 let mut pair = HydraPair::new(provider_kind);
 if let Some(model) = config.model {
 pair.orchestrator_model = Some(model);
 }
 if let Some(effort) = config.effort {
 pair.orchestrator_effort = Some(effort);
 }
 if let Some(max_heads) = config.max_heads {
 pair.max_heads = Some(max_heads);
 }
 pair.auto_merge = config.auto_merge;
 pair.reviews_heads = config.reviews_heads;
 pair.isolates_heads = config.isolates_heads;
 store.hydra_pairs.push(pair.clone());
 store.save();
 Ok(pair)
}

#[tauri::command]
pub async fn get_hydra(
 id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<HydraPair, String> {
 let store = state.read().await;
 let hid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
 store
 .hydra_pairs
 .iter()
 .find(|p| p.id == hid)
 .cloned()
 .ok_or_else(|| format!("Hydra '{}' not found", id))
}

#[tauri::command]
pub async fn get_hydras(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<HydraPair>, String> {
 let store = state.read().await;
 Ok(store.hydra_pairs.clone())
}

#[tauri::command]
pub async fn update_hydra(
 id: String,
 config: HydraConfig,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<HydraPair, String> {
 let mut store = state.write().await;
 let hid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
 let updated = {
 let pair = store
 .hydra_pairs
 .iter_mut()
 .find(|p| p.id == hid)
 .ok_or_else(|| format!("Hydra '{}' not found", id))?;

 if let Some(model) = config.model {
 pair.orchestrator_model = Some(model);
 }
 if let Some(effort) = config.effort {
 pair.orchestrator_effort = Some(effort);
 }
 if let Some(max_heads) = config.max_heads {
 pair.max_heads = Some(max_heads);
 }
 pair.auto_merge = config.auto_merge;
 pair.reviews_heads = config.reviews_heads;
 pair.isolates_heads = config.isolates_heads;
 pair.clone()
 };
 store.save();
 Ok(updated)
}

#[tauri::command]
pub async fn delete_hydra(
 id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 let hid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
 let count_before = store.hydra_pairs.len();
 store.hydra_pairs.retain(|p| p.id != hid);
 if store.hydra_pairs.len() == count_before {
 return Err(format!("Hydra '{}' not found", id));
 }
 store.save();
 Ok(())
}

#[tauri::command]
pub async fn start_hydra_run(
 hydra_id: String,
 prompt: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<HydraRun, String> {
 let store = state.read().await;
 let hid = Uuid::parse_str(&hydra_id).map_err(|e| e.to_string())?;
 let _pair = store
 .hydra_pairs
 .iter()
 .find(|p| p.id == hid)
 .ok_or_else(|| format!("Hydra '{}' not found", hydra_id))?;

 let heads = vec![
 HydraHeadStatus {
 index: 0,
 name: "orchestrator".to_string(),
 task: prompt.clone(),
 status: "running".to_string(),
 progress: 0.0,
 summary: None,
 started_at: chrono::Utc::now(),
 finished_at: None,
 },
 HydraHeadStatus {
 index: 1,
 name: "worker-1".to_string(),
 task: prompt.clone(),
 status: "running".to_string(),
 progress: 0.0,
 summary: None,
 started_at: chrono::Utc::now(),
 finished_at: None,
 },
 ];

 let run = HydraRun {
 id: Uuid::new_v4(),
 hydra_id: hid,
 prompt,
 heads,
 status: HydraRunStatus::Running,
 started_at: chrono::Utc::now(),
 completed_at: None,
 };

 Ok(run)
}

#[tauri::command]
pub async fn stop_hydra_run(
 _hydra_id: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 Ok(())
}
