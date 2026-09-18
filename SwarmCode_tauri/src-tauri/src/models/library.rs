//! Library item model -- saved snippets, prompts, templates, or code samples
//! that the user collects and reuses.
//!
//! A LibraryItem is a first-class entity in Swarm Code's UI: it can be pinned,
//! tagged, categorised, and inserted into a chat.

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

/// A broad bucket for library items.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LibraryCategory {
    Prompt,
    Snippet,
    Template,
    Command,
    Context,
    Other,
}

impl Default for LibraryCategory {
    fn default() -> Self {
        LibraryCategory::Other
    }
}

impl LibraryCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            LibraryCategory::Prompt => "Prompt",
            LibraryCategory::Snippet => "Snippet",
            LibraryCategory::Template => "Template",
            LibraryCategory::Command => "Command",
            LibraryCategory::Context => "Context",
            LibraryCategory::Other => "Other",
        }
    }
}

// ---------------------------------------------------------------------------
// LibraryItem
// ---------------------------------------------------------------------------

/// A saved item in the user's library.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LibraryItem {
    pub id: Uuid,

    /// A short title shown in lists.
    pub title: String,

    /// The main text content of the item.
    pub body: String,

    /// Optional tags for filtering and grouping.
    pub tags: Vec<String>,

    /// When the item was first created.
    pub created_at: DateTime<Utc>,

    /// When the item was last modified.
    pub updated_at: DateTime<Utc>,

    /// Whether the item is pinned to the top of the list.
    pub pinned: bool,

    /// How many times the user has inserted or used this item.
    pub usage_count: u32,

    /// The broad category this item belongs to.
    pub category: LibraryCategory,
}

impl LibraryItem {
    /// Create a new library item with the given title and body.
    pub fn new(title: impl Into<String>, body: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            body: body.into(),
            tags: Vec::new(),
            created_at: now,
            updated_at: now,
            pinned: false,
            usage_count: 0,
            category: LibraryCategory::Other,
        }
    }

    /// Create a new item in a specific category.
    pub fn with_category(
        title: impl Into<String>,
        body: impl Into<String>,
        category: LibraryCategory,
    ) -> Self {
        let mut item = Self::new(title, body);
        item.category = category;
        item
    }

    /// Create with a specific UUID (for deserialization or deduplication).
    pub fn with_id(
        id: Uuid,
        title: impl Into<String>,
        body: impl Into<String>,
    ) -> Self {
        let mut item = Self::new(title, body);
        item.id = id;
        item
    }

    /// Update the body and refresh `updated_at`.
    pub fn set_body(&mut self, body: impl Into<String>) {
        self.body = body.into();
        self.updated_at = Utc::now();
    }

    /// Update the title and refresh `updated_at`.
    pub fn set_title(&mut self, title: impl Into<String>) {
        self.title = title.into();
        self.updated_at = Utc::now();
    }

    /// Toggle the pinned state and refresh `updated_at`.
    pub fn toggle_pinned(&mut self) {
        self.pinned = !self.pinned;
        self.updated_at = Utc::now();
    }

    /// Set the pinned state explicitly.
    pub fn set_pinned(&mut self, pinned: bool) {
        self.pinned = pinned;
        self.updated_at = Utc::now();
    }

    /// Add a tag (if not already present).
    pub fn add_tag(&mut self, tag: impl Into<String>) {
        let tag = tag.into().trim().to_string();
        if !tag.is_empty() && !self.tags.contains(&tag) {
            self.tags.push(tag);
            self.updated_at = Utc::now();
        }
    }

    /// Remove a tag.
    pub fn remove_tag(&mut self, tag: &str) {
        if self.tags.iter().any(|t| t == tag) {
            self.tags.retain(|t| t != tag);
            self.updated_at = Utc::now();
        }
    }

    /// Record a usage and refresh `updated_at`.
    pub fn record_usage(&mut self) {
        self.usage_count = self.usage_count.saturating_add(1);
        self.updated_at = Utc::now();
    }

    /// Set the category and refresh `updated_at`.
    pub fn set_category(&mut self, category: LibraryCategory) {
        self.category = category;
        self.updated_at = Utc::now();
    }

    /// A short summary of the body text -- the first non-empty line, up to
    /// 80 characters.
    pub fn preview(&self) -> String {
        let line = self
            .body
            .lines()
            .map(|l| l.trim())
            .find(|l| !l.is_empty())
            .unwrap_or("");
        if line.chars().count() > 80 {
            line.chars().take(77).collect::<String>() + "..."
        } else {
            line.to_string()
        }
    }
}

