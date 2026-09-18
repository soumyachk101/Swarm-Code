use std::sync::Arc;
use tokio::sync::RwLock;

use crate::types::{DirEntry, FilePreview};
use crate::store::AppStore;

#[tauri::command]
pub async fn read_file(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 path: String,
) -> Result<String, String> {
 tokio::fs::read_to_string(&path)
 .await
 .map_err(|e| format!("Could not read {}: {}", path, e))
}

#[tauri::command]
pub async fn write_file(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 path: String,
 content: String,
) -> Result<(), String> {
 // Create parent directories if needed
 if let Some(parent) = std::path::Path::new(&path).parent() {
 tokio::fs::create_dir_all(parent)
 .await
 .map_err(|e| format!("Could not create directories: {e}"))?;
 }
 tokio::fs::write(&path, content)
 .await
 .map_err(|e| format!("Could not write {}: {}", path, e))?;
 Ok(())
}

#[tauri::command]
pub async fn list_directory(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 path: String,
) -> Result<Vec<DirEntry>, String> {
 let mut entries = Vec::new();

 let mut dir_entries = tokio::fs::read_dir(&path)
 .await
 .map_err(|e| format!("Could not read directory {}: {}", path, e))?;

 while let Some(entry) = dir_entries
 .next_entry()
 .await
 .map_err(|e| format!("{}", e))?
 {
 let metadata = entry
 .metadata()
 .await
 .map_err(|e| format!("{}", e))?;
 let name = entry
 .file_name()
 .to_string_lossy()
 .to_string();
 let entry_path = entry.path().to_string_lossy().to_string();

 entries.push(DirEntry {
 name,
 path: entry_path,
 is_directory: metadata.is_dir(),
 size: if metadata.is_file() { Some(metadata.len()) } else { None },
 modified: metadata.modified().ok().map(|t| chrono::DateTime::<chrono::Utc>::from(t)),
 extension: entry
 .path()
 .extension()
 .and_then(|e| e.to_str())
 .map(|s| s.to_string()),
 });
 }

 entries.sort_by(|a, b| {
 match (a.is_directory, b.is_directory) {
 (true, false) => std::cmp::Ordering::Less,
 (false, true) => std::cmp::Ordering::Greater,
 _ => a.name.cmp(&b.name),
 }
 });

 Ok(entries)
}

#[tauri::command]
pub async fn get_file_preview(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 path: String,
) -> Result<FilePreview, String> {
 let metadata = tokio::fs::metadata(&path)
 .await
 .map_err(|e| format!("{}", e))?;

 let name = std::path::Path::new(&path)
 .file_name()
 .and_then(|n| n.to_str())
 .unwrap_or("")
 .to_string();

 let extension = std::path::Path::new(&path)
 .extension()
 .and_then(|e| e.to_str())
 .map(|s| s.to_string())
 .unwrap_or_default();

 // For text files, read the first 200 lines
 let is_text = extension_is_text(&extension);
 let (lines, preview) = if is_text {
 match tokio::fs::read_to_string(&path).await {
 Ok(content) => {
 let line_count = content.lines().count() as u32;
 let preview_text = content
 .lines()
 .take(200)
 .collect::<Vec<_>>()
 .join("\n");
 (line_count, preview_text)
 }
 Err(_) => (0, "[binary or unreadable]".to_string()),
 }
 } else {
 (0, "[binary file]".to_string())
 };

 Ok(FilePreview {
 path: path.clone(),
 name,
 extension,
 size: metadata.len(),
 lines,
 preview,
 is_text,
 })
}

fn extension_is_text(ext: &str) -> bool {
 matches!(
 ext.to_lowercase().as_str(),
 "txt" | "md" | "json" | "toml" | "yaml" | "yml" | "rs" | "swift"
 | "js" | "ts" | "py" | "rb" | "go" | "java" | "c" | "cpp" | "h"
 | "html" | "css" | "scss" | "xml" | "svg" | "sh" | "bash" | "zsh"
 | "fish" | "sql" | "r" | "lua" | "php" | "cs" | "tsx" | "jsx"
 | "vue" | "svelte" | "env" | "gitignore" | "gitattributes"
 | "lock" | "ini" | "cfg" | "conf" | "log" | "csv"
 )
}
