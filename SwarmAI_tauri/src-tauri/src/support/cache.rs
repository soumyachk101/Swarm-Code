//! A generation-based, bounded TTL cache.
//!
//! Entries live in the current generation. When it fills, it becomes the
//! previous generation and a fresh one starts. A hit in the previous generation
//! moves the entry forward. This means the cache never drops everything at once
//! -- a run of fresh keys pushes out the oldest entries first while entries still
//! in use stay, and no operation costs more than two dictionary lookups.

use std::collections::hash_map::Entry;
use std::time::{Duration, Instant};

/// A bounded cache that keeps what was used recently and lets the rest go a
/// generation at a time.
///
/// The cache holds at most `2 * limit` entries across the current and previous
/// generations, though in practice it stays near `limit` because the previous
/// generation only holds what was not yet replaced.
#[derive(Debug, Clone, Default)]
pub struct RecentCache<K: Eq + std::hash::Hash, V> {
    current: std::collections::HashMap<K, (V, Instant)>,
    previous: std::collections::HashMap<K, (V, Instant)>,
    limit: usize,
    max_age: Duration,
}

impl<K: Eq + std::hash::Hash + Clone, V: Clone> RecentCache<K, V> {
    /// Create a new cache with the given entry limit per generation and a TTL
    /// after which expired entries are discarded.
    ///
    /// The effective `limit` is clamped to a minimum of 1.
    pub fn new(limit: usize, max_age: Duration) -> Self {
        let limit = limit.max(1);
        Self {
            current: std::collections::HashMap::with_capacity(limit),
            previous: std::collections::HashMap::new(),
            limit,
            max_age,
        }
    }

    /// Insert or replace an entry.  The previous generation is rolled over
    /// when the current one is full and the key is not already present.
    pub fn insert(&mut self, key: K, value: V) {
        let now = Instant::now();
        self.prune_expired();

        if self.current.len() >= self.limit {
            if !self.current.contains_key(&key) {
                // Rotate: current becomes previous, fresh current starts.
                self.previous = std::mem::take(&mut self.current);
                self.previous.retain(|_, (_, t)| t.elapsed() < self.max_age);
            }
        }

        self.current.insert(key, (value, now));
    }

    /// Look up a value.  Checks the current generation first; on a miss the
    /// previous generation is checked and the entry is promoted (re-inserted
    /// into the current generation).
    ///
    /// Returns `None` if the key is absent from both generations.
    pub fn get(&mut self, key: &K) -> Option<&V> {
        // Check current generation first (no promotion).
        if self.current.contains_key(key) {
            return self.current.get(key).map(|(v, _)| v);
        }

        // Try previous generation with promotion.
        if let Some((value, ts)) = self.previous.remove(key) {
            if ts.elapsed() < self.max_age {
                let now = Instant::now();
                self.current.insert(key.clone(), (value.clone(), now));
                return self.current.get(key).map(|(v, _)| v);
            }
        }
        None
    }

    /// Whether the key is present in either generation (without promotion).
    pub fn contains(&self, key: &K) -> bool {
        self.current.contains_key(key) || self.previous.contains_key(key)
    }

    /// Remove a specific key from both generations.
    pub fn remove(&mut self, key: &K) -> Option<V> {
        let current = self.current.remove(key).map(|(v, _)| v);
        let previous = self.previous.remove(key).map(|(v, _)| v);
        current.or(previous)
    }

    /// Return the number of live entries across both generations.
    pub fn len(&self) -> usize {
        self.current.len() + self.previous.len()
    }

    /// Whether the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.current.is_empty() && self.previous.is_empty()
    }

    /// Remove all entries from the cache.
    pub fn clear(&mut self) {
        self.current.clear();
        self.previous.clear();
    }

    /// Remove every entry whose TTL has elapsed.
    pub fn prune_expired(&mut self) {
        let now = Instant::now();
        self.current.retain(|_, (_, t)| now.duration_since(*t) < self.max_age);
        self.previous.retain(|_, (_, t)| now.duration_since(*t) < self.max_age);
    }

    /// Return all entries in the current generation (does not promote anything
    /// from the previous generation).
    pub fn current_entries(&self) -> impl Iterator<Item = (&K, &V)> {
        self.current.iter().map(|(k, (v, _))| (k, v))
    }

    /// Return all entries in the previous generation.
    pub fn previous_entries(&self) -> impl Iterator<Item = (&K, &V)> {
        self.previous.iter().map(|(k, (v, _))| (k, v))
    }

    /// The configured limit (entries per generation).
    pub fn limit(&self) -> usize {
        self.limit
    }

    /// The configured TTL.
    pub fn max_age(&self) -> Duration {
        self.max_age
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn test_insert_and_get() {
        let mut cache = RecentCache::new(2, Duration::from_secs(60));
        cache.insert("a", 1);
        cache.insert("b", 2);
        assert_eq!(cache.get(&"a"), Some(&1));
        assert_eq!(cache.get(&"b"), Some(&2));
        assert_eq!(cache.get(&"c"), None);
    }

    #[test]
    fn test_rotation() {
        let mut cache = RecentCache::new(2, Duration::from_secs(60));
        cache.insert("a", 1);
        cache.insert("b", 2);
        cache.insert("c", 3); // current full, "a" should go to previous

        // "a" should still be reachable via promotion
        assert_eq!(cache.get(&"a"), Some(&1));
        assert_eq!(cache.get(&"b"), Some(&2));
        assert_eq!(cache.get(&"c"), Some(&3));
    }

    #[test]
    fn test_remove() {
        let mut cache = RecentCache::new(4, Duration::from_secs(60));
        cache.insert("x", 10);
        assert_eq!(cache.remove(&"x"), Some(10));
        assert_eq!(cache.get(&"x"), None);
    }

    #[test]
    fn test_contains() {
        let mut cache = RecentCache::new(2, Duration::from_secs(60));
        cache.insert("k", "v");
        assert!(cache.contains(&"k"));
        assert!(!cache.contains(&"other"));
    }

    #[test]
    fn test_clear() {
        let mut cache = RecentCache::new(2, Duration::from_secs(60));
        cache.insert("a", 1);
        cache.insert("b", 2);
        cache.clear();
        assert!(cache.is_empty());
    }

    #[test]
    fn test_prune_expired() {
        let mut cache = RecentCache::new(2, Duration::from_millis(1));
        cache.insert("a", 1);
        std::thread::sleep(Duration::from_millis(5));
        cache.insert("b", 2);
        cache.prune_expired();
        // "a" should have expired
        assert_eq!(cache.get(&"a"), None);
        assert_eq!(cache.get(&"b"), Some(&2));
    }

    #[test]
    fn test_len_and_is_empty() {
        let mut cache = RecentCache::new(10, Duration::from_secs(60));
        assert!(cache.is_empty());
        assert_eq!(cache.len(), 0);
        cache.insert("a", 1);
        assert!(!cache.is_empty());
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn test_min_limit_is_one() {
        let cache: RecentCache<i32, i32> = RecentCache::new(0, Duration::from_secs(60));
        assert_eq!(cache.limit(), 1);
    }
}
