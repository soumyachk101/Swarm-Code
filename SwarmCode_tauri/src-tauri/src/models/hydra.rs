use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::provider::ProviderKind;

// Re-export shared hydra types defined in types.rs.
pub use crate::types::{
 HydraConfig as TypesHydraConfig,
 HydraHeadStatus,
 HydraRun as TypesHydraRun,
 HydraRunStatus,
};

// ---------------------------------------------------------------------------
// HydraPair (mirrors Swift HydraPair)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraPair {
 pub id: Uuid,
 pub provider: ProviderKind,
 pub orchestrator_model: Option<String>,
 pub orchestrator_effort: Option<String>,
 pub worker_provider: Option<ProviderKind>,
 pub worker_model: Option<String>,
 pub worker_effort: Option<String>,
 pub max_heads: Option<u32>,
 /// Pair-specific override for auto-merge.
 pub auto_merge: bool,
 /// Pair-specific override for reviews-heads.
 pub reviews_heads: bool,
 /// Pair-specific override for isolates-heads.
 pub isolates_heads: bool,
}

impl HydraPair {
 pub const MAX_HEADS_RANGE: std::ops::RangeInclusive<u32> = 1..=8;

 pub fn new(provider: ProviderKind) -> Self {
 Self {
 id: Uuid::new_v4(),
 provider,
 orchestrator_model: None,
 orchestrator_effort: None,
 worker_provider: None,
 worker_model: None,
 worker_effort: None,
 max_heads: None,
 auto_merge: false,
 reviews_heads: false,
 isolates_heads: true,
 }
 }

 pub fn heads_provider(&self) -> ProviderKind {
 self.worker_provider.unwrap_or(self.provider)
 }

 pub fn sends_heads_elsewhere(&self) -> bool {
 self.worker_provider.map(|w| w != self.provider).unwrap_or(false)
 }

 pub fn clamped_cap(cap: Option<u32>) -> Option<u32> {
 cap.map(|c| c.clamp(*Self::MAX_HEADS_RANGE.start(), *Self::MAX_HEADS_RANGE.end()))
 }
}

// ---------------------------------------------------------------------------
// HydraHeadProfile (mirrors Swift HydraHeadProfile)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HydraHeadProfile {
 pub id: Uuid,
 pub name: String,
 pub description: Option<String>,
 pub max_heads: Option<u32>,
 pub head_provider: Option<ProviderKind>,
 pub head_model: Option<String>,
 pub head_effort: Option<String>,
 #[serde(default)]
 pub match_mode: HydraMatchMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default, Copy)]
#[serde(rename_all = "snake_case")]
pub enum HydraMatchMode {
 /// Match a chat by its exact title.
 #[serde(rename = "title")]
 Title,
 /// Match any chat for the same provider+model combo.
 #[serde(rename = "wildcard")]
 #[default]
 Wildcard,
}

impl HydraHeadProfile {
 pub const MIN_HEADS: u32 = 1;
 pub const MAX_HEADS: u32 = 50;

 /// Returns true when the profile applies to `provider`/`model`: either the
 /// profile wildcards both fields, or at least one is set and the chat matches it.
 pub fn applies_to(&self, provider: ProviderKind, model: Option<&str>) -> bool {
 match (self.head_provider, &self.head_model) {
 (None, None) => true,
 (Some(p), None) => p == provider,
 (None, Some(m)) => model.map(|md| md == m).unwrap_or(false),
 (Some(p), Some(m)) => {
 let provider_match = p == provider;
 let model_match = model.map(|md| md == m).unwrap_or(false);
 provider_match || model_match
 }
 }
 }

 /// Clamp `max_heads` into the [MIN_HEADS, MAX_HEADS] range, returning None when absent.
 pub fn clamped_max_heads(&self) -> Option<u32> {
 self.max_heads.map(|v| v.clamp(Self::MIN_HEADS, Self::MAX_HEADS))
 }

 /// Returns the effective max-heads for this profile, or None when not set.
 pub fn effective_max_heads(&self) -> Option<u32> {
 self.clamped_max_heads()
 }
}

