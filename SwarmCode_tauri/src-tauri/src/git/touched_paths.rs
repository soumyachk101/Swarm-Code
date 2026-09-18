//! Touched paths tracking for Git repositories.
//!
//! Matches the files an agent reported editing against the files a diff
//! contains, normalising paths to repository-relative form and providing
//! filtering and grouping utilities.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// TouchedFile
// ---------------------------------------------------------------------------

/// Change kind for a TouchedFile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffChangeType {
    Added,
    Modified,
    Deleted,
    Renamed,
    Copied,
    Unmodified,
}

impl DiffChangeType {
    pub fn as_char(self) -> char {
        match self {
            DiffChangeType::Added => 'A',
            DiffChangeType::Modified => 'M',
            DiffChangeType::Deleted => 'D',
            DiffChangeType::Renamed => 'R',
            DiffChangeType::Copied => 'C',
            DiffChangeType::Unmodified => ' ',
        }
    }

    pub fn from_char(c: char) -> Self {
        match c {
            'A' => DiffChangeType::Added,
            'M' => DiffChangeType::Modified,
            'D' => DiffChangeType::Deleted,
            'R' => DiffChangeType::Renamed,
            'C' => DiffChangeType::Copied,
            _ => DiffChangeType::Unmodified,
        }
    }
}

/// A tracked file with its change status.
#[derive(Debug, Clone)]
pub struct TouchedFile {
    /// Absolute path to the file.
    pub path: PathBuf,
    /// Change kind: M (modified), A (added), D (deleted), R (renamed), etc.
    pub status: char,
    /// Optional old path when the file was renamed or copied.
    pub old_path: Option<PathBuf>,
    /// Parsed change type.
    pub change_type: DiffChangeType,
}

impl TouchedFile {
    pub fn new(path: PathBuf, status: char) -> Self {
        Self {
            path,
            status,
            old_path: None,
            change_type: DiffChangeType::from_char(status),
        }
    }

    pub fn with_old_path(mut self, old_path: PathBuf) -> Self {
        self.old_path = Some(old_path);
        self
    }

    /// The file extension, lowercased, or None.
    pub fn extension(&self) -> Option<String> {
        self.path
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.to_ascii_lowercase())
    }

    /// The file stem (name without extension).
    pub fn stem(&self) -> Option<String> {
        self.path
            .file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.to_string())
    }

    /// The file name.
    pub fn file_name(&self) -> Option<String> {
        self.path.file_name().and_then(|s| s.to_str()).map(|s| s.to_string())
    }

    /// Whether the change is a modification (not add/delete/rename).
    pub fn is_modified(&self) -> bool {
        self.status == 'M'
    }

    /// Whether the file was added.
    pub fn is_added(&self) -> bool {
        self.status == 'A'
    }

    /// Whether the file was deleted.
    pub fn is_deleted(&self) -> bool {
        self.status == 'D'
    }

    /// Whether the file was renamed.
    pub fn is_renamed(&self) -> bool {
        self.status == 'R'
    }
}

// ---------------------------------------------------------------------------
// TouchedPaths
// ---------------------------------------------------------------------------

/// Collects and tracks touched (changed) file paths from Git operations.
///
/// Provides methods to normalise paths, filter by extension, and group
/// by directory.
#[derive(Debug, Default)]
pub struct TouchedPaths {
    files: HashSet<PathBuf>,
    touched_set: HashSet<String>,
}

impl TouchedPaths {
    pub fn new() -> Self {
        Self::default()
    }

    /// Create a TouchedPaths from a set of path strings.
    pub fn from_paths(paths: impl IntoIterator<Item = String>) -> Self {
        let mut tp = Self::new();
        for path in paths {
            tp.add_path(path);
        }
        tp
    }

