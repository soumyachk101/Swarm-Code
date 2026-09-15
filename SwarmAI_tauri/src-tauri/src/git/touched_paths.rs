//! Touched paths tracking for Git repositories.

use std::collections::HashSet;
use std::path::PathBuf;

/// A tracked file with its change status.
#[derive(Debug, Clone)]
pub struct TouchedFile {
 /// Absolute path to the file
 pub path: PathBuf,
 /// Change kind: M (modified), A (added), D (deleted), R (renamed)
 pub status: char,
}

impl TouchedFile {
 pub fn new(path: PathBuf, status: char) -> Self {
 Self { path, status }
 }
}

/// Collects and tracks touched (changed) file paths from Git operations.
#[derive(Debug, Default)]
pub struct TouchedPaths {
 files: HashSet<PathBuf>,
}

impl TouchedPaths {
 pub fn new() -> Self {
 Self::default()
 }

 /// Add a file to the tracked set.
 pub fn add(&mut self, path: PathBuf) {
 self.files.insert(path);
 }

 /// Remove a file from the tracked set.
 pub fn remove(&mut self, path: &PathBuf) {
 self.files.remove(path);
 }

 /// Check if a path is tracked.
 pub fn contains(&self, path: &PathBuf) -> bool {
 self.files.contains(path)
 }

 /// Get all tracked paths.
 pub fn all(&self) -> Vec<PathBuf> {
 self.files.iter().cloned().collect()
 }

 /// Get count of tracked paths.
 pub fn len(&self) -> usize {
 self.files.len()
 }

 /// Check if empty.
 pub fn is_empty(&self) -> bool {
 self.files.is_empty()
 }

 /// Clear all tracked paths.
 pub fn clear(&mut self) {
 self.files.clear();
 }
}

impl IntoIterator for TouchedPaths {
 type Item = PathBuf;
 type IntoIter = std::collections::hash_set::IntoIter<PathBuf>;

 fn into_iter(self) -> Self::IntoIter {
 self.files.into_iter()
 }
}
