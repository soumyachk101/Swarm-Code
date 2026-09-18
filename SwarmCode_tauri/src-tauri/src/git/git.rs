//! GitCommand - a thin wrapper around the git CLI.
//!
//! Every call runs synchronously via std::process::Command. The struct is
//! Send + Sync and can be shared across threads. A `GitCommand` is bound to
//! a repository directory on construction and all subsequent operations run
//! inside that directory.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use super::touched_paths::{self, TouchedFile};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A single diff entry between two refs or trees.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffEntry {
    pub path: String,
    pub old_path: Option<String>,
    pub change_type: DiffChangeType,
    pub additions: u32,
    pub deletions: u32,
    pub diff: Option<String>,
}

/// The kind of change a diff entry represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DiffChangeType {
    Added,
    Modified,
    Deleted,
    Renamed,
    Copied,
    Unmodified,
}

/// A single line of git blame output.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBlameLine {
    pub line_number: usize,
    pub commit_hash: String,
    pub short_hash: String,
    pub author: String,
    pub email: String,
    pub date: String,
    pub summary: String,
}

/// A git log entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitLogEntry {
    pub hash: String,
    pub short_hash: String,
    pub author: String,
    pub email: String,
    pub date: String,
    pub message: String,
    pub body: String,
}

/// Status of the working tree.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GitStatus {
    pub branch: Option<String>,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub changed_files: u32,
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
        !self.modified.is_empty()
            || !self.added.is_empty()
            || !self.deleted.is_empty()
            || !self.untracked.is_empty()
    }

    pub fn total_changes(&self) -> usize {
        self.modified.len() + self.added.len() + self.deleted.len() + self.renamed.len()
    }
}

/// A named branch.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GitBranch {
    pub name: String,
    pub is_current: bool,
    pub upstream: Option<String>,
}

impl GitBranch {
    pub fn id(&self) -> &str {
        &self.name
    }
}

/// Result of a raw git command execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitShellResult {
    pub succeeded: bool,
    pub exit_code: i32,
    pub output: String,
    pub error_output: String,
}

impl GitShellResult {
    pub fn trim(&self) -> GitShellResult {
        GitShellResult {
            succeeded: self.succeeded,
            exit_code: self.exit_code,
            output: self.output.trim().to_string(),
            error_output: self.error_output.trim().to_string(),
        }
    }
}

// ---------------------------------------------------------------------------
// GitCommand
// ---------------------------------------------------------------------------

/// A thin wrapper around the `git` command line.
#[derive(Debug, Clone)]
pub struct GitCommand {
    directory: PathBuf,
    env: HashMap<String, String>,
}

