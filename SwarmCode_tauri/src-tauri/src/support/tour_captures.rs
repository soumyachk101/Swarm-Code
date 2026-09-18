//! TourCaptures - manages onboarding/tour screenshots.
//!
//! Mirrors the Swift `TourCaptures` and `TourCaptures+Hydra` classes:
//! manages onboarding step screenshots, including hydra-specific steps.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// TourStep
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TourStep {
 /// A static screenshot image.
 Image {
 path: PathBuf,
 caption: String,
 },
 /// A video recording.
 Video {
 path: PathBuf,
 thumbnail: Option<PathBuf>,
 duration_seconds: u32,
 caption: String,
 },
 /// An interactive demo.
 Interactive {
 id: String,
 title: String,
 description: String,
 },
}

impl TourStep {
 pub fn image(path: impl Into<PathBuf>, caption: impl Into<String>) -> Self {
 Self::Image {
 path: path.into(),
 caption: caption.into(),
 }
 }

 pub fn video(path: impl Into<PathBuf>, caption: impl Into<String>) -> Self {
 Self::Video {
 path: path.into(),
 thumbnail: None,
 duration_seconds: 0,
 caption: caption.into(),
 }
 }

 pub fn interactive(id: impl Into<String>, title: impl Into<String>, description: impl Into<String>) -> Self {
 Self::Interactive {
 id: id.into(),
 title: title.into(),
 description: description.into(),
 }
 }

 pub fn caption(&self) -> &str {
 match self {
 Self::Image { caption, .. } => caption,
 Self::Video { caption, .. } => caption,
 Self::Interactive { description, .. } => description,
 }
 }
}

// ---------------------------------------------------------------------------
// Tour
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tour {
 pub id: String,
 pub name: String,
 pub description: String,
 pub steps: Vec<TourStep>,
 pub version: String,
 pub created_at: DateTime<Utc>,
 pub updated_at: DateTime<Utc>,
 pub is_hydra_tour: bool,
 pub is_completed: bool,
}

impl Tour {
 pub fn new(
 id: impl Into<String>,
 name: impl Into<String>,
 description: impl Into<String>,
 steps: Vec<TourStep>,
 ) -> Self {
 let now = Utc::now();
 Self {
 id: id.into(),
 name: name.into(),
 description: description.into(),
 steps,
 version: "1.0".to_string(),
 created_at: now,
 updated_at: now,
 is_hydra_tour: false,
 is_completed: false,
 }
 }

 pub fn with_hydra(mut self) -> Self {
 self.is_hydra_tour = true;
 self
 }

 pub fn mark_completed(&mut self) {
 self.is_completed = true;
 self.updated_at = Utc::now();
 }

 pub fn add_step(&mut self, step: TourStep) {
 self.steps.push(step);
 self.updated_at = Utc::now();
 }

 pub fn step_count(&self) -> usize {
 self.steps.len()
 }

 pub fn current_step(&self) -> Option<&TourStep> {
 self.steps.first()
 }
}

// ---------------------------------------------------------------------------
// TourCaptures - manager for tours
// ---------------------------------------------------------------------------

pub struct TourCaptures {
 tours: RwLock<HashMap<String, Tour>>,
 tours_dir: PathBuf,
 user_progress: RwLock<HashMap<String, TourProgress>>,
}

impl TourCaptures {
 /// Create a new TourCaptures manager.
 pub fn new(tours_dir: PathBuf) -> Self {
 let _ = std::fs::create_dir_all(&tours_dir);
 Self {
 tours: RwLock::new(HashMap::new()),
 tours_dir,
 user_progress: RwLock::new(HashMap::new()),
 }
 }

 /// Load tours from disk.
 pub async fn load(&self) -> Result<usize, String> {
 let index_path = self.tours_dir.join("tours.json");
 if !index_path.exists() {
 return Ok(0);
 }

 let data = std::fs::read_to_string(&index_path)
 .map_err(|e| e.to_string())?;

 let tours: HashMap<String, Tour> = serde_json::from_str(&data)
 .map_err(|e| e.to_string())?;

 let count = tours.len();
 *self.tours.write().await = tours;
 Ok(count)
 }

 /// Persist tours to disk.
 pub async fn save(&self) -> Result<(), String> {
 let tours = self.tours.read().await;
 let json = serde_json::to_string_pretty(&*tours)
 .map_err(|e| e.to_string())?;
 let index_path = self.tours_dir.join("tours.json");
 std::fs::write(&index_path, json)
 .map_err(|e| e.to_string())
 }