    /// Create from a diff's changed paths.
    pub fn from_diff_entries(entries: &[crate::git::DiffEntry]) -> Self {
        let mut tp = Self::new();
        for entry in entries {
            tp.add_path(entry.path.clone());
            if let Some(ref old) = entry.old_path {
                tp.add_path(old.clone());
            }
        }
        tp
    }

    // MARK: - Add / Remove

    /// Add a file path (absolute or relative).
    pub fn add_path(&mut self, path: impl Into<PathBuf>) {
        let path = path.into();
        let normalised = Self::normalize_path(&path);
        self.files.insert(path);
        self.touched_set.insert(normalised);
    }

    /// Add a path string.
    pub fn add(&mut self, path: PathBuf) {
        self.add_path(path);
    }

    /// Remove a file from the tracked set.
    pub fn remove(&mut self, path: &Path) {
        if let Some(normalised) = Self::relative(path.to_string_lossy().as_ref(), "/") {
            self.touched_set.remove(&normalised);
        }
        self.files.remove(path);
    }

    // MARK: - Query

    /// Whether a path is tracked.
    pub fn contains_path(&self, path: &Path) -> bool {
        let normalised = Self::normalize_path(path);
        self.touched_set.contains(&normalised)
    }

    /// Whether a path string is tracked.
    pub fn contains(&self, path: &str) -> bool {
        let normalised = Self::normalize_path(&PathBuf::from(path));
        self.touched_set.contains(&normalised)
    }

    /// Get all tracked absolute paths.
    pub fn all_paths(&self) -> Vec<PathBuf> {
        self.files.iter().cloned().collect()
    }

    /// Get all tracked repository-relative paths.
    pub fn all_relative(&self) -> Vec<String> {
        self.touched_set.iter().cloned().collect()
    }

    /// Get count of tracked paths.
    pub fn len(&self) -> usize {
        self.touched_set.len()
    }

    /// Check if empty.
    pub fn is_empty(&self) -> bool {
        self.touched_set.is_empty()
    }

    /// Clear all tracked paths.
    pub fn clear(&mut self) {
        self.files.clear();
        self.touched_set.clear();
    }

    // MARK: - Filtering

    /// Return only files with the given extension (case-insensitive, without dot).
    pub fn filter_by_extension(&self, ext: &str) -> Vec<&PathBuf> {
        self.files
            .iter()
            .filter(|p| {
                p.extension()
                    .and_then(|e| e.to_str())
                    .map(|e| e.eq_ignore_ascii_case(ext))
                    .unwrap_or(false)
            })
            .collect()
    }

    /// Return files that match any of the given extensions.
    pub fn filter_by_extensions(&self, extensions: &[&str]) -> Vec<&PathBuf> {
        self.files
            .iter()
            .filter(|p| {
                if let Some(ext) = p.extension().and_then(|e| e.to_str()) {
                    extensions.iter().any(|&allowed| ext.eq_ignore_ascii_case(allowed))
                } else {
                    false
                }
            })
            .collect()
    }

    /// Return files that are NOT of the given extension.
    pub fn exclude_extension(&self, ext: &str) -> Vec<&PathBuf> {
        self.files
            .iter()
            .filter(|p| {
                if let Some(e) = p.extension().and_then(|e| e.to_str()) {
                    !e.eq_ignore_ascii_case(ext)
                } else {
                    true
                }
            })
            .collect()
    }

    /// Return only files that are source code.
    pub fn source_files(&self) -> Vec<&PathBuf> {
        self.filter_by_extensions(&["rs", "swift", "py", "js", "ts", "go", "java", "c", "cpp", "h", "rb", "php"])
    }

    /// Return only image files.
    pub fn image_files(&self) -> Vec<&PathBuf> {
        self.filter_by_extensions(&["png", "jpg", "jpeg", "gif", "svg", "webp", "ico"])
    }

    // MARK: - Grouping