// ---------------------------------------------------------------------------
// Library (the collection)
// ---------------------------------------------------------------------------

/// The user's full library of saved items.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Library {
    pub items: Vec<LibraryItem>,
}

impl Library {
    pub fn new() -> Self {
        Self::default()
    }

    /// Insert an item, bumping its updated_at.
    pub fn insert(&mut self, mut item: LibraryItem) {
        item.updated_at = Utc::now();
        self.items.push(item);
    }

    /// Remove an item by id.
    pub fn remove(&mut self, id: &Uuid) -> Option<LibraryItem> {
        if let Some(pos) = self.items.iter().position(|item| item.id == *id) {
            Some(self.items.remove(pos))
        } else {
            None
        }
    }

    /// Find an item by id.
    pub fn find(&self, id: &Uuid) -> Option<&LibraryItem> {
        self.items.iter().find(|item| item.id == *id)
    }

    /// Find an item by id, mutably.
    pub fn find_mut(&mut self, id: &Uuid) -> Option<&mut LibraryItem> {
        self.items.iter_mut().find(|item| item.id == *id)
    }

    /// Return all items that match the given tag.
    pub fn with_tag(&self, tag: &str) -> Vec<&LibraryItem> {
        self.items
            .iter()
            .filter(|item| item.tags.iter().any(|t| t == tag))
            .collect()
    }

    /// Return all items in the given category.
    pub fn in_category(&self, category: LibraryCategory) -> Vec<&LibraryItem> {
        self.items
            .iter()
            .filter(|item| item.category == category)
            .collect()
    }

    /// Return pinned items, ordered by usage_count descending.
    pub fn pinned(&self) -> Vec<&LibraryItem> {
        let mut v: Vec<&LibraryItem> = self.items.iter().filter(|i| i.pinned).collect();
        v.sort_by(|a, b| b.usage_count.cmp(&a.usage_count));
        v
    }

    /// Return the most recently used items.
    pub fn recent(&self, limit: usize) -> Vec<LibraryItem> {
        let mut v = self.items.clone();
        v.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        v.into_iter().take(limit).collect()
    }

    /// Search by substring in title or body (case-insensitive).
    pub fn search(&self, query: &str) -> Vec<&LibraryItem> {
        let q = query.to_ascii_lowercase();
        self.items
            .iter()
            .filter(|item| {
                item.title.to_ascii_lowercase().contains(&q)
                    || item.body.to_ascii_lowercase().contains(&q)
            })
            .collect()
    }

    /// Return the total number of items.
    pub fn len(&self) -> usize {
        self.items.len()
    }

    /// Whether the library is empty.
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    /// Remove every item that is not pinned.
    pub fn clear_unpinned(&mut self) {
        self.items.retain(|item| item.pinned);
    }
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LibraryExport {
    pub items: Vec<LibraryItem>,
    pub exported_at: DateTime<Utc>,
}

impl Library {
    /// Export the library to a serialisable format.
    pub fn to_export(&self) -> LibraryExport {
        LibraryExport {
            items: self.items.clone(),
            exported_at: Utc::now(),
        }
    }

