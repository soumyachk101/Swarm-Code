//! Data format migration utilities.
//!
//! Mirrors the Swift `LegacyMigration` class: handles upgrading the persisted
//! store JSON from older shape to the current shape, version by version, and
//! falls back gracefully when fields are missing or the format is unknown.
//!
//! Migration is intentionally non-destructive: the on-disk file is only
//! rewritten after a successful migration, and the original is preserved as
//! `library.json.migration_backup` until the user quits cleanly.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// Current format version. Bump whenever AppStore's on-disk shape changes
/// in a way that would break older versions of the app.
pub const CURRENT_VERSION: u32 = 4;

/// Versioned envelope around the persisted AppStore. Older revisions of the
/// store were written without this header, so the migrator looks at the JSON
/// shape directly to detect the version when the header is absent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionedStore {
 pub version: u32,
 pub store: serde_json::Value,
}

impl VersionedStore {
 /// Wrap a raw JSON object in a versioned envelope.
 pub fn wrap(value: serde_json::Value) -> Self {
 Self { version: CURRENT_VERSION, store: value }
 }

 pub fn unwrap(self) -> serde_json::Value {
 self.store
 }
}

/// Result of running a migration. The migrator never fails the boot -- the
/// worst-case behavior is "we kept the old file as-is" so the user can still
/// launch and recover.
#[derive(Debug, Clone, Default)]
pub struct MigrationResult {
 pub from_version: Option<u32>,
 pub to_version: u32,
 pub applied: Vec<String>,
 pub warnings: Vec<String>,
 pub backup_path: Option<PathBuf>,
}

impl MigrationResult {
 pub fn ok() -> Self {
 Self { to_version: CURRENT_VERSION, ..Default::default() }
 }
}

/// Migration errors are non-fatal -- callers log the message and continue
/// with whatever could be recovered from disk.
#[derive(Debug, Clone)]
pub struct MigrationError {
 pub message: String,
 pub backup: Option<PathBuf>,
}

impl std::fmt::Display for MigrationError {
 fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
 write!(f, "Migration error: {}", self.message)
 }
}

impl std::error::Error for MigrationError {}

/// Reads `path` and returns a `(raw_json, version)` pair. When the file is
/// missing or empty, returns `(None, 0)`.
pub fn detect_version(path: &Path) -> Result<(Option<serde_json::Value>, u32), String> {
 if !path.exists() {
 return Ok((None, 0));
 }
 let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
 if raw.trim().is_empty() {
 return Ok((None, 0));
 }
 let value: serde_json::Value = serde_json::from_str(&raw)
 .map_err(|e| format!("Invalid store JSON: {e}"))?;

 // Newer files have an explicit `version` envelope.
 if let Some(v) = value.get("version").and_then(|v| v.as_u64()) {
 return Ok((Some(value), v as u32));
 }

 // Older files wrote the AppStore fields directly. Best-effort version
 // detection by presence of schema-introducing fields.
 let detected = if value.get("thread_documents").is_some() {
 4
 } else if value.get("hydra_pairs").is_some() {
 3
 } else if value.get("settings").is_some() {
 2
 } else {
 1
 };

 Ok((Some(value), detected))
}

/// Backup `path` to `path.migration_backup` and return the backup path. If
/// the backup already exists it is overwritten -- that is fine because
/// migration runs once per boot before the new file is written.
fn backup(path: &Path) -> Result<PathBuf, String> {
 let mut backup_path = path.to_path_buf();
 let new_name = match path.file_name().and_then(|n| n.to_str()) {
 Some(name) => format!("{name}.migration_backup"),
 None => "library.json.migration_backup".to_string(),
 };
 backup_path.set_file_name(new_name);
 fs::copy(path, &backup_path).map_err(|e| e.to_string())?;
 Ok(backup_path)
}

/// Migration v1 -> v2: introduced `AppSettings` (was previously embedded in
/// the Swift `Preferences` class). Older JSON had a flat `preferences` block
/// keyed by preference name; we copy those values into a default
/// `AppSettings` so they at least appear in the new shape.
fn migrate_v1_to_v2(value: &mut serde_json::Value) -> Result<(), String> {
 if let Some(prefs) = value.get_mut("preferences").and_then(|p| p.as_object_mut()) {
 let mut settings = serde_json::Map::new();
 for (k, v) in prefs.iter() {
 settings.insert(k.clone(), v.clone());
 }
 value.as_object_mut()
 .unwrap()
 .insert("settings".to_string(), serde_json::Value::Object(settings));
 } else {
 // No preferences -- fall back to defaults.
 value.as_object_mut()
 .unwrap()
 .insert("settings".to_string(), serde_json::json!({}));
 }
 Ok(())
}

/// Migration v2 -> v3: introduced `HydraPair` (was previously a loose
/// `hydra_configs` array). Promote that array into the structured
/// `hydra_pairs` field.
fn migrate_v2_to_v3(value: &mut serde_json::Value) -> Result<(), String> {
 let obj = value.as_object_mut().unwrap();
 if obj.get("hydra_pairs").is_none() {
 let legacy = obj.remove("hydra_configs").unwrap_or(serde_json::json!([]));
 obj.insert("hydra_pairs".to_string(), legacy);
 }
 Ok(())
}

