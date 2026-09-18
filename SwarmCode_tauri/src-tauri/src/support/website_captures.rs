//! WebsiteCaptures - captures website screenshots.
//!
//! Mirrors the Swift `WebsiteCaptures` class: manages website screenshot
//! captures with metadata and caching.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// WebsiteCapture
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebsiteCapture {
 pub id: uuid::Uuid,
 pub url: String,
 pub title: String,
 pub file_path: PathBuf,
 pub width: u32,
 pub height: u32,
 pub captured_at: DateTime<Utc>,
 pub thumbnail_path: Option<PathBuf>,
 pub is_pinned: bool,
}

impl WebsiteCapture {
 pub fn new(url: impl Into<String>, file_path: PathBuf) -> Self {
 let url_str = url.into();
 Self {
 id: uuid::Uuid::new_v4(),
 url: url_str.clone(),
 title: Self::extract_title(&url_str),
 file_path,
 width: 1280,
 height: 800,
 captured_at: Utc::now(),
 thumbnail_path: None,
 is_pinned: false,
 }
 }

 /// Extract a display title from a URL.
 fn extract_title(url: &str) -> String {
 if let Ok(parsed) = url::Url::parse(url) {
 parsed.host_str().map(|h| h.to_string()).unwrap_or_else(|| url.to_string())
 } else {
 url.to_string()
 }
 }

 pub fn with_dimensions(mut self, width: u32, height: u32) -> Self {
 self.width = width;
 self.height = height;
 self
 }

 pub fn with_title(mut self, title: impl Into<String>) -> Self {
 self.title = title.into();
 self
 }

 pub fn with_pinned(mut self, pinned: bool) -> Self {
 self.is_pinned = pinned;
 self
 }

 /// Whether this capture is stale (older than 30 days).
 pub fn is_stale(&self) -> bool {
 self.captured_at.timestamp() < (Utc::now().timestamp() - 30 * 86400)
 }
}

// ---------------------------------------------------------------------------
// CaptureOptions
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct CaptureOptions {
 pub width: u32,
 pub height: u32,
 pub full_page: bool,
 pub delay_ms: u32,
 pub user_agent: Option<String>,
 pub viewport_width: Option<u32>,
 pub viewport_height: Option<u32>,
}

impl Default for CaptureOptions {
 fn default() -> Self {
 Self {
 width: 1280,
 height: 800,
 full_page: false,
 delay_ms: 500,
 user_agent: None,
 viewport_width: None,
 viewport_height: None,
 }
 }
}

// ---------------------------------------------------------------------------
// WebsiteCaptures - manager
// ---------------------------------------------------------------------------

pub struct WebsiteCaptures {
 captures: RwLock<Vec<WebsiteCapture>>,
 captures_dir: PathBuf,
 thumbnails_dir: PathBuf,
}

impl WebsiteCaptures {
 /// Create a new WebsiteCaptures manager rooted at the given directory.
 pub fn new(base_dir: PathBuf) -> Result<Self, String> {
 let captures_dir = base_dir.join("website_captures");
 let thumbnails_dir = base_dir.join("website_thumbnails");

 let _ = std::fs::create_dir_all(&captures_dir);
 let _ = std::fs::create_dir_all(&thumbnails_dir);

 Ok(Self {
 captures: RwLock::new(Vec::new()),
 captures_dir,
 thumbnails_dir,
 })
 }

 /// Load captures from disk.
 pub async fn load(&self) -> Result<usize, String> {
 let index_path = self.captures_dir.join("index.json");
 if !index_path.exists() {
 return Ok(0);
 }

 let data = std::fs::read_to_string(&index_path)
 .map_err(|e| e.to_string())?;

 let captures: Vec<WebsiteCapture> = serde_json::from_str(&data)
 .map_err(|e| e.to_string())?;

 let count = captures.len();
 *self.captures.write().await = captures;
 Ok(count)
 }

 /// Persist captures index to disk.
 pub async fn save(&self) -> Result<(), String> {
 let captures = self.captures.read().await;
 let json = serde_json::to_string_pretty(&*captures)
 .map_err(|e| e.to_string())?;
 let index_path = self.captures_dir.join("index.json");
 std::fs::write(&index_path, json)
 .map_err(|e| e.to_string())
 }

 /// Add a new capture.
 pub async fn add(&self, capture: WebsiteCapture) {
 self.captures.write().await.push(capture);
 let _ = self.save().await;
 }

 /// Get a capture by id.
 pub async fn get(&self, id: uuid::Uuid) -> Option<WebsiteCapture> {
 self.captures
 .read()
 .await
 .iter()
 .find(|c| c.id == id)
 .cloned()
 }

 /// Get a capture by URL.
 pub async fn get_by_url(&self, url: &str) -> Option<WebsiteCapture> {
 self.captures
 .read()
 .await
 .iter()
 .find(|c| c.url == url)
 .cloned()
 }

 /// Remove a capture by id.
 pub async fn remove(&self, id: uuid::Uuid) -> bool {
 let mut captures = self.captures.write().await;
 let before = captures.len();
 captures.retain(|c| c.id != id);
 let removed = captures.len() != before;
 if removed {
 let _ = self.save().await;
 }
 removed
 }

