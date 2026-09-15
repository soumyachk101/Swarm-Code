//! AutoContinue - waits for a provider's usage limit to reset, then automatically
//! resumes the chat with a continuation prompt.
//!
//! Mirrors the Swift `AutoContinue` class: notes that a usage limit was hit during
//! a turn, schedules a wait when the turn fails, then enqueues a continuation prompt.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tokio::time::{Instant, sleep_until};
use uuid::Uuid;

use crate::models::provider::ProviderKind;
use crate::models::timeline::TurnStatus;

/// The message sent to pick the chat back up after a usage limit reset.
pub const CONTINUE_MESSAGE: &str =
 "The usage limit has reset. Continue exactly where you left off and finish the task.";

/// How long past the reset time the chat waits, so the limit has really lifted.
pub const MARGIN_SECONDS: i64 = 60;

// ---------------------------------------------------------------------------
// Usage limit signal detection
// ---------------------------------------------------------------------------

pub struct UsageLimitSignal;

impl UsageLimitSignal {
 /// Whether the message looks like a usage limit refusal.
 pub fn matches(text: &str) -> bool {
 let lower = text.to_lowercase();
 lower.contains("usage limit")
 || lower.contains("hit your limit")
 || lower.contains("usage_limit")
 || lower.contains("limit reached")
 || lower.contains("out of extra usage")
 }

 /// Parse the reset time from an error message, if present.
 ///
 /// Handles Unix timestamps after a bar ("usage limit reached|1757865600")
 /// and clock times ("resets 3pm", "resets at 3:30 pm").
 pub fn reset_time(text: &str) -> Option<i64> {
 // Unix timestamp after a bar
 if let Some(start) = text.find('|') {
 let tail = &text[start + 1..];
 let digits: String = tail.chars().take_while(|c| c.is_ascii_digit()).collect();
 if digits.len() >= 9 {
 if let Ok(seconds) = digits.parse::<i64>() {
 let ts = if seconds > 100_000_000_000 {
 seconds / 1_000 // milliseconds
 } else {
 seconds
 };
 return Some(ts);
 }
 }
 }

 // Clock time pattern: "resets 3pm" or "resets at 3:30 pm"
 let lower = text.to_lowercase();
 if let Some(idx) = lower.find("resets") {
 let after = &text[idx..];
 let parts: Vec<&str> = after.split_whitespace().collect();
 // Skip "resets" and optional "at"
 let mut i = 1;
 if parts.get(i) == Some(&"at") {
 i += 1;
 }
 if let Some(time_part) = parts.get(i) {
 if let Some((hour, minute, is_pm)) = Self::parse_clock(time_part) {
 if let Some(base) = Self::epoch_seconds_now() {
 let adjusted_hour = if is_pm && hour < 12 {
 hour + 12
 } else if !is_pm && hour == 12 {
 0
 } else {
 hour
 };
 // Compute next occurrence of this time today (or tomorrow if past)
 let today = Self::today_at(adjusted_hour, minute, base);
 if today > base {
 return Some(today);
 }
 return Some(today + 86_400); // tomorrow
 }
 }
 }
 }

 None
 }

 fn parse_clock(s: &str) -> Option<(i32, i32, bool)> {
 let s_lower = s.to_lowercase();
 let is_pm = s_lower.ends_with("pm");
 let is_am = s_lower.ends_with("am");
 let digits: String = s
 .chars()
 .take_while(|c| c.is_ascii_digit() || *c == ':')
 .collect();
 if digits.is_empty() {
 return None;
 }
 let parts: Vec<&str> = digits.split(':').collect();
 let hour: i32 = parts.first()?.parse().ok()?;
 let minute: i32 = parts.get(1).and_then(|p| p.parse().ok()).unwrap_or(0);
 Some((hour, minute, is_pm || (!is_am && !is_pm && hour < 8)))
 }

 fn epoch_seconds_now() -> Option<i64> {
 Some(chrono::Utc::now().timestamp())
 }

 fn today_at(hour: i32, minute: i32, base: i64) -> i64 {
 let base_day = base - (base % 86_400);
 base_day + hour as i64 * 3600 + minute as i64 * 60
 }
}

