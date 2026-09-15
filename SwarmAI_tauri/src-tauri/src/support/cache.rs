use std::time::{Duration, Instant};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

pub struct RecentCache<T> {
 entries: Vec<(T, Instant)>,
 max_age: Duration,
}

impl<T> RecentCache<T> {
 pub fn new(max_age: Duration) -> Self {
 Self {
 entries: Vec::new(),
 max_age,
 }
 }

 pub fn insert(&mut self, item: T) {
 self.entries.retain(|(_, time)| time.elapsed() < self.max_age);
 self.entries.push((item, Instant::now()));
 }

 pub fn get_all(&self) -> Vec<&T> {
 self.entries.iter().filter(|(_, time)| time.elapsed() < self.max_age).map(|(item, _)| item).collect()
 }

 pub fn clear(&mut self) {
 self.entries.clear();
 }
}
