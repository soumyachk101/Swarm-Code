use std::process::Command;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Git types (mirrored in types.rs for command imports)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GitStatus {
 pub branch: Option<String>,
 pub upstream: Option<String>,
 pub ahead: u32,
 pub behind: u32,
 pub modified: Vec<String>,
 pub added: Vec<String>,
 pub deleted: Vec<String>,
 pub renamed: Vec<String>,
 pub untracked: Vec<String>,
 pub staged: Vec<String>,
 pub is_repo: bool,
}

impl GitStatus {
 pub fn is_dirty(&self) -> bool {
 !self.modified.is_empty() || !self.added.is_empty() || !self.deleted.is_empty() || !self.untracked.is_empty()
 }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffEntry {
 pub path: String,
 pub old_path: Option<String>,
 pub change_type: crate::types::DiffChangeType,
 pub additions: u32,
 pub deletions: u32,
 pub diff: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommit {
 pub hash: String,
 pub short_hash: String,
 pub author: String,
 pub email: String,
 pub date: chrono::DateTime<chrono::Utc>,
 pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBlame {
 pub line: usize,
 pub commit_hash: String,
 pub author: String,
 pub date: chrono::DateTime<chrono::Utc>,
 pub summary: String,
}

pub struct Git {
 pub path: String,
}

impl Git {
 pub fn new(path: impl Into<String>) -> Self {
 Self { path: path.into() }
 }

 pub fn is_repository(&self) -> bool {
 Command::new("git")
 .args(["rev-parse", "--git-dir"])
 .current_dir(&self.path)
 .output()
 .map(|o| o.status.success())
 .unwrap_or(false)
 }

 pub fn status(&self) -> Result<GitStatus, String> {
 let output = Command::new("git")
 .args(["status", "--porcelain=v1", "-b"])
 .current_dir(&self.path)
 .output()
 .map_err(|e| format!("Failed to run git status: {}", e))?;

 if !output.status.success() {
 return Err("Not a git repository".to_string());
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let mut branch = None;
 let mut upstream = None;
 let mut ahead = 0u32;
 let mut behind = 0u32;
 let mut modified = Vec::new();
 let mut added = Vec::new();
 let mut deleted = Vec::new();
 let mut renamed = Vec::new();
 let mut untracked = Vec::new();
 let mut staged = Vec::new();

 for line in stdout.lines() {
 if line.starts_with("##") {
 let branch_line = &line[2..];
 branch = Some(branch_line.split_whitespace().next().unwrap_or("").to_string());
 if let Some(pos) = branch_line.find("...") {
 let rest = &branch_line[pos + 3..];
 upstream = rest.split_whitespace().next().map(|s| s.to_string());
 }
 if let Some(ahead_pos) = branch_line.find("ahead ") {
 let rest = &branch_line[ahead_pos + 6..];
 let num_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
 ahead = num_str.parse().unwrap_or(0);
 }
 if let Some(behind_pos) = branch_line.find("behind ") {
 let rest = &branch_line[behind_pos + 7..];
 let num_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
 behind = num_str.parse().unwrap_or(0);
 }
 } else if line.len() >= 3 {
 let status_str = &line[0..2];
 let file_path = line[3..].to_string();
 match status_str.chars().next() {
 Some('M') => { modified.push(file_path.clone()); staged.push(file_path.clone()); }
 Some('A') => { added.push(file_path.clone()); staged.push(file_path.clone()); }
 Some('D') => { deleted.push(file_path.clone()); staged.push(file_path.clone()); }
 Some('R') => { renamed.push(file_path.clone()); staged.push(file_path.clone()); }
 Some('?') => { untracked.push(file_path); }
 Some(' ') => {
 let second = status_str.chars().nth(1);
 if second == Some('M') { modified.push(file_path.clone()); }
 if second == Some('D') { deleted.push(file_path.clone()); }
 if second == Some('A') { added.push(file_path.clone()); }
 }
 _ => {}
 }
 }
 }

 Ok(GitStatus {
 branch,
 upstream,
 ahead,
 behind,
 modified,
 added,
 deleted,
 renamed,
 untracked,
 staged,
 is_repo: true,
 })
 }

 pub fn diff(&self, file: Option<&str>) -> Result<Vec<DiffEntry>, String> {
 let mut args = vec!["diff", "--no-color", "--diff-filter=ACDMR", "-U3"];
 if let Some(f) = file {
 args.push("--");
 args.push(f);
 }

 let output = Command::new("git")
 .args(&args)
 .current_dir(&self.path)
 .output()
 .map_err(|e| format!("Failed to run git diff: {}", e))?;

 if !output.status.success() {
 let err = String::from_utf8_lossy(&output.stderr);
 return Err(format!("git diff failed: {}", err));
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let mut entries = Vec::new();
 let mut current_file: Option<String> = None;
 let mut current_old_path: Option<String> = None;
 let mut current_additions = 0u32;
 let mut current_deletions = 0u32;
 let mut diff_lines: Vec<String> = Vec::new();

 for line in stdout.lines() {
 if line.starts_with("diff --git") {
 if let Some(prev_file) = current_file.take() {
 entries.push(DiffEntry {
 path: prev_file,
 old_path: current_old_path.take(),
 change_type: crate::types::DiffChangeType::Modified,
 additions: current_additions,
 deletions: current_deletions,
 diff: if diff_lines.is_empty() { None } else { Some(diff_lines.join("\n")) },
 });
 diff_lines.clear();
 current_additions = 0;
 current_deletions = 0;
 }
 let parts: Vec<&str> = line.split_whitespace().collect();
 if parts.len() >= 4 {
 current_file = Some(parts[3].strip_prefix("b/").unwrap_or(parts[3]).to_string());
 current_old_path = Some(parts[2].strip_prefix("a/").unwrap_or(parts[2]).to_string());
 }
 } else {
 diff_lines.push(line.to_string());
 if line.starts_with("+") && !line.starts_with("+++") { current_additions += 1; }
 if line.starts_with("-") && !line.starts_with("---") { current_deletions += 1; }
 }
 }

 if let Some(prev_file) = current_file.take() {
 entries.push(DiffEntry {
 path: prev_file,
 old_path: current_old_path.take(),
 change_type: crate::types::DiffChangeType::Modified,
 additions: current_additions,
 deletions: current_deletions,
 diff: if diff_lines.is_empty() { None } else { Some(diff_lines.join("\n")) },
 });
 }

 if entries.is_empty() && file.is_some() {
 entries.push(DiffEntry {
 path: file.unwrap().to_string(),
 old_path: None,
 change_type: crate::types::DiffChangeType::Modified,
 additions: 0,
 deletions: 0,
 diff: None,
 });
 }

 Ok(entries)
 }
}

// ---------------------------------------------------------------------------
// init_git
//
// Module-level initializer for the git subsystem. Currently a no-op because
// all git operations are synchronous wrappers around the `git` CLI. Provided
// as a hook so that git credential-store setup, global config detection,
// and similar one-time work has a stable entry-point.
// ---------------------------------------------------------------------------

pub fn init_git() {
 // Intentionally empty.
}