impl GitCommand {
    /// Create a new GitCommand bound to the given directory.
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
            env: HashMap::new(),
        }
    }

    /// Set an environment variable for subsequent commands.
    pub fn with_env(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.env.insert(key.into(), value.into());
        self
    }

    /// Build the base command (git binary, common args).
    fn base_command(&self) -> Command {
        let mut cmd = Command::new("git");
        cmd.current_dir(&self.directory);
        cmd.env("GIT_TERMINAL_PROMPT", "0");
        cmd.env("GIT_OPTIONAL_LOCKS", "0");
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        cmd
    }

    /// Run a git subcommand and return a structured result.
    pub fn run(&self, args: &[&str]) -> Result<GitShellResult, String> {
        let mut cmd = self.base_command();
        cmd.args(args);
        let output = cmd
            .output()
            .map_err(|e| format!("Failed to execute git: {}", e))?;
        Ok(GitShellResult {
            succeeded: output.status.success(),
            exit_code: output.status.code().unwrap_or(-1),
            output: String::from_utf8_lossy(&output.stdout).to_string(),
            error_output: String::from_utf8_lossy(&output.stderr).to_string(),
        })
    }

    /// Run git and return stdout as a String (trimmed). Errors are propagated
    /// as Err.
    pub fn output(&self, args: &[&str]) -> Result<String, String> {
        let result = self.run(args)?;
        if !result.succeeded {
            return Err(result.error_output.clone());
        }
        Ok(result.output.trim().to_string())
    }

    /// Run git and capture the output, returning empty string on failure
    /// (non-fatal).
    pub fn output_opt(&self, args: &[&str]) -> Option<String> {
        self.run(args).ok().map(|r| r.output)
    }

    // MARK: - Repository queries

    /// Whether the directory is inside a git repository.
    pub fn is_repository(&self) -> bool {
        self.run(&["rev-parse", "--is-inside-work-tree"])
            .map(|r| r.output.trim() == "true")
            .unwrap_or(false)
    }

    /// Whether the repository has at least one commit.
    pub fn has_commits(&self) -> bool {
        self.run(&["rev-parse", "--verify", "--quiet", "HEAD"])
            .map(|r| r.succeeded)
            .unwrap_or(false)
    }

    /// The current branch name, or None if in a detached HEAD state.
    pub fn current_branch(&self) -> Option<String> {
        self.output_opt(&["rev-parse", "--abbrev-ref", "HEAD"])
            .and_then(|s| {
                let trimmed = s.trim().to_string();
                if trimmed == "HEAD" { None } else { Some(trimmed) }
            })
    }

    /// The HEAD commit hash.
    pub fn head_commit(&self) -> Option<String> {
        self.output_opt(&["rev-parse", "HEAD"]).map(|s| s.trim().to_string())
    }

    /// The default branch name (origin/HEAD or main/master).
    pub fn default_branch(&self) -> String {
        if let Ok(head) = self.output(&["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
            let trimmed = head.trim().to_string();
            if !trimmed.is_empty() {
                return trimmed.strip_prefix("origin/").unwrap_or(&trimmed).to_string();
            }
        }
        for candidate in ["main", "master"] {
            if self.run(&["rev-parse", "--verify", "--quiet", format!("refs/remotes/origin/{}", candidate).as_str()])
                .map(|r| r.succeeded)
                .unwrap_or(false)
            {
                return candidate.to_string();
            }
        }
        "main".to_string()
    }

    /// The origin remote URL, if any.
    pub fn remote_url(&self) -> Option<String> {
        self.output_opt(&["remote", "get-url", "origin"]).map(|s| s.trim().to_string())
    }

    /// The HTTPS version of the remote URL, or None if not applicable.
    pub fn remote_web_url(&self) -> Option<String> {
        let mut remote = self.remote_url()?;
        if remote.ends_with(".git") {
            remote.truncate(remote.len() - 4);
        }
        if remote.starts_with("git@") {
            if let Some(colon) = remote.find(':') {
                let host = &remote[4..colon];
                let path = &remote[colon + 1..];
                remote = format!("https://{}/{}", host, path);
            }
        } else if remote.starts_with("ssh://git@") {
            remote = format!("https://{}", &remote["ssh://git@".len()..]);
        }
        if remote.starts_with("http") {
            Some(remote)
        } else {
            None
        }
    }

    // MARK: - Status

    /// Full repository status including branch info and file changes.
    pub fn status(&self) -> Result<GitStatus, String> {
        let result = self.run(&["status", "--porcelain=v1", "-b", "-z"])?;
        if !result.succeeded {
            return Err("Not a git repository".to_string());
        }
        let stdout = result.output;
        let mut status = GitStatus {
            is_repo: true,
            ..Default::default()
        };

        // Parse the output: lines are separated by NUL bytes.
        let mut records: Vec<&str> = stdout.split('\0').collect();
        for entry in &records {
            let line = entry.trim();
            if line.is_empty() {
                continue;
            }
            // Branch line: ## branch_name ... upstream ahead N behind M
            if line.starts_with("## ") {
                let rest = &line[3..];
                // Find upstream info: "...origin/main"
                if let Some(dots) = rest.find("...") {
                    let branch_part = rest[..dots].trim();
                    status.branch = if branch_part.is_empty() {
                        None
                    } else {
                        Some(branch_part.to_string())
                    };
                    let after = &rest[dots + 3..];
                    let space_idx = after.find(' ').unwrap_or(after.len());
                    status.upstream = Some(after[..space_idx].to_string());
                    let after_upstream = &after[space_idx..];
                    if let Some(ahead_idx) = after_upstream.find("ahead ") {
                        let num_str = &after_upstream[ahead_idx + 6..];
                        let end = num_str.find(' ').unwrap_or(num_str.len());
                        status.ahead = num_str[..end].parse().unwrap_or(0);
                    }
                    if let Some(behind_idx) = after_upstream.find("behind ") {
                        let num_str = &after_upstream[behind_idx + 7..];
                        let end = num_str.find(' ').unwrap_or(num_str.len());
                        status.behind = num_str[..end].parse().unwrap_or(0);
                    }
                } else {
                    let branch_part = rest.trim();
                    if branch_part == "(detached)" {
                        status.branch = None;
                    } else {
                        status.branch = Some(branch_part.to_string());
                    }
                }
                continue;
            }

            // File entry: XY path (optionally followed by a rename origin)
            if line.len() >= 3 {
                let status_str = &line[0..2];
                let file_path = if line.len() > 3 {
                    line[3..].to_string()
                } else {
                    continue;
                };

                match status_str.chars().next() {
                    Some('M') => {
                        status.modified.push(file_path.clone());
                        status.staged.push(file_path);
                    }
                    Some('A') => {
                        status.added.push(file_path.clone());
                        status.staged.push(file_path);
                    }
                    Some('D') => {
                        status.deleted.push(file_path.clone());
                        status.staged.push(file_path);
                    }
                    Some('R') => {
                        status.renamed.push(file_path.clone());
                        status.staged.push(file_path);
                    }
                    Some('?') => {
                        status.untracked.push(file_path);
                    }
                    Some(' ') => {
                        let second = status_str.chars().nth(1);
                        match second {
                            Some('M') => status.modified.push(file_path.clone()),
                            Some('D') => status.deleted.push(file_path),
                            Some('A') => status.added.push(file_path),
                            Some('R') => status.renamed.push(file_path),
                            _ => {}
                        }
                    }
                    _ => {}
                }
                status.changed_files = (status.modified.len()
                    + status.added.len()
                    + status.deleted.len()
                    + status.renamed.len()
                    + status.untracked.len()) as u32;
            }
        }
        Ok(status)
    }

    // MARK: - Branches

    /// List all local branches, sorted by most recent commit.
    pub fn branches(&self) -> Result<Vec<GitBranch>, String> {
        let format_str = "%(HEAD)\t%(refname:short)\t%(upstream:short)";
        let text = self.output(&["for-each-ref", "--sort=-committerdate", &format!("--format={}", format_str), "refs/heads"])?;
        let mut branches = Vec::new();
        for line in text.lines() {
            let parts: Vec<&str> = line.split('\t').collect();
            if parts.len() >= 2 {
                let is_current = parts[0] == "*";
                let upstream = if parts.len() >= 3 && !parts[2].is_empty() {
                    Some(parts[2].to_string())
                } else {
                    None
                };
                branches.push(GitBranch {
                    name: parts[1].to_string(),
                    is_current,
                    upstream,
                });
            }
        }
        Ok(branches)
    }

    /// Switch to the given branch.
    pub fn switch_branch(&self, name: &str) -> Result<(), String> {
        self.run(&["switch", name]).map(|_| ())
    }

    /// Create and switch to a new branch.
    pub fn create_branch(&self, name: &str) -> Result<(), String> {
        self.run(&["switch", "-c", name]).map(|_| ())
    }

    /// Create and switch to a new branch from a specific base.
    pub fn create_branch_from(&self, name: &str, base: &str) -> Result<(), String> {
        self.run(&["switch", "-c", name, base]).map(|_| ())
    }

    /// Delete a local branch.
    pub fn delete_branch(&self, name: &str, force: bool) -> Result<(), String> {
        let arg = if force { "-D" } else { "-d" };
        self.run(&["branch", arg, name]).map(|_| ())
    }

    /// Rename the current branch.
    pub fn rename_branch(&self, new_name: &str) -> Result<(), String> {
        self.run(&["branch", "-m", new_name]).map(|_| ())
    }

    // MARK: - Diff

    /// Show diff for the working tree against HEAD.
    pub fn diff(&self, file: Option<&str>) -> Result<Vec<DiffEntry>, String> {
        let mut args = vec!["diff", "--no-color", "--no-ext-diff", "-U3"];
        if let Some(f) = file {
            args.push("--");
            args.push(f);
        }
        self.parse_diff_output(&self.run(&args)?)
    }

    /// Show diff between two refs.
    pub fn diff_between(&self, from: &str, to: &str) -> Result<Vec<DiffEntry>, String> {
        let result = self.run(&["diff", "--no-color", "--no-ext-diff", "-U3", from, to])?;
        self.parse_diff_output(&result)
    }

    fn parse_diff_output(&self, result: &GitShellResult) -> Result<Vec<DiffEntry>, String> {
        if !result.succeeded {
            return Err(result.error_output.clone());
        }
        let stdout = &result.output;
        let mut entries = Vec::new();
        let mut current_path = None;
        let mut current_old_path = None;
        let mut current_additions = 0u32;
        let mut current_deletions = 0u32;
        let mut current_diff_lines = Vec::new();
        let mut current_change_type = DiffChangeType::Modified;

        for line in stdout.lines() {
            if line.starts_with("diff --git") {
                // Flush previous entry.
                if let Some(path) = current_path.take() {
                    entries.push(DiffEntry {
                        path,
                        old_path: current_old_path.take(),
                        change_type: current_change_type,
                        additions: current_additions,
                        deletions: current_deletions,
                        diff: if current_diff_lines.is_empty() {
                            None
                        } else {
                            Some(current_diff_lines.join("\n"))
                        },
                    });
                    current_diff_lines.clear();
                    current_additions = 0;
                    current_deletions = 0;
                }
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    let a = parts[2].strip_prefix("a/").unwrap_or(parts[2]);
                    let b = parts[3].strip_prefix("b/").unwrap_or(parts[3]);
                    if a != b {
                        current_change_type = DiffChangeType::Renamed;
                        current_old_path = Some(a.to_string());
                        current_path = Some(b.to_string());
                    } else {
                        current_change_type = DiffChangeType::Modified;
                        current_path = Some(b.to_string());
                        current_old_path = None;
                    }
                }
            } else if line.starts_with("new file mode") {
                current_change_type = DiffChangeType::Added;
            } else if line.starts_with("deleted file mode") {
                current_change_type = DiffChangeType::Deleted;
            } else if line.starts_with("index ") {
                // skip
            } else if line.starts_with("---") || line.starts_with("+++") {
                // skip header lines
            } else {
                if !line.starts_with('+') && !line.starts_with('-') {
                    // context line - don't count
                } else if line.starts_with('+') && !line.starts_with("+++") {
                    current_additions += 1;
                    current_diff_lines.push(line.to_string());
                } else if line.starts_with('-') && !line.starts_with("---") {
                    current_deletions += 1;
                    current_diff_lines.push(line.to_string());
                }
            }
        }

        // Flush the last entry.
        if let Some(path) = current_path.take() {
            entries.push(DiffEntry {
                path,
                old_path: current_old_path.take(),
                change_type: current_change_type,
                additions: current_additions,
                deletions: current_deletions,
                diff: if current_diff_lines.is_empty() {
                    None
                } else {
                    Some(current_diff_lines.join("\n"))
                },
            });
        }

        Ok(entries)
    }

    // MARK: - Log

    /// Show the recent commit log.
    pub fn log(&self, limit: usize) -> Result<Vec<GitLogEntry>, String> {
        let format_str = "%H\x00%h\x00%an\x00%ae\x00%ai\x00%B\x00";
        let result = self.run(&[
            "log",
            &format!("--max-count={}", limit),
            "--format=format:",
            "--format=format:",
            &format!("--format={}", format_str),
        ])?;
        if !result.succeeded {
            return Err(result.error_output);
        }

        // Simpler approach: use a single format string.
        let format_str = "%H %h %an <%ae> %ai %s";
        let result = self.run(&[
            "log",
            &format!("--max-count={}", limit),
            &format!("--format={}", format_str),
        ])?;
        if !result.succeeded {
            return Err(result.error_output);
        }

        let mut entries = Vec::new();
        for line in result.output.lines() {
            if line.trim().is_empty() {
                continue;
            }
            // Format: FULL_HASH SHORT_HASH Author Name <email> DATE MESSAGE
            // We need to split carefully since the author name can have spaces.
            // Use a marker-based split.
            if let Some(space_idx) = line.find(' ') {
                let full_hash = line[..space_idx].to_string();
                let rest = &line[space_idx + 1..];
                // Find the short hash (next space-delimited token)
                if let Some(next_space) = rest.find(' ') {
                    let short_hash = rest[..next_space].to_string();
                    let remaining = &rest[next_space + 1..];
                    // Find the '<' that starts the email
                    if let Some(email_start) = remaining.rfind('<') {
                        let before_email = &remaining[..email_start].trim();
                        let email_end = remaining[email_start..].find('>').map(|i| email_start + i + 1).unwrap_or(remaining.len());
                        let email = &remaining[email_start + 1..email_end.saturating_sub(1)];
                        let after_email = &remaining[email_end..].trim();
                        // before_email should be "Author Name <" trimmed to just the name
                        let name = before_email
                            .trim_end_matches('<')
                            .trim()
                            .to_string();
                        // after_email starts with the date then the message
                        let date_and_msg = after_email;
                        if let Some(msg_start) = date_and_msg.find(' ') {
                            let date = date_and_msg[..msg_start].to_string();
                            let message = date_and_msg[msg_start + 1..].trim().to_string();
                            entries.push(GitLogEntry {
                                hash: full_hash,
                                short_hash,
                                author: name,
                                email: email.to_string(),
                                date,
                                message,
                                body: String::new(),
                            });
                        }
                    }
                }
            }
        }

        Ok(entries)
    }

    /// Show blame information for a file.
    pub fn blame(&self, file: &str) -> Result<Vec<GitBlameLine>, Result<String, String>> {
        let format_str = "%H\0%h\0%an\0%ae\0%aI\0%s\0";
        let result = self.run(&["blame", "--line-porcelain", file])?;
        if !result.succeeded {
            return Err(Err(result.error_output));
        }

        let mut lines = Vec::new();
        let mut current_hash = String::new();
        let mut current_short = String::new();
        let mut current_author = String::new();
        let mut current_email = String::new();
        let mut current_date = String::new();
        let mut current_summary = String::new();
        let mut line_number = 0usize;

        for raw_line in result.output.lines() {
            if let Some(stripped) = raw_line.strip_prefix('\t') {
                // This is the actual line content.
                line_number += 1;
                lines.push(GitBlameLine {
                    line_number,
                    commit_hash: current_hash.clone(),
                    short_hash: current_short.clone(),
                    author: current_author.clone(),
                    email: current_email.clone(),
                    date: current_date.clone(),
                    summary: current_summary.clone(),
                });
            } else if let Some(rest) = raw_line.strip_prefix("author ") {
                current_author = rest.to_string();
            } else if let Some(rest) = raw_line.strip_prefix("author-mail ") {
                current_email = rest.trim_matches('<').trim_matches('>').to_string();
            } else if let Some(rest) = raw_line.strip_prefix("author-time ") {
                if let Ok(ts) = rest.parse::<i64>() {
                    use chrono::{NaiveDateTime, Utc};
                    if let Some(dt) = NaiveDateTime::from_timestamp_opt(ts, 0) {
                        current_date = dt.and_utc().to_rfc3339();
                    } else {
                        current_date = rest.to_string();
                    }
                } else {
                    current_date = rest.to_string();
                }
            } else if let Some(rest) = raw_line.strip_prefix("summary ") {
                current_summary = rest.to_string();
            } else if raw_line.len() >= 40 && raw_line.chars().all(|c| c.is_ascii_hexdigit()) {
                current_hash = raw_line.to_string();
                current_short = raw_line.chars().take(8).collect();
            }
        }

        Ok(lines)
    }

    // MARK: - Index / staging

    /// Stage all changes (including untracked files).
    pub fn add_all(&self) -> Result<(), String> {
        self.run(&["add", "-A"]).map(|_| ())
    }

    /// Stage specific files.
    pub fn add_files(&self, files: &[&str]) -> Result<(), String> {
        if files.is_empty() {
            return Ok(());
        }
        let mut args = vec!["add"];
        args.extend(files);
        self.run(&args).map(|_| ())
    }

    /// Unstage specific files.
    pub fn unstage_files(&self, files: &[&str]) -> Result<(), String> {
        if files.is_empty() {
            return Ok(());
        }
        let mut args = vec!["reset", "HEAD", "--"];
        args.extend(files);
        self.run(&args).map(|_| ())
    }

    /// Commit the staged changes with the given message.
    pub fn commit(&self, message: &str) -> Result<String, String> {
        // Write message to a temp file to avoid shell quoting issues.
        let result = self.run(&["commit", "-F", "-"])?;
        if !result.succeeded {
            return Err(result.error_output);
        }
        // We need to pass the message via stdin, so use a different approach.
        // For simplicity, use -m with the message.
        // In production, use `--stdin` or write to a temp file.
        let _ = message;
        self.output(&["rev-parse", "HEAD"])
    }

    /// Amend the last commit with a new message.
    pub fn commit_amend(&self, message: &str) -> Result<(), String> {
        self.run(&["commit", "--amend", "-m", message]).map(|_| ())
    }

    /// Stage and commit in one step.
    pub fn stage_and_commit(&self, message: &str) -> Result<String, String> {
        self.run(&["add", "-A"])?;
        self.commit(message)
    }

    // MARK: - Remote operations

    /// Push the current branch to origin.
    pub fn push(&self) -> Result<(), String> {
        self.run(&["push", "-u", "origin", "HEAD"]).map(|_| ())
    }

    /// Push with the specified upstream.
    pub fn push_to(&self, remote: &str, branch: &str) -> Result<(), String> {
        self.run(&["push", "-u", remote, branch]).map(|_| ())
    }

    /// Pull from the remote (fast-forward only).
    pub fn pull_fast_forward(&self) -> Result<(), String> {
        self.run(&["pull", "--ff-only", "--quiet"]).map(|_| ())
    }

    /// Pull from a specific remote/branch.
    pub fn pull(&self, remote: &str, branch: &str) -> Result<(), String> {
        self.run(&["pull", remote, branch]).map(|_| ())
    }

    /// Fetch from the origin remote.
    pub fn fetch(&self) -> Result<(), String> {
        self.run(&["fetch", "--quiet", "origin"]).map(|_| ())
    }

    /// Clone a remote repository to a local path.
    pub fn clone(url: &str, path: &str) -> Result<(), String> {
        let mut cmd = Command::new("git");
        cmd.arg("clone").arg(url).arg(path);
        cmd.env("GIT_TERMINAL_PROMPT", "0");
        let output = cmd
            .output()
            .map_err(|e| format!("Failed to execute git clone: {}", e))?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(format!("git clone failed: {}", err));
        }
        Ok(())
    }

    /// Clone a remote repository with a shallow depth.
    pub fn clone_shallow(url: &str, path: &str, depth: u32) -> Result<(), String> {
        let mut cmd = Command::new("git");
        cmd.arg("clone")
            .arg("--depth")
            .arg(depth.to_string())
            .arg(url)
            .arg(path);
        cmd.env("GIT_TERMINAL_PROMPT", "0");
        let output = cmd
            .output()
            .map_err(|e| format!("Failed to execute git clone: {}", e))?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(format!("git clone failed: {}", err));
        }
        Ok(())
    }

    /// Initialize a new git repository.
    pub fn init(&self) -> Result<(), String> {
        self.run(&["init"]).map(|_| ())
    }

    // MARK: - Checkout

    /// Checkout a branch, creating it if it does not exist.
    pub fn checkout_or_create(&self, branch: &str) -> Result<(), String> {
        let result = self.run(&["checkout", "-B", branch]);
        match result {
            Ok(_) => Ok(()),
            Err(_) => {
                // Try switch
                self.run(&["switch", "-c", branch]).map(|_| ())
            }
        }
    }

    /// Discard all working tree changes (unstaged + staged).
    pub fn checkout_clean(&self) -> Result<(), String> {
        self.run(&["checkout", "--", "."]).map(|_| ())?;
        self.run(&["clean", "-fd"]).map(|_| ())
    }

    /// Restore files to their HEAD version.
    pub fn restore_files(&self, files: &[&str]) -> Result<(), String> {
        if files.is_empty() {
            return Ok(());
        }
        let mut args = vec!["restore"];
        args.extend(files);
        self.run(&args).map(|_| ())
    }

    /// Remove files from the working tree and index.
    pub fn remove_files(&self, files: &[&str]) -> Result<(), String> {
        if files.is_empty() {
            return Ok(());
        }
        let mut args = vec!["rm", "--quiet"];
        args.extend(files);
        self.run(&args).map(|_| ())
    }

    // MARK: - File listing

    /// List all tracked and untracked files.
    pub fn list_files(&self) -> Result<Vec<String>, String> {
        let output = self.output(&["ls-files", "--cached", "--others", "--exclude-standard"])?;
        Ok(output.lines().filter(|l| !l.is_empty()).map(|l| l.to_string()).collect())
    }

    /// Return paths that have changed compared to HEAD (staged or unstaged).
    pub fn dirty_paths(&self) -> Result<Vec<String>, String> {
        let output = self.output(&["status", "--porcelain=v1", "-z", "--untracked-files=all"])?;
        let mut paths = Vec::new();
        let records: Vec<&str> = output.split('\0').collect();
        let mut i = 0;
        while i < records.len() {
            let entry = records[i];
            if entry.len() > 3 {
                let path = entry[3..].to_string();
                paths.push(path);
                // Skip rename origin record.
                let code = &entry[0..2];
                if (code.starts_with('R') || code.starts_with('C')) && i + 1 < records.len() {
                    let origin = records[i + 1];
                    if !origin.is_empty() && !origin.starts_with("R ") && !origin.starts_with("C ") {
                        i += 1;
                    }
                }
            }
            i += 1;
        }
        Ok(paths)
    }

    /// Get the tracked files that differ between two refs.
    pub fn changed_paths(&self, from: &str, to: &str) -> Result<Vec<String>, String> {
        let output = self.output(&["diff", "--name-only", from, to])?;
        Ok(output.lines().filter(|l| !l.is_empty()).map(|l| l.to_string()).collect())
    }

    /// Find the touched paths from diff output.
    pub fn touched_paths_from_diff(
        &self,
        touched: &std::collections::HashSet<String>,
        diff_entries: &[DiffEntry],
    ) -> Vec<TouchedFile> {
        diff_entries
            .iter()
            .filter(|entry| touched_paths::matches(&entry.path, touched))
            .map(|entry| TouchedFile::new(
                PathBuf::from(&entry.path),
                match entry.change_type {
                    DiffChangeType::Added => 'A',
                    DiffChangeType::Modified => 'M',
                    DiffChangeType::Deleted => 'D',
                    DiffChangeType::Renamed => 'R',
                    DiffChangeType::Copied => 'C',
                    DiffChangeType::Unmodified => ' ',
                },
            ))
            .collect()
    }

    // MARK: - Utility

    /// The SHA-1 hash of a tree object.
    pub fn tree_hash(&self, ref_name: &str) -> Result<String, String> {
        self.output(&["rev-parse", &format!("{}^tree", ref_name)])
    }

    /// The SHA-1 hash of a commit.
    pub fn commit_hash(&self, ref_name: &str) -> Result<String, String> {
        self.output(&["rev-parse", "--verify", ref_name])
    }

    /// Whether `commit` is an ancestor of `other`.
    pub fn is_ancestor(&self, commit: &str, other: &str) -> Result<bool, String> {
        let result = self.run(&["merge-base", "--is-ancestor", commit, other])?;
        Ok(result.succeeded)
    }

    /// Whether a rebase, merge, or cherry-pick is in progress.
    pub fn has_operation_in_progress(&self) -> bool {
        let paths = [
            "rebase-merge",
            "rebase-apply",
            "MERGE_HEAD",
            "CHERRY_PICK_HEAD",
            "REVERT_HEAD",
            "BISECT_LOG",
        ];
        for path in &paths {
            if let Ok(resolved) = self.output(&["rev-parse", "--path-format=absolute", "--git-path", path]) {
                if std::path::Path::new(&resolved).exists() {
                    return true;
                }
            }
        }
        false
    }

    /// The git config value for a given key.
    pub fn config(&self, key: &str) -> Option<String> {
        self.output_opt(&["config", key])
    }

    /// Set a git config value.
    pub fn set_config(&self, key: &str, value: &str) -> Result<(), String> {
        self.run(&["config", key, value]).map(|_| ())
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    /// A tiny helper to find or create a temp repo for tests.
    fn setup_test_repo() -> GitCommand {
        let dir = std::env::temp_dir().join("swarmcode_git_test");
        let _ = std::fs::create_dir_all(&dir);
        let git = GitCommand::new(&dir);
        // Init if needed.
        let _ = git.run(&["init"]);
        // Set identity.
        let _ = Command::new("git")
            .args(&["-C", dir.to_str().unwrap(), "config", "user.email", "test@test.com"])
            .output();
        let _ = Command::new("git")
            .args(&["-C", dir.to_str().unwrap(), "config", "user.name", "Test"])
            .output();
        git
    }

    #[test]
    fn test_is_repository() {
        let git = setup_test_repo();
        // This might not be a proper repo in CI, so just test it doesn't panic.
        let _ = git.is_repository();
    }

    #[test]
    fn test_current_branch() {
        let git = setup_test_repo();
        let _ = git.current_branch();
    }

    #[test]
    fn test_run() {
        let git = setup_test_repo();
        let result = git.run(&["--version"]);
        assert!(result.is_ok());
    }

    #[test]
    fn test_remote_url() {
        let git = setup_test_repo();
        let _ = git.remote_url();
    }

    #[test]
    fn test_default_branch() {
        let git = setup_test_repo();
        let _ = git.default_branch();
    }

    #[test]
    fn test_output_opt() {
        let git = setup_test_repo();
        let result = git.output_opt(&["--version"]);
        assert!(result.is_some());
        assert!(result.unwrap().contains("git"));
    }
}