    /// Group the tracked paths by their immediate parent directory.
    ///
    /// Returns a map of directory name (or empty string for root) to the list
    /// of file names in that directory.
    pub fn group_by_directory(&self) -> HashMap<String, Vec<String>> {
        let mut groups: HashMap<String, Vec<String>> = HashMap::new();
        for path in &self.files {
            let dir = path
                .parent()
                .and_then(|p| p.to_str())
                .unwrap_or("")
                .to_string();
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            groups.entry(dir).or_default().push(name);
        }
        groups
    }

    /// Group by the top-level directory (first component of the path).
    pub fn group_by_top_level_directory(&self) -> HashMap<String, usize> {
        let mut counts: HashMap<String, usize> = HashMap::new();
        for path in &self.files {
            let top = path
                .components()
                .nth(1)
                .and_then(|c| c.as_os_str().to_str())
                .unwrap_or("(root)");
            *counts.entry(top.to_string()).or_default() += 1;
        }
        counts
    }

    // MARK: - Matching

    /// The repository-relative form of a path, whether absolute or relative.
    pub fn normalize_path(path: &Path) -> String {
        let s = path.to_string_lossy();
        // Strip leading ./ and / prefixes that make the path absolute.
        let s = s.strip_prefix("./").unwrap_or(&s);
        let s = s.strip_prefix('/').unwrap_or(s);
        s.to_string()
    }

    /// The repository-relative form of a path, or None when the path is no
    /// part of the checkout: another folder on the machine, a climb out of
    /// the root, or a URL.
    pub fn relative(path: &str, root: &str) -> Option<String> {
        let path = path.trim();
        if path.is_empty() || path.contains("://") {
            return None;
        }

        let root = if root.ends_with('/') {
            root.to_string()
        } else {
            format!("{}/", root)
        };

        // Expand tilde.
        let path = if path.starts_with('~') {
            path.replacen('~', std::env::var("HOME").as_deref().unwrap_or(""), 1)
        } else {
            path.to_string()
        };

        let absolute = if path.starts_with('/') {
            path
        } else {
            format!("{}{}", root.trim_end_matches('/'), "/", path)
        };

        // Normalise the path (remove .., ., duplicate slashes).
        let normalised = match Path::new(&absolute).canonicalize() {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(_) => absolute,
        };

        if normalised.starts_with(&root) {
            let rel = normalised.strip_prefix(&root).unwrap_or(&normalised);
            let rel = rel.strip_prefix('/').unwrap_or(rel);
            if rel.is_empty() { None } else { Some(rel.to_string()) }
        } else {
            None
        }
    }

    /// Whether a diff file is one of the touched paths, allowing for a path
    /// reported relative to a subfolder.
    pub fn matches(file: &str, touched: &HashSet<String>) -> bool {
        let file = Self::normalize_path(&PathBuf::from(file));
        if touched.contains(&file) {
            return true;
        }
        for path in touched {
            // Match if the file ends with "/<touched>" or touched ends with "/<file>"
            if path.len() < file.len() {
                if file.ends_with(path) && file.as_bytes()[file.len() - path.len() - 1] == b'/' {
                    return true;
                }
            } else if file.len() < path.len() {
                if path.ends_with(&file) && path.as_bytes()[path.len() - file.len() - 1] == b'/' {
                    return true;
                }
            }
        }
        false
    }
}

impl IntoIterator for TouchedPaths {
    type Item = String;
    type IntoIter = std::collections::hash_set::IntoIter<String>;

    fn into_iter(self) -> Self::IntoIter {
        self.touched_set.into_iter()
    }
}

