use std::time::{Duration, Instant};
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct ThumbnailCache {
 pub cache: Arc<RwLock<HashMap<String, ThumbnailEntry>>>,
 pub max_size: usize,
 pub max_age: Duration,
}

#[derive(Debug, Clone)]
pub struct ThumbnailEntry {
 pub path: PathBuf,
 pub data: Vec<u8>,
 pub width: u32,
 pub height: u32,
 pub created_at: Instant,
}

impl ThumbnailCache {
 pub fn new(max_size: usize, max_age: Duration) -> Self {
 Self {
 cache: Arc::new(RwLock::new(HashMap::new())),
 max_size,
 max_age,
 }
 }

 pub async fn get(&self, path: &str) -> Option<ThumbnailEntry> {
 let cache = self.cache.read().await;
 cache.get(path).cloned()
 }

 pub async fn put(&self, path: String, entry: ThumbnailEntry) {
 let mut cache = self.cache.write().await;
 cache.insert(path, entry);
 }

 pub async fn evict_stale(&self) {
 let mut cache = self.cache.write().await;
 cache.retain(|_, entry| entry.created_at.elapsed() < self.max_age);
 }
}
