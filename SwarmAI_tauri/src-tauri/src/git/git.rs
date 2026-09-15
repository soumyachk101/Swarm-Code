use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
 pub branch: Option<String>,
 pub upstream: Option<String>,
 pub ahead: u32,
 pub behind: u32,
 pub changed_files: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranch {
 pub name: String,
 pub is_current: bool,
 pub upstream: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitShellResult {
 pub succeeded: bool,
 pub exit_code: i32,
 pub output: String,
 pub error_output: String,
}

pub struct Git {
 pub directory: PathBuf,
}

impl Git {
 pub fn new(path: &str) -> Self {
 Self {
 directory: PathBuf::from(path),
 }
 }

 pub fn run(&self, args: &[&str]) -> Result<GitShellResult, String> {
 let mut cmd = Command::new("git");
 cmd.current_dir(&self.directory);
 cmd.args(args);
 cmd.env("GIT_TERMINAL_PROMPT", "0");
 cmd.env("GIT_OPTIONAL_LOCKS", "0");

 let output = cmd.output().map_err(|e| e.to_string())?;

 Ok(GitShellResult {
 succeeded: output.status.success(),
 exit_code: output.status.code().unwrap_or(-1),
 output: String::from_utf8_lossy(&output.stdout).to_string(),
 error_output: String::from_utf8_lossy(&output.stderr).to_string(),
 })
 }

 pub fn is_repository(&self) -> bool {
 self.run(&["rev-parse", "--is-inside-work-tree"])
 .map(|r| r.output.trim() == "true")
 .unwrap_or(false)
 }

 pub fn has_commits(&self) -> bool {
 self.run(&["rev-parse", "--verify", "--quiet", "HEAD"])
 .map(|r| r.succeeded)
 .unwrap_or(false)
 }

 pub fn current_branch(&self) -> Option<String> {
 self.run(&["rev-parse", "--abbrev-ref", "HEAD"])
 .ok()
 .map(|r| r.output.trim().to_string())
 .filter(|s| !s.is_empty())
 }

 pub fn head_commit(&self) -> Option<String> {
 self.run(&["rev-parse", "HEAD"])
 .ok()
 .map(|r| r.output.trim().to_string())
 .filter(|s| !s.is_empty())
 }
}