impl FromIterator<String> for TouchedPaths {
    fn from_iter<I: IntoIterator<Item = String>>(iter: I) -> Self {
        let mut tp = Self::new();
        for path in iter {
            tp.add_path(path);
        }
        tp
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_path() {
        assert_eq!(TouchedPaths::normalize_path(Path::new("./src/main.rs")), "src/main.rs");
        assert_eq!(TouchedPaths::normalize_path(Path::new("/home/user/src/main.rs")), "home/user/src/main.rs");
        assert_eq!(TouchedPaths::normalize_path(Path::new("src/main.rs")), "src/main.rs");
    }

    #[test]
    fn test_relative() {
        let root = "/home/user/project";
        assert_eq!(TouchedPaths::relative("src/main.rs", root), Some("src/main.rs".to_string()));
        assert_eq!(TouchedPaths::relative("/home/user/project/src/main.rs", root), Some("src/main.rs".to_string()));
        assert!(TouchedPaths::relative("https://example.com/file.rs", root).is_none());
        assert!(TouchedPaths::relative("", root).is_none());
    }

    #[test]
    fn test_add_and_contains() {
        let mut tp = TouchedPaths::new();
        tp.add_path("src/main.rs");
        tp.add_path("src/lib.rs");
        assert!(tp.contains("src/main.rs"));
        assert!(tp.contains("src/lib.rs"));
        assert!(!tp.contains("src/other.rs"));
        assert_eq!(tp.len(), 2);
    }

    #[test]
    fn test_remove() {
        let mut tp = TouchedPaths::new();
        tp.add_path("src/main.rs");
        tp.remove(Path::new("src/main.rs"));
        assert!(tp.is_empty());
    }

    #[test]
    fn test_clear() {
        let mut tp = TouchedPaths::new();
        tp.add_path("a.rs");
        tp.add_path("b.rs");
        tp.clear();
        assert!(tp.is_empty());
    }

    #[test]
    fn test_filter_by_extension() {
        let mut tp = TouchedPaths::new();
        tp.add_path("src/main.rs");
        tp.add_path("src/lib.rs");
        tp.add_path("README.md");
        let rust = tp.filter_by_extension("rs");
        assert_eq!(rust.len(), 2);
        let md = tp.filter_by_extension("md");
        assert_eq!(md.len(), 1);
    }

    #[test]
    fn test_group_by_directory() {
        let mut tp = TouchedPaths::new();
        tp.add_path("src/a.rs");
        tp.add_path("src/b.rs");
        tp.add_path("tests/c.rs");
        let groups = tp.group_by_directory();
        assert_eq!(groups.len(), 2);
        assert!(groups.contains_key("src"));
        assert!(groups.contains_key("tests"));
    }

    #[test]
    fn test_from_paths() {
        let tp = TouchedPaths::from_paths(vec!["a.rs".into(), "b.rs".into()]);
        assert_eq!(tp.len(), 2);
    }

    #[test]
    fn test_from_iterator() {
        let tp: TouchedPaths = ["a.rs", "b.rs", "c.rs"].iter().map(|s| s.to_string()).collect();
        assert_eq!(tp.len(), 3);
    }

    #[test]
    fn test_into_iterator() {
        let mut tp = TouchedPaths::new();
        tp.add_path("a.rs");
        tp.add_path("b.rs");
        let paths: Vec<String> = tp.into_iter().collect();
        assert_eq!(paths.len(), 2);
    }

    #[test]
    fn test_matches() {
        let mut touched: HashSet<String> = HashSet::new();
        touched.insert("src/main.rs".to_string());
        touched.insert("src/old_name.rs".to_string());
        assert!(TouchedPaths::matches("src/main.rs", &touched));
        assert!(!TouchedPaths::matches("src/other.rs", &touched));
    }

    #[test]
    fn test_image_files() {
        let mut tp = TouchedPaths::new();
        tp.add_path("img/logo.png");
        tp.add_path("src/main.rs");
        let images = tp.image_files();
        assert_eq!(images.len(), 1);
    }

    #[test]
    fn test_source_files() {
        let mut tp = TouchedPaths::new();
        tp.add_path("src/main.rs");
        tp.add_path("src/lib.py");
        tp.add_path("README.md");
        let sources = tp.source_files();
        assert_eq!(sources.len(), 2);
    }
}