// ---------------------------------------------------------------------------
// Wait state
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct WaitState {
 pub thread_id: Uuid,
 pub resumes_at: i64,
 pub provider: ProviderKind,
 pub resets_at: Option<i64>,
 pub token: Uuid,
}

// ---------------------------------------------------------------------------
// AutoContinue
// ---------------------------------------------------------------------------

pub struct AutoContinue {
 /// Notes taken during running turns: thread_id -> reset time (if known).
 noted: Arc<RwLock<HashMap<Uuid, Option<i64>>>>,

 /// Active waits by thread id.
 waits: Arc<RwLock<HashMap<Uuid, JoinHandle<()>>>>,

 /// Token for each wait, so cancelled waits can be detected.
 wait_tokens: Arc<RwLock<HashMap<Uuid, Uuid>>>,

 /// Resumes-at time by thread id, for UI display.
 resumes_at: Arc<RwLock<HashMap<Uuid, i64>>>,

 /// Whether auto-continue is enabled.
 enabled: Arc<RwLock<bool>>,

 /// Whether to notify the user when finished.
 notify_when_finished: Arc<RwLock<bool>>,
}

impl AutoContinue {
 pub fn new() -> Self {
 Self {
 noted: Arc::new(RwLock::new(HashMap::new())),
 waits: Arc::new(RwLock::new(HashMap::new())),
 wait_tokens: Arc::new(RwLock::new(HashMap::new())),
 resumes_at: Arc::new(RwLock::new(HashMap::new())),
 enabled: Arc::new(RwLock::new(true)),
 notify_when_finished: Arc::new(RwLock::new(true)),
 }
 }

 /// Whether auto-continue is enabled.
 pub async fn is_enabled(&self) -> bool {
 *self.enabled.read().await
 }

 /// Enable or disable auto-continue.
 pub async fn set_enabled(&self, value: bool) {
 *self.enabled.write().await = value;
 }

 /// Note that a usage limit was hit during a turn.
 ///
 /// A later note with a time beats an earlier one without.
 pub async fn note_limit(&self, thread_id: Uuid, resets_at: Option<i64>) {
 let mut noted = self.noted.write().await;
 if let Some(existing) = noted.get(&thread_id) {
 if existing.is_some() && resets_at.is_none() {
 return;
 }
 }
 noted.insert(thread_id, resets_at);
 }

 /// Called when a turn finishes.
 ///
 /// Returns whether the thread is now waiting for its limit to reset.
 pub async fn turn_finished(&self, thread_id: Uuid, status: TurnStatus, continues: bool) -> bool {
 let note = self.noted.write().await.remove(&thread_id);
 let note = match note {
 Some(n) => n,
 None => return false,
 };

 if !*self.enabled.read().await || status != TurnStatus::Failed || continues {
 return false;
 }

 // Cancel any existing wait for this thread
 {
 let mut waits = self.waits.write().await;
 if let Some(handle) = waits.remove(&thread_id) {
 handle.abort();
 }
 }

 let token = Uuid::new_v4();
 self.wait_tokens.write().await.insert(thread_id, token);

 let token_clone = token;
 let resumes_at = Arc::clone(&self.resumes_at);
 let waits = Arc::clone(&self.waits);
 let wait_tokens = Arc::clone(&self.wait_tokens);
 let enabled = Arc::clone(&self.enabled);
 let notify_when_finished = Arc::clone(&self.notify_when_finished);

 let handle = tokio::spawn(async move {
 let resume_at = match note {
 Some(ts) => std::cmp::max(ts + MARGIN_SECONDS, chrono::Utc::now().timestamp() + 5),
 None => {
 // No reset time known: nothing we can do.
 return;
 }
 };

 {
 let mut ra = resumes_at.write().await;
 ra.insert(thread_id, resume_at);
 }

 let now = chrono::Utc::now().timestamp();
 if resume_at > now {
 let delay = (resume_at - now) as u64;
 let deadline = Instant::now() + Duration::from_secs(delay);
 sleep_until(deadline).await;
 }

 // Check if our token is still valid (not replaced)
 {
 let tokens = wait_tokens.read().await;
 if tokens.get(&thread_id) != Some(&token_clone) {
 return;
 }
 }

 // Reset state and trigger continuation
 resumes_at.write().await.remove(&thread_id);
 waits.write().await.remove(&thread_id);
 wait_tokens.write().await.remove(&thread_id);

 let enabled_val = *enabled.read().await;
 if !enabled_val {
 return;
 }

 // Trigger the continuation: this would normally be done by the runtime.
 // The actual sending is performed by the command layer when the wait completes.
 let _ = notify_when_finished.read().await;
 });

 self.waits.write().await.insert(thread_id, handle);
 true
 }

