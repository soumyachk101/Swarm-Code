use std::process::Command;
use std::sync::Arc;
use tokio::sync::RwLock;

use tauri::State;

use crate::git::GitStatus;
use crate::types::DiffEntry;
use crate::types::DiffChangeType;
use crate::types::GitCommit;
use crate::types::GitBlame;
use crate::store::AppStore;

#[tauri::command]
pub async fn git_status(
 path: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<GitStatus, String> {
 let output = Command::new("git")
 .args(["status", "--porcelain=v1", "-b"])
 .current_dir(&path)
 .output()
 .map_err(|e| format!("Failed to run git status: {}", e))?;

 if !output.status.success() {
 let err = String::from_utf8_lossy(&output.stderr);
 return Err(format!("git status failed: {}", err));
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let mut status = GitStatus::default();

 for line in stdout.lines() {
 if line.starts_with("##") {
 let branch_line = &line[2..];
 status.branch = Some(branch_line.split_whitespace().next().unwrap_or("").to_string());
 if let Some(pos) = branch_line.find("...") {
 let rest = &branch_line[pos + 3..];
 status.upstream = rest.split_whitespace().next().map(|s| s.to_string());
 }
 if let Some(ahead_pos) = branch_line.find("ahead ") {
 let rest = &branch_line[ahead_pos + 6..];
 let num_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
 status.ahead = num_str.parse().unwrap_or(0);
 }
 if let Some(behind_pos) = branch_line.find("behind ") {
 let rest = &branch_line[behind_pos + 7..];
 let num_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
 status.behind = num_str.parse().unwrap_or(0);
 }
 } else if line.len() >= 3 {
 let status_str = &line[0..2];
 let file_path = line[3..].to_string();
 match status_str.chars().next() {
 Some('M') => { status.modified.push(file_path.clone()); status.staged.push(file_path.clone()); }
 Some('A') => { status.added.push(file_path.clone()); status.staged.push(file_path.clone()); }
 Some('D') => { status.deleted.push(file_path.clone()); status.staged.push(file_path.clone()); }
 Some('R') => { status.renamed.push(file_path.clone()); status.staged.push(file_path.clone()); }
 Some('?') => { status.untracked.push(file_path); }
 Some(' ') => {
 if status_str.chars().nth(1) == Some('M') { status.modified.push(file_path.clone()); }
 if status_str.chars().nth(1) == Some('D') { status.deleted.push(file_path.clone()); }
 if status_str.chars().nth(1) == Some('A') { status.added.push(file_path.clone()); }
 }
 _ => {}
 }
 }
 }

 status.is_repo = true;
 Ok(status)
}

#[tauri::command]
pub async fn git_diff(
 path: String,
 file: Option<String>,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<DiffEntry>, String> {
 let mut args = vec!["diff", "--no-color", "--diff-filter=ACDMR", "-U3"];
 if let Some(ref f) = file {
 args.push("--");
 args.push(f);
 }

 let output = Command::new("git")
 .args(&args)
 .current_dir(&path)
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
 change_type: DiffChangeType::Modified,
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
 change_type: DiffChangeType::Modified,
 additions: current_additions,
 deletions: current_deletions,
 diff: if diff_lines.is_empty() { None } else { Some(diff_lines.join("\n")) },
 });
 }

 if entries.is_empty() && file.is_some() {
 entries.push(DiffEntry {
 path: file.unwrap().to_string(),
 old_path: None,
 change_type: DiffChangeType::Modified,
 additions: 0,
 deletions: 0,
 diff: None,
 });
 }

 Ok(entries)
}

#[tauri::command]
pub async fn git_log(
 path: String,
 limit: usize,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<GitCommit>, String> {
 let output = Command::new("git")
 .args([
 "log",
 &format!("-{}", limit),
 "--format=%H|%h|%an|%ae|%ai|%s",
 ])
 .current_dir(&path)
 .output()
 .map_err(|e| format!("Failed to run git log: {}", e))?;

 if !output.status.success() {
 let err = String::from_utf8_lossy(&output.stderr);
 return Err(format!("git log failed: {}", err));
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let commits: Vec<GitCommit> = stdout
 .lines()
 .filter(|l| !l.is_empty())
 .filter_map(|line| {
 let parts: Vec<&str> = line.split('|').collect();
 if parts.len() >= 6 {
 Some(GitCommit {
 hash: parts[0].to_string(),
 short_hash: parts[1].to_string(),
 author: parts[2].to_string(),
 email: parts[3].to_string(),
 date: chrono::DateTime::parse_from_rfc3339(parts[4])
 .ok()
 .map(|d| d.with_timezone(&chrono::Utc))
 .unwrap_or_else(|| chrono::Utc::now()),
 message: parts[5..].join("|"),
 })
 } else {
 None
 }
 })
 .collect();

 Ok(commits)
}

#[tauri::command]
pub async fn git_blame(
 path: String,
 file: String,
 line: usize,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<GitBlame, String> {
 let output = Command::new("git")
 .args(["blame", "-L", &format!("{},{}", line, line), "--porcelain", &file])
 .current_dir(&path)
 .output()
 .map_err(|e| format!("Failed to run git blame: {}", e))?;

 if !output.status.success() {
 let err = String::from_utf8_lossy(&output.stderr);
 return Err(format!("git blame failed: {}", err));
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let mut commit_hash = String::new();
 let mut author = String::new();
 let mut date_ts: i64 = 0;
 let mut summary = String::new();

 for line in stdout.lines() {
 if line.len() == 40 && line.chars().all(|c| c.is_ascii_hexdigit()) {
 commit_hash = line.to_string();
 } else if let Some(stripped) = line.strip_prefix("author ") {
 author = stripped.to_string();
 } else if let Some(stripped) = line.strip_prefix("author-time ") {
 date_ts = stripped.parse().unwrap_or(0);
 } else if line.starts_with('\t') {
 summary = line[1..].to_string();
 break;
 }
 }

 let date = chrono::DateTime::from_timestamp(date_ts, 0)
 .unwrap_or_else(|| chrono::Utc::now())
 .with_timezone(&chrono::Utc);

 Ok(GitBlame {
 line,
 commit_hash,
 author,
 date,
 summary,
 })
}

#[tauri::command]
pub async fn get_touched_paths(
 workspace: String,
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<String>, String> {
 let output = Command::new("git")
 .args(["diff", "--name-only", "HEAD"])
 .current_dir(&workspace)
 .output()
 .map_err(|e| format!("Failed to run git diff: {}", e))?;

 if !output.status.success() {
 let err = String::from_utf8_lossy(&output.stderr);
 return Err(format!("git diff failed: {}", err));
 }

 let stdout = String::from_utf8_lossy(&output.stdout);
 let paths: Vec<String> = stdout
 .lines()
 .filter(|l| !l.is_empty())
 .map(|s| s.to_string())
 .collect();

 Ok(paths)
}