 /// Register a new tour.
 pub async fn register(&self, tour: Tour) {
 self.tours.write().await.insert(tour.id.clone(), tour);
 let _ = self.save().await;
 }

 /// Get a tour by id.
 pub async fn get(&self, id: &str) -> Option<Tour> {
 self.tours.read().await.get(id).cloned()
 }

 /// All tours.
 pub async fn all(&self) -> Vec<Tour> {
 self.tours.read().await.values().cloned().collect()
 }

 /// Hydra-specific tours only.
 pub async fn hydra_tours(&self) -> Vec<Tour> {
 self.tours
 .read()
 .await
 .values()
 .filter(|t| t.is_hydra_tour)
 .cloned()
 .collect()
 }

 /// Remove a tour by id.
 pub async fn remove(&self, id: &str) -> bool {
 let mut tours = self.tours.write().await;
 let removed = tours.remove(id).is_some();
 if removed {
 let _ = self.save().await;
 }
 removed
 }

 /// Record user progress for a tour step.
 pub async fn record_step(&self, tour_id: &str, step_index: usize) {
 let mut progress = self.user_progress.write().await;
 progress.entry(tour_id.to_string())
 .or_insert_with(|| TourProgress {
 tour_id: tour_id.to_string(),
 current_step: 0,
 is_completed: false,
 })
 .current_step = step_index;
 }

 /// Mark a tour as completed.
 pub async fn mark_completed(&self, tour_id: &str) {
 if let Some(tour) = self.tours.write().await.get_mut(tour_id) {
 tour.mark_completed();
 let _ = self.save().await;
 }

 let mut progress = self.user_progress.write().await;
 progress.entry(tour_id.to_string())
 .or_insert_with(|| TourProgress {
 tour_id: tour_id.to_string(),
 current_step: 0,
 is_completed: false,
 })
 .is_completed = true;
 }

 /// Check if a tour has been completed.
 pub async fn is_completed(&self, tour_id: &str) -> bool {
 self.user_progress
 .read()
 .await
 .get(tour_id)
 .map(|p| p.is_completed)
 .unwrap_or(false)
 }

 /// Get user progress for a tour.
 pub async fn progress(&self, tour_id: &str) -> Option<TourProgress> {
 self.user_progress.read().await.get(tour_id).cloned()
 }
}

// ---------------------------------------------------------------------------
// TourProgress
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TourProgress {
 pub tour_id: String,
 pub current_step: usize,
 pub is_completed: bool,
}

// ---------------------------------------------------------------------------
// Built-in tours
// ---------------------------------------------------------------------------

impl TourCaptures {
 /// Register the default onboarding tours.
 pub async fn register_defaults(&self) {
 let welcome_tour = Tour::new(
 "welcome",
 "Welcome to Swarm Code",
 "A quick introduction to Swarm Code's core concepts.",
 vec![
 TourStep::image("", "The Swarm Code interface"),
 TourStep::image("", "Creating your first thread"),
 TourStep::interactive("try-chat", "Try a message", "Send a message to an AI assistant"),
 ],
 );

 let hydra_tour = Tour::new(
 "hydra-intro",
 "Multi-Model Consensus",
 "How Hydra runs multiple AI models and merges results.",
 vec![
 TourStep::image("", "Hydra overview"),
 TourStep::image("", "Comparing model outputs"),
 TourStep::interactive("try-hydra", "Try Hydra", "Launch a Hydra run with two models"),
 ],
 )
 .with_hydra();

 self.register(welcome_tour).await;
 self.register(hydra_tour).await;
 }
}

// ---------------------------------------------------------------------------
// Shared handle
// ---------------------------------------------------------------------------

pub type SharedTourCaptures = Arc<TourCaptures>;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
 use super::*;

 #[tokio::test]
 async fn test_tour_lifecycle() {
 let dir = std::env::temp_dir().join("swarmcode_test_tours");
 let manager = TourCaptures::new(dir.clone());

 let mut tour = Tour::new(
 "test",
 "Test Tour",
 "A test tour.",
 vec![
 TourStep::image("img1.png", "Step 1"),
 TourStep::image("img2.png", "Step 2"),
 ],
 );

 manager.register(tour.clone()).await;
 let found = manager.get("test").await;
 assert!(found.is_some());

 manager.mark_completed("test").await;
 assert!(manager.is_completed("test").await);

 manager.record_step("test", 1).await;
 let progress = manager.progress("test").await;
 assert_eq!(progress.map(|p| p.current_step), Some(1));

 let _ = std::fs::remove_dir_all(&dir);
 }
}