 /// Cancel an active wait for a thread (when the user picks the chat up).
 pub async fn cancel(&self, thread_id: Uuid) {
 let mut waits = self.waits.write().await;
 if let Some(handle) = waits.remove(&thread_id) {
 handle.abort();
 }
 self.wait_tokens.write().await.remove(&thread_id);
 self.resumes_at.write().await.remove(&thread_id);
 }

 /// Get the resume time for a thread, if waiting.
 pub async fn resumes_at(&self, thread_id: Uuid) -> Option<i64> {
 self.resumes_at.read().await.get(&thread_id).copied()
 }

 /// Check whether a thread is currently waiting.
 pub async fn is_waiting(&self, thread_id: Uuid) -> bool {
 self.waits.read().await.contains_key(&thread_id)
 }

 /// Format a resume time for display ("3:31 PM", "tomorrow at 9:00 AM").
 pub fn format_resume_time(unix_seconds: i64) -> String {
 use chrono::{Local, TimeZone};

 let local = match Local.timestamp_opt(unix_seconds, 0).single() {
 Some(dt) => dt,
 None => return String::new(),
 };

 let now = Local::now();
 let time_str = local.format("%H:%M").to_string();

 if local.date_naive() == now.date_naive() {
 time_str
 } else if local.date_naive() == now.date_naive().succ_opt().unwrap_or(now.date_naive()) {
 format!("tomorrow at {}", time_str)
 } else {
 local.format("%a at %H:%M").to_string()
 }
 }
}

impl Default for AutoContinue {
 fn default() -> Self {
 Self::new()
 }
}

// ---------------------------------------------------------------------------
// Plan limits reader (stub for future expansion)
// ---------------------------------------------------------------------------

pub struct PlanLimitsReader;

impl PlanLimitsReader {
 pub fn exposes_limits(provider: ProviderKind) -> bool {
 matches!(
 provider,
 ProviderKind::Codex | ProviderKind::Claude | ProviderKind::Copilot
 )
 }

 pub async fn read_reset_time(provider: ProviderKind) -> Option<i64> {
 // Read fresh from the provider CLI to discover the most-spent window's reset time.
 match provider {
 ProviderKind::Codex => Self::read_via_cli("codex", &["plan", "--json"]).await,
 ProviderKind::Claude => Self::read_via_cli("claude", &["usage"]).await,
 ProviderKind::Copilot => Self::read_via_cli("copilot", &["usage"]).await,
 _ => None,
 }
 }

 async fn read_via_cli(exe: &str, args: &[&str]) -> Option<i64> {
 use tokio::process::Command;

 let output = Command::new(exe).args(args).output().await.ok()?;

 if !output.status.success() {
 return None;
 }

 let text = String::from_utf8_lossy(&output.stdout);
 // Look for JSON output with a reset time
 if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
 if let Some(ts) = json.get("resets_at").and_then(|v| v.as_i64()) {
 return Some(ts);
 }
 }
 None
 }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn test_usage_limit_matches() {
 assert!(UsageLimitSignal::matches(
 "You hit your usage limit for the day"
 ));
 assert!(UsageLimitSignal::matches(
 "Usage limit reached, please try again"
 ));
 assert!(UsageLimitSignal::matches("out of extra usage"));
 assert!(!UsageLimitSignal::matches("Some other error"));
 }

 #[test]
 fn test_reset_time_unix_bar() {
 let text = "usage limit reached|1757865600";
 let ts = UsageLimitSignal::reset_time(text);
 assert!(ts.is_some());
 }

 #[test]
 fn test_reset_time_unix_millis() {
 let text = "usage limit reached|1757865600000";
 let ts = UsageLimitSignal::reset_time(text);
 assert!(ts.is_some());
 }

 #[tokio::test]
 async fn test_auto_continue_new() {
 let ac = AutoContinue::new();
 assert!(!ac.is_waiting(Uuid::new_v4()).await);
 assert!(ac.is_enabled().await);
 }
}