// ---------------------------------------------------------------------------
// HydraLaunch (mirrors Swift HydraLaunch)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraLaunch {
 pub heads_provider: ProviderKind,
 pub runs_natively: bool,
 pub heads_label: Option<String>,
 pub worker_model: Option<String>,
 pub worker_effort: Option<String>,
 pub max_heads: Option<u32>,
 #[serde(default = "default_isolates")]
 pub isolates_heads: bool,
 #[serde(default)]
 pub auto_merges: bool,
 #[serde(default)]
 pub reviews_heads: bool,
}

fn default_isolates() -> bool {
 true
}

impl HydraLaunch {
 pub fn has_room(&self, running: u32) -> bool {
 self.max_heads.map(|m| running < m).unwrap_or(true)
 }
}

// ---------------------------------------------------------------------------
// HydraPersona (a head's identity: name, asset, hex colour)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct HydraPersona {
 pub name: &'static str,
 pub asset: &'static str,
 pub hex: u32,
}

impl HydraPersona {
 pub const fn new(name: &'static str, asset: &'static str, hex: u32) -> Self {
 Self { name, asset, hex }
 }

 pub fn color(&self) -> (f64, f64, f64) {
 let r = ((self.hex >> 16) & 0xFF) as f64 / 255.0;
 let g = ((self.hex >> 8) & 0xFF) as f64 / 255.0;
 let b = (self.hex & 0xFF) as f64 / 255.0;
 (r, g, b)
 }
}

// ---------------------------------------------------------------------------
// HydraHeadInfo sub-enums
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HydraHeadKind {
 Native,
 Droppy,
}

impl Default for HydraHeadKind {
 fn default() -> Self {
 Self::Droppy
 }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HydraHeadOrigin {
 Delegated,
 Queued,
 Sent,
}

impl Default for HydraHeadOrigin {
 fn default() -> Self {
 Self::Delegated
 }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HydraHeadLifecycle {
 Running,
 Completed,
 Failed,
 Stopped,
}

impl Default for HydraHeadLifecycle {
 fn default() -> Self {
 Self::Stopped
 }
}

impl HydraHeadLifecycle {
 pub fn is_finished(&self) -> bool {
 !matches!(self, Self::Running)
 }
}

// ---------------------------------------------------------------------------
// HydraHeadInfo (a head's place in its lead's team)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraHeadInfo {
 pub index: u32,
 pub task: String,
 pub kind: HydraHeadKind,
 pub origin: HydraHeadOrigin,
 pub status: HydraHeadLifecycle,
 pub summary: Option<String>,
 pub activity: Option<String>,
 pub tool_calls: u32,
 pub tokens: u64,
 pub started_at: DateTime<Utc>,
 pub finished_at: Option<DateTime<Utc>>,
 pub native_id: Option<String>,
 pub native_task_id: Option<String>,
 pub tool_use_id: Option<String>,
 pub batch_id: Option<Uuid>,
 pub can_stop: bool,
 pub is_background: bool,
 pub base_tree: Option<String>,
 pub landing: Option<HydraLanding>,
}

impl HydraHeadInfo {
 pub fn new(index: u32, task: String, kind: HydraHeadKind, origin: HydraHeadOrigin) -> Self {
 let can_stop = matches!(kind, HydraHeadKind::Droppy);
 Self {
 index,
 task,
 kind,
 origin,
 status: HydraHeadLifecycle::Running,
 summary: None,
 activity: None,
 tool_calls: 0,
 tokens: 0,
 started_at: Utc::now(),
 finished_at: None,
 native_id: None,
 native_task_id: None,
 tool_use_id: None,
 batch_id: None,
 can_stop,
 is_background: true,
 base_tree: None,
 landing: None,
 }
 }

 pub fn is_finished(&self) -> bool {
 self.status.is_finished()
 }

 pub fn has_own_copy(&self) -> bool {
 self.base_tree.is_some()
 }
}

// ---------------------------------------------------------------------------
// HydraLanding (where a head's work went when it reported)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HydraLanding {
 pub files: Vec<HydraLandingFile>,
 pub conflicts: Vec<String>,
 pub patch_path: Option<String>,
 pub error: Option<String>,
}

impl HydraLanding {
 pub fn is_empty(&self) -> bool {
 self.files.is_empty() && self.patch_path.is_none() && self.error.is_none()
 }

