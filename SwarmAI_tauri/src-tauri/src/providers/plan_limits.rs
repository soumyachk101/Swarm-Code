use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Plan limits
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlanLimits {
 pub plan_name: Option<String>,
 pub windows: Vec<Window>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Window {
 pub id: String,
 pub title: String,
 pub percent: f64,
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
}

impl PlanLimits {
 pub fn is_exhausted(&self) -> bool {
 self.windows.iter().any(|w| w.percent >= 100.0)
 }

 pub fn exhausted_window(&self) -> Option<&Window> {
 self.windows.iter().find(|w| w.percent >= 100.0)
 }
}

// ---------------------------------------------------------------------------
// Plan limits reader (static catalog)
// ---------------------------------------------------------------------------

pub struct PlanLimitsReader;

impl PlanLimitsReader {
 pub fn exposes_limits(_provider: crate::models::provider::ProviderKind) -> bool {
 true
 }

 pub async fn read(
 _provider: crate::models::provider::ProviderKind,
 _executable: String,
 _environment: std::collections::HashMap<String, String>,
 ) -> Option<PlanLimits> {
 None
 }

 pub fn window_title(minutes: Option<i64>) -> String {
 match minutes {
 Some(m) if m <= 60 => format!("{} min window", m),
 Some(m) => {
 let h = m / 60;
 let rem = m % 60;
 if rem == 0 {
 format!("{}h window", h)
 } else {
 format!("{}h {}m window", h, rem)
 }
 }
 None => "Window".to_string(),
 }
 }

 pub fn plan_name(raw: Option<&str>) -> Option<String> {
 let name = raw?.trim();
 if name.is_empty() {
 None
 } else {
 Some(name.to_string())
 }
 }
}