 /// All captures.
 pub async fn all(&self) -> Vec<WebsiteCapture> {
 self.captures.read().await.clone()
 }

 /// Pinned captures.
 pub async fn pinned(&self) -> Vec<WebsiteCapture> {
 self.captures
 .read()
 .await
 .iter()
 .filter(|c| c.is_pinned)
 .cloned()
 .collect()
 }

 /// Toggle pinned state.
 pub async fn toggle_pinned(&self, id: uuid::Uuid) -> Option<bool> {
 let mut captures = self.captures.write().await;
 if let Some(c) = captures.iter_mut().find(|c| c.id == id) {
 c.is_pinned = !c.is_pinned;
 let new_state = c.is_pinned;
 drop(captures);
 let _ = self.save().await;
 Some(new_state)
 } else {
 None
 }
 }

 /// Remove stale captures (older than 30 days and not pinned).
 pub async fn evict_stale(&self) -> usize {
 let mut captures = self.captures.write().await;
 let before = captures.len();
 captures.retain(|c| c.is_pinned || !c.is_stale());
 let removed = before - captures.len();
 if removed > 0 {
 let _ = self.save().await;
 }
 removed
 }

 /// Capture a screenshot of a website.
 ///
 /// Uses `playwright` CLI if available, otherwise falls back to a placeholder.
 pub async fn capture(&self, url: &str, options: CaptureOptions) -> Result<WebsiteCapture, String> {
 let file_name = format!("{}.png", uuid::Uuid::new_v4());
 let file_path = self.captures_dir.join(&file_name);

 // Attempt playwright capture
 let result = self::capture_with_playwright(url, &file_path, &options).await;

 match result {
 Ok(_) => {
 let capture = WebsiteCapture::new(url, file_path)
 .with_dimensions(options.width, options.height);
 self.add(capture.clone()).await;
 Ok(capture)
 }
 Err(e) => {
 // If playwright isn't available, create a placeholder capture
 tracing::warn!("playwright capture failed: {}", e);
 let capture = WebsiteCapture::new(url, file_path)
 .with_dimensions(options.width, options.height);
 self.add(capture.clone()).await;
 Err(e)
 }
 }
 }

 /// Capture path for a specific URL.
 pub async fn capture_path(&self, url: &str) -> Option<PathBuf> {
 self.get_by_url(url).await.map(|c| c.file_path)
 }

 /// Generate a thumbnail for a capture.
 pub async fn generate_thumbnail(
 &self,
 capture_id: uuid::Uuid,
 thumb_width: u32,
 thumb_height: u32,
 ) -> Result<PathBuf, String> {
 let captures = self.captures.read().await;
 let capture = captures.iter().find(|c| c.id == capture_id)
 .ok_or_else(|| "capture not found".to_string())?;

 let thumb_path = self.thumbnails_dir.join(format!("{}.png", capture_id));

 // Use image crate to generate thumbnail
 if capture.file_path.exists() {
 let img = image::open(&capture.file_path)
 .map_err(|e| e.to_string())?;

 let thumb = img.resize(thumb_width, thumb_height, image::imageops::FilterType::Lanczos3);
 thumb.save(&thumb_path)
 .map_err(|e| e.to_string())?;

 Ok(thumb_path)
 } else {
 Err("source image not found".to_string())
 }
 }

 /// The root directory for captures.
 pub fn captures_dir(&self) -> &Path {
 &self.captures_dir
 }

 /// The root directory for thumbnails.
 pub fn thumbnails_dir(&self) -> &Path {
 &self.thumbnails_dir
 }
}

// ---------------------------------------------------------------------------
// Capture with Playwright CLI
// ---------------------------------------------------------------------------

async fn capture_with_playwright(
 url: &str,
 output_path: &Path,
 options: &CaptureOptions,
) -> Result<(), String> {
 use tokio::process::Command;

 let mut args = vec![
 "screenshot".into(),
 "--viewport-size".into(),
 format!("{}x{}", options.width, options.height),
 "--browser=chromium".into(),
 "--output".into(),
 output_path.to_string_lossy().to_string(),
 url.to_string(),
 ];

 if options.full_page {
 args.push("--full-page".into());
 }

 let output = Command::new("playwright")
 .args(&args)
 .output()
 .await
 .map_err(|e| format!("playwright not available: {}", e))?;

 if !output.status.success() {
 let stderr = String::from_utf8_lossy(&output.stderr);
 return Err(format!("playwright failed: {}", stderr));
 }

 Ok(())
}

// ---------------------------------------------------------------------------
// Shared handle
// ---------------------------------------------------------------------------

pub type SharedWebsiteCaptures = Arc<WebsiteCaptures>;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
 use super::*;

 #[tokio::test]
 async fn test_capture_lifecycle() {
 let dir = std::env::temp_dir().join("swarmcode_test_captures");
 let captures = WebsiteCaptures::new(dir.clone()).unwrap();
 captures.load().await.unwrap();

 let capture = WebsiteCapture::new("https://example.com", dir.join("test.png"));
 captures.add(capture.clone()).await;

 let found = captures.get(capture.id).await;
 assert!(found.is_some());

 let removed = captures.remove(capture.id).await;
 assert!(removed);

 let _ = std::fs::remove_dir_all(&dir);
 }
}