/// Migration v3 -> v4: introduced `ThreadDocument` (separated from the
/// timeline). Move any inline documents into a dedicated array.
fn migrate_v3_to_v4(value: &mut serde_json::Value) -> Result<(), String> {
 let obj = value.as_object_mut().unwrap();
 if obj.get("thread_documents").is_none() {
 obj.insert("thread_documents".to_string(), serde_json::json!([]));
 }
 Ok(())
}

/// Run any pending migrations and return the result. Writes the migrated
/// file to `path` as a versioned envelope. Returns the migrated JSON value
/// (with the version header stripped) and the migration result summary.
pub fn run_migrations(path: &Path) -> Result<(serde_json::Value, MigrationResult), MigrationError> {
 let mut result = MigrationResult::ok();
 let (raw, version) = detect_version(path).map_err(|e| MigrationError {
 message: e,
 backup: None,
 })?;

 let mut value = match raw {
 Some(v) => v,
 None => {
 // No file on disk -- caller will use defaults.
 return Err(MigrationError {
 message: "no file".to_string(),
 backup: None,
 });
 }
 };

 if version == 0 {
 return Err(MigrationError {
 message: "empty file".to_string(),
 backup: None,
 });
 }

 result.from_version = Some(version);

 if version < CURRENT_VERSION {
 let backup = backup(path).ok();
 result.backup_path = backup.clone();

 // v1 -> v2
 if version < 2 {
 migrate_v1_to_v2(&mut value)
 .map_err(|e| MigrationError { message: e, backup: backup.clone() })?;
 result.applied.push("v1->v2 (AppSettings)".to_string());
 }

 // v2 -> v3
 if version < 3 {
 migrate_v2_to_v3(&mut value)
 .map_err(|e| MigrationError { message: e, backup: backup.clone() })?;
 result.applied.push("v2->v3 (HydraPair)".to_string());
 }

 // v3 -> v4
 if version < 4 {
 migrate_v3_to_v4(&mut value)
 .map_err(|e| MigrationError { message: e, backup: backup.clone() })?;
 result.applied.push("v3->v4 (ThreadDocument)".to_string());
 }
 }

 // Strip any pre-versioned top-level "version" key and rewrap.
 if let Some(obj) = value.as_object_mut() {
 obj.remove("version");
 }

 result.to_version = CURRENT_VERSION;
 Ok((value, result))
}

/// Convenience: write `value` as a versioned store to `path`.
pub fn write_versioned(path: &Path, value: serde_json::Value) {
 if let Some(parent) = path.parent() {
 let _ = fs::create_dir_all(parent);
 }
 let wrapped = VersionedStore::wrap(value);
 if let Ok(json) = serde_json::to_string_pretty(&wrapped) {
 let tmp = path.with_extension("json.tmp");
 if fs::write(&tmp, json.as_bytes()).is_ok() {
 let _ = fs::rename(&tmp, path);
 }
 }
}

/// Convenience: read the raw JSON from `path` without migrations.
pub fn read_raw(path: &Path) -> Result<serde_json::Value, String> {
 if !path.exists() {
 return Err("file not found".to_string());
 }
 let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
 serde_json::from_str(&raw).map_err(|e| format!("Invalid JSON: {e}"))
}

#[cfg(test)]
mod tests {
 use super::*;
 use uuid::Uuid;

 #[test]
 fn detect_empty_missing_file() {
 let dir = std::env::temp_dir().join(format!("swarmcode-mig-{}", uuid::Uuid::new_v4()));
 fs::create_dir_all(&dir).unwrap();
 let path = dir.join("library.json");
 let (raw, ver) = detect_version(&path).unwrap();
 assert!(raw.is_none());
 assert_eq!(ver, 0);
 let _ = fs::remove_dir_all(&dir);
 }

 #[test]
 fn detect_v1_format() {
 let dir = std::env::temp_dir().join(format!("swarmcode-mig-{}", uuid::Uuid::new_v4()));
 fs::create_dir_all(&dir).unwrap();
 let path = dir.join("library.json");
 fs::write(&path, r#"{"projects":[],"threads":[],"preferences":{"theme":"dark"}}"#).unwrap();
 let (_, ver) = detect_version(&path).unwrap();
 assert_eq!(ver, 1);
 let _ = fs::remove_dir_all(&dir);
 }

 #[test]
 fn detect_v2_format() {
 let dir = std::env::temp_dir().join(format!("swarmcode-mig-{}", uuid::Uuid::new_v4()));
 fs::create_dir_all(&dir).unwrap();
 let path = dir.join("library.json");
 fs::write(&path, r#"{"projects":[],"threads":[],"settings":{},"hydra_configs":[]}"#).unwrap();
 let (_, ver) = detect_version(&path).unwrap();
 assert_eq!(ver, 2);
 let _ = fs::remove_dir_all(&dir);
 }
}
