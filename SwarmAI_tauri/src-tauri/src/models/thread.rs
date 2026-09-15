use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::provider::{InteractionMode, ProviderKind, RuntimeMode};
use super::hydra::HydraHeadInfo;

// ---------------------------------------------------------------------------
// ThreadKind (mirrors Swift ThreadKind)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ThreadKind {
 Regular,
 Worktree,
 Helper,
 HydraHead,
}

impl Default for ThreadKind {
 fn default() -> Self {
 Self::Regular
 }
}

impl ThreadKind {
 pub fn is_helper(&self) -> bool {
 matches!(self, Self::Helper | Self::HydraHead)
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
 pub id: Uuid,
 pub name: String,
 pub path: String,
 pub added_at: DateTime<Utc>,
 pub is_expanded: bool,
 pub scripts: Vec<ProjectScript>,
}

impl Project {
 pub fn new(name: String, path: String) -> Self {
 Self {
 id: Uuid::new_v4(),
 name,
 path,
 added_at: Utc::now(),
 is_expanded: true,
 scripts: Vec::new(),
 }
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectScript {
 pub id: Uuid,
 pub name: String,
 pub command: String,
 pub symbol: String,
 pub run_on_worktree_create: bool,
}

impl ProjectScript {
 pub fn new(name: String, command: String, symbol: String, run_on_worktree_create: bool) -> Self {
 Self {
 id: Uuid::new_v4(),
 name,
 command,
 symbol,
 run_on_worktree_create,
 }
 }
}

// ---------------------------------------------------------------------------
// ThreadFilter
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum ThreadFilter {
 #[default]
 All,
 Pinned,
 Hydra,
 Settled,
 Archived,
 Helper,
}

// ---------------------------------------------------------------------------
// ChatThread
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatThread {
 pub id: Uuid,
 pub project_id: Uuid,
 pub title: String,
 pub created_at: DateTime<Utc>,
 pub updated_at: DateTime<Utc>,
 pub provider: ProviderKind,
 pub model: Option<String>,
 pub effort: Option<String>,
 pub fast_mode: bool,
 pub runtime_mode: RuntimeMode,
 pub interaction_mode: InteractionMode,
 pub worktree_path: Option<String>,
 pub branch: Option<String>,
 pub provider_session_id: Option<String>,
 pub is_pinned: bool,
 pub is_archived: bool,
 pub is_settled: bool,
 pub settled_at: Option<DateTime<Utc>>,
 pub has_unread: bool,
 pub has_custom_title: bool,
 pub sort_order: Option<f64>,
 pub activity_order: Option<f64>,
 pub activity_order_day: Option<DateTime<Utc>>,
 pub last_status: Option<String>,
 pub parent_thread_id: Option<Uuid>,
 pub is_in_panel: bool,
 pub folds_helpers: bool,
 pub hydra_enabled: bool,
 pub hydra_pair_id: Option<Uuid>,
 pub hydra_spawn_count: u32,
 pub hydra: Option<HydraHeadInfo>,
}

impl ChatThread {
 pub fn untitled() -> &'static str {
 "New thread"
 }

 pub fn is_helper(&self) -> bool {
 self.parent_thread_id.is_some()
 }

 pub fn is_hydra_head(&self) -> bool {
 self.hydra.is_some()
 }

 pub fn new(
 project_id: Uuid,
 provider: ProviderKind,
 model: Option<String>,
 effort: Option<String>,
 runtime_mode: RuntimeMode,
 fast_mode: bool,
 ) -> Self {
 let now = Utc::now();
 Self {
 id: Uuid::new_v4(),
 project_id,
 title: Self::untitled().to_string(),
 created_at: now,
 updated_at: now,
 provider,
 model,
 effort,
 fast_mode,
 runtime_mode,
 interaction_mode: InteractionMode::Build,
 worktree_path: None,
 branch: None,
 provider_session_id: None,
 is_pinned: false,
 is_archived: false,
 is_settled: false,
 settled_at: None,
 has_unread: false,
 has_custom_title: false,
 sort_order: None,
 activity_order: None,
 activity_order_day: None,
 last_status: None,
 parent_thread_id: None,
 is_in_panel: false,
 folds_helpers: false,
 hydra_enabled: false,
 hydra_pair_id: None,
 hydra_spawn_count: 0,
 hydra: None,
 }
 }
}