 pub fn landed(&self) -> bool {
 !self.files.is_empty() && self.patch_path.is_none() && self.error.is_none()
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraLandingFile {
 pub path: String,
 pub additions: u32,
 pub deletions: u32,
}

// ---------------------------------------------------------------------------
// HydraDelegation (a head the lead asked for via the delegation block)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraDelegation {
 pub task: String,
 pub prompt: String,
 pub name: Option<String>,
}

// ---------------------------------------------------------------------------
// HydraReport (what a head sends back to its lead)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraReport {
 pub head_index: u32,
 pub task: String,
 pub origin: HydraHeadOrigin,
 pub status: HydraHeadLifecycle,
 pub text: String,
 pub landing: Option<HydraLanding>,
 pub copy_path: Option<String>,
 pub elapsed: Option<f64>,
 pub tool_calls: u32,
}

// ---------------------------------------------------------------------------
// HydraPersona roster (mirrors Swift HydraRoster)
// ---------------------------------------------------------------------------

pub struct HydraRoster;

impl HydraRoster {
 pub fn personas() -> Vec<HydraPersona> {
 vec![
 HydraPersona::new("Hank", "hydra-head-01", 0xFF8A3D),
 HydraPersona::new("Walter", "hydra-head-02", 0x3D8BFF),
 HydraPersona::new("Ada", "hydra-head-03", 0x34C46A),
 HydraPersona::new("Otto", "hydra-head-04", 0xA35BE0),
 HydraPersona::new("Nova", "hydra-head-05", 0xF25C9A),
 HydraPersona::new("Remy", "hydra-head-06", 0x2BB5B0),
 HydraPersona::new("Iris", "hydra-head-07", 0xE8B430),
 HydraPersona::new("Milo", "hydra-head-08", 0xE84F4F),
 HydraPersona::new("Juno", "hydra-head-09", 0x6A5CFF),
 HydraPersona::new("Ezra", "hydra-head-10", 0x4FD1A1),
 HydraPersona::new("Lena", "hydra-head-11", 0x2FB8E6),
 HydraPersona::new("Bo", "hydra-head-12", 0xB0784A),
 HydraPersona::new("Kai", "hydra-head-13", 0x8FD14F),
 HydraPersona::new("Vera", "hydra-head-14", 0xD946EF),
 HydraPersona::new("Finn", "hydra-head-15", 0xF97316),
 HydraPersona::new("Mira", "hydra-head-16", 0xC084FC),
 HydraPersona::new("Odin", "hydra-head-17", 0xB45309),
 HydraPersona::new("Suki", "hydra-head-18", 0xF472B6),
 HydraPersona::new("Rex", "hydra-head-19", 0x2563EB),
 HydraPersona::new("Zola", "hydra-head-20", 0x65A30D),
 HydraPersona::new("Pip", "hydra-head-21", 0x94A3B8),
 HydraPersona::new("Ivo", "hydra-head-22", 0x0D9488),
 HydraPersona::new("Lux", "hydra-head-23", 0xFACC15),
 HydraPersona::new("Tova", "hydra-head-24", 0x059669),
 HydraPersona::new("Gus", "hydra-head-25", 0x7DD3FC),
 ]
 }

 pub fn persona_at(index: u32) -> HydraPersona {
 let personas = Self::personas();
 let count = personas.len();
 let idx = (((index as usize) % count) + count) % count;
 let base = &personas[idx];
 let round = ((index as i64) / (count as i64)).max(0) as u32;
 if round > 0 {
 let name: &'static str = Box::leak(format!("{} {}", base.name, round + 1).into_boxed_str());
 HydraPersona::new(name, base.asset, base.hex)
 } else {
 HydraPersona::new(base.name, base.asset, base.hex)
 }
 }

 /// The roster index for an announced head name, case-insensitive.
 /// A trailing round number ("Otto 2") is treated as the display suffix.
 pub fn index_named(name: &str) -> Option<u32> {
 let mut bare = name.trim().to_string();
 if let Some(space_idx) = bare.rfind(' ') {
 let after = &bare[space_idx + 1..];
 if after.parse::<u32>().is_ok() {
 bare = bare[..space_idx].trim().to_string();
 }
 }
 let personas = Self::personas();
 for (i, persona) in personas.iter().enumerate() {
 if persona.name.eq_ignore_ascii_case(&bare) {
 return Some(i as u32);
 }
 }
 None
 }
}