    /// Import items from an export.
    pub fn from_export(export: LibraryExport) -> Self {
        Self {
            items: export
                .items
                .into_iter()
                .map(|mut item| {
                    item.id = Uuid::new_v4();
                    item
                })
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_library_item() {
        let item = LibraryItem::new("Title", "Body text here");
        assert_eq!(item.title, "Title");
        assert_eq!(item.body, "Body text here");
        assert!(!item.pinned);
        assert_eq!(item.usage_count, 0);
        assert_eq!(item.category, LibraryCategory::Other);
    }

    #[test]
    fn test_library_item_with_category() {
        let item = LibraryItem::with_category("P", "B", LibraryCategory::Prompt);
        assert_eq!(item.category, LibraryCategory::Prompt);
    }

    #[test]
    fn test_set_body_updates_timestamp() {
        let mut item = LibraryItem::new("T", "old");
        let old_ts = item.updated_at;
        // Sleep briefly.
        std::thread::sleep(std::time::Duration::from_millis(10));
        item.set_body("new");
        assert_eq!(item.body, "new");
        assert!(item.updated_at > old_ts);
    }

    #[test]
    fn test_tag_management() {
        let mut item = LibraryItem::new("T", "B");
        item.add_tag("rust");
        assert!(item.tags.contains(&"rust".to_string()));
        item.add_tag("rust"); // duplicate, no-op
        assert_eq!(item.tags.len(), 1);
        item.remove_tag("rust");
        assert!(item.tags.is_empty());
    }

    #[test]
    fn test_usage_and_pin() {
        let mut item = LibraryItem::new("T", "B");
        item.toggle_pinned();
        assert!(item.pinned);
        item.record_usage();
        item.record_usage();
        assert_eq!(item.usage_count, 2);
    }

    #[test]
    fn test_preview() {
        let item = LibraryItem::new("T", "First line\nSecond line");
        assert_eq!(item.preview(), "First line");
        let long_body = "x".repeat(100);
        let item2 = LibraryItem::new("T", long_body);
        assert!(item2.preview().ends_with("..."));
    }

    #[test]
    fn test_library_crud() {
        let mut lib = Library::new();
        assert!(lib.is_empty());
        let item = LibraryItem::new("A", "B");
        lib.insert(item.clone());
        assert_eq!(lib.len(), 1);
        assert!(lib.find(&item.id).is_some());
        let removed = lib.remove(&item.id);
        assert!(removed.is_some());
        assert!(lib.is_empty());
    }

    #[test]
    fn test_library_search() {
        let mut lib = Library::new();
        lib.insert(LibraryItem::new("hello world", "foo"));
        lib.insert(LibraryItem::new("goodbye", "bar"));
        let results = lib.search("hello");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "hello world");
    }

    #[test]
    fn test_library_filter() {
        let mut lib = Library::new();
        let p = LibraryItem::with_category("P1", "B1", LibraryCategory::Prompt);
        let mut s = LibraryItem::with_category("S1", "B2", LibraryCategory::Snippet);
        lib.insert(p);
        lib.insert(s.clone());
        assert_eq!(lib.in_category(LibraryCategory::Prompt).len(), 1);
        assert_eq!(lib.with_tag("tag").len(), 0); // no tags set
        s.add_tag("shared");
        lib.insert(s);
        assert_eq!(lib.with_tag("shared").len(), 1);
    }

    #[test]
    fn test_library_pinned() {
        let mut lib = Library::new();
        let mut a = LibraryItem::new("A", "B");
        a.set_pinned(true);
        lib.insert(a);
        lib.insert(LibraryItem::new("C", "D"));
        let pinned = lib.pinned();
        assert_eq!(pinned.len(), 1);
        assert_eq!(pinned[0].title, "A");
    }

    #[test]
    fn test_library_export_import() {
        let mut lib = Library::new();
        lib.insert(LibraryItem::new("orig", "body"));
        let export = lib.to_export();
        let imported = Library::from_export(export);
        // IDs should be regenerated.
        assert_ne!(lib.items[0].id, imported.items[0].id);
        assert_eq!(imported.items[0].title, "orig");
    }
}