// ---------------------------------------------------------------------------
// HydraBudget (mirrors Swift HydraBudget)
// ---------------------------------------------------------------------------

pub struct HydraBudget;

impl HydraBudget {
 pub const PACING_TOOLS: u32 = 24;
 pub const WRAP_UP_TOOLS: u32 = 120;
 pub const MAX_TOOLS: u32 = 160;
 pub const WRAP_UP_SECONDS: f64 = 25.0 * 60.0;
 pub const MAX_SECONDS: f64 = 35.0 * 60.0;
 pub const REPORT_SECONDS: f64 = 3.0 * 60.0;
 pub const MAX_DELEGATION_ROUNDS: u32 = 3;
 pub const WORKER_AGENT_NAME: &'static str = "swarmcode-worker";
 pub const SCOUT_AGENT_NAME: &'static str = "swarmcode-scout";
}

// ---------------------------------------------------------------------------
// HydraHead — runtime representation of a single head
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HydraHead {
 pub id: Uuid,
 pub parent_id: Uuid,
 pub name: String,
 pub task: String,
 pub provider: ProviderKind,
 pub model: Option<String>,
 pub status: HydraHeadLifecycle,
 pub kind: HydraHeadKind,
 pub origin: HydraHeadOrigin,
 pub messages: Vec<String>,
 pub errors: Vec<String>,
 pub started_at: DateTime<Utc>,
 pub finished_at: Option<DateTime<Utc>>,
}

impl HydraHead {
 pub fn new(parent_id: Uuid, info: &HydraHeadInfo, provider: ProviderKind, model: Option<String>) -> Self {
 let persona = HydraRoster::persona_at(info.index);
 Self {
 id: Uuid::new_v4(),
 parent_id,
 name: persona.name.to_string(),
 task: info.task.clone(),
 provider,
 model,
 status: info.status.clone(),
 kind: info.kind.clone(),
 origin: info.origin.clone(),
 messages: Vec::new(),
 errors: Vec::new(),
 started_at: Utc::now(),
 finished_at: None,
 }
 }
}

// ---------------------------------------------------------------------------
// Hydra — a single Hydra team (one per lead thread when Hydra is on).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hydra {
 pub id: Uuid,
 pub parent_thread_id: Uuid,
 pub title: String,
 pub heads: Vec<HydraHead>,
 pub config: crate::types::HydraConfig,
 pub status: HydraLifecycleStatus,
 pub created_at: DateTime<Utc>,
 pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HydraLifecycleStatus {
 Idle,
 Running,
 Completed,
 Failed,
 Stopped,
}

impl Default for HydraLifecycleStatus {
 fn default() -> Self {
 Self::Idle
 }
}

impl Hydra {
 pub fn new(parent_thread_id: Uuid, title: String, config: crate::types::HydraConfig) -> Self {
 let now = Utc::now();
 Self {
 id: Uuid::new_v4(),
 parent_thread_id,
 title,
 heads: Vec::new(),
 config,
 status: HydraLifecycleStatus::Idle,
 created_at: now,
 updated_at: now,
 }
 }

 pub fn spawn_count(&self) -> u32 {
 self.heads.len() as u32
 }

 pub fn running_count(&self) -> u32 {
 self.heads.iter().filter(|h| h.status == HydraHeadLifecycle::Running).count() as u32
 }

 pub fn finished_count(&self) -> u32 {
 self.heads.iter().filter(|h| h.status != HydraHeadLifecycle::Running).count() as u32
 }

 pub fn touch(&mut self) {
 self.updated_at = Utc::now();
 }
}

// ---------------------------------------------------------------------------
// ChatContext (mirrors Swift HydraPrompts.ChatContext)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ChatContext {
 pub last_user_prompt: Option<String>,
 pub last_reply: Option<String>,
 pub touched_paths: Vec<String>,
}

// ---------------------------------------------------------------------------
// Workplace enum (mirrors Swift HydraPrompts.Workplace)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Workplace {
 OwnCopy { path: String },
 Shared { path: String },
}

impl Workplace {
 pub fn path(&self) -> &str {
 match self {
 Self::OwnCopy { path } | Self::Shared { path } => path,
 }
 }
}
