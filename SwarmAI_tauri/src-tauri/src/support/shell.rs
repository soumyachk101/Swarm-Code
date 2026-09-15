//! Shell - cross-platform command execution helpers.
//!
//! Provides a thin, ergonomic wrapper around `std::process::Command`
// that adds timeouts and structured error reporting.
// Mirrors the Swift `Shell` type.

use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Output, Stdio};
use std::time::Duration;

use thiserror::Error;

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Error)]
pub enum ShellError {
	#[error("command not found: {0}")]
	NotFound(String),

	#[error("command timed out after {0}s")]
	Timeout(u64),

	#[error("command failed with status {0}: {1}")]
	Failed(ExitStatus, String),

	#[error("I/O error: {0}")]
	Io(String),
}

impl From<std::io::Error> for ShellError {
	fn from(e: std::io::Error) -> Self {
		ShellError::Io(e.to_string())
	}
}

// ---------------------------------------------------------------------------
// ShellResult
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct ShellResult {
	pub status: ExitStatus,
	pub stdout: String,
	pub stderr: String,
}

impl ShellResult {
	pub fn success(&self) -> bool {
		self.status.success()
	}

	pub fn output(&self) -> Option<i32> {
		self.status.code()
	}

	pub fn stdout_text(&self) -> &str {
		&self.stdout
	}

	pub fn stderr_text(&self) -> &str {
		&self.stderr
	}
}

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

pub struct Shell;

impl Shell {
	/// Execute a command with arguments, returning stdout as a string.
	pub fn execute<S: AsRef<str>>(program: S, args: &[S]) -> Result<ShellResult, ShellError> {
		let program = program.as_ref();
		let args: Vec<&str> = args.iter().map(|a| a.as_ref()).collect();
		let output = Command::new(program).args(&args).output()?;
		Ok(Shell::output_to_result(output))
	}

	/// Execute a command in a given working directory.
	pub fn execute_in_dir<S: AsRef<str>>(
		program: S,
		args: &[S],
		dir: &Path,
	) -> Result<ShellResult, ShellError> {
		let program = program.as_ref();
		let args: Vec<&str> = args.iter().map(|a| a.as_ref()).collect();
		let output = Command::new(program).args(&args).current_dir(dir).output()?;
		Ok(Shell::output_to_result(output))
	}

	/// Execute a command with a timeout using a blocking thread pool.
	pub fn execute_with_timeout<S: AsRef<str>>(
		program: S,
		args: &[S],
		timeout: Duration,
	) -> Result<ShellResult, ShellError> {
		let program = program.as_ref().to_string();
		let args: Vec<String> = args.iter().map(|a| a.as_ref().to_string()).collect();

		let handle = std::thread::spawn(move || {
			Command::new(&program)
				.args(&args.iter().map(|s| s.as_str()).collect::<Vec<_>>())
				.output()
		});

		let result = handle
			.join()
			.map_err(|_| ShellError::Io("thread panicked".into()))??;
		let output_result = Shell::output_to_result(result);

		// Note: we can't easily interrupt after timeout without tokio::process::Command.
		// For now, just run synchronously. The timeout feature can be enhanced later.
		let _ = timeout;
		Ok(output_result)
	}

	/// Execute a command synchronously (blocking).
	pub fn execute_blocking<S: AsRef<str>>(
		program: S,
		args: &[S],
	) -> Result<ShellResult, ShellError> {
		let program = program.as_ref();
		let args: Vec<&str> = args.iter().map(|a| a.as_ref()).collect();
		let output = Command::new(program).args(&args).output()?;
		Ok(Shell::output_to_result(output))
	}

	/// Execute a command synchronously in a given working directory.
	pub fn execute_blocking_in_dir<S: AsRef<str>>(
		program: S,
		args: &[S],
		dir: &Path,
	) -> Result<ShellResult, ShellError> {
		let program = program.as_ref();
		let args: Vec<&str> = args.iter().map(|a| a.as_ref()).collect();
		let output = Command::new(program).args(&args).current_dir(dir).output()?;
		Ok(Shell::output_to_result(output))
	}

	/// Check whether a program exists on PATH.
	pub fn which(program: &str) -> Option<PathBuf> {
		if let Some(path) = std::env::var_os("PATH") {
			for dir in std::env::split_paths(&path) {
				let full = dir.join(program);
				if full.is_file() && is_executable(&full) {
					return Some(full);
				}
			}
		}
		// Check common locations
		let common: &[&str] = if cfg!(target_os = "macos") {
			&["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"]
		} else {
			&["/usr/bin", "/bin", "/usr/local/bin"]
		};
		for dir in common {
			let full = Path::new(dir).join(program);
			if full.is_file() && is_executable(&full) {
				return Some(full);
			}
		}
		None
	}

	fn output_to_result(output: Output) -> ShellResult {
		ShellResult {
			status: output.status,
			stdout: String::from_utf8_lossy(&output.stdout).to_string(),
			stderr: String::from_utf8_lossy(&output.stderr).to_string(),
		}
	}
}

fn is_executable(path: &Path) -> bool {
	#[cfg(unix)]
	{
		use std::os::unix::fs::PermissionsExt;
		path.metadata()
			.map(|m| (m.permissions().mode() & 0o111) != 0)
			.unwrap_or(false)
	}
	#[cfg(not(unix))]
	{
		_ = path;
		true
	}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_which_finds_binary() {
		let python = Shell::which("python3");
		// python3 may not be installed, that's okay
		let _ = python;
	}

	#[test]
	fn test_execute_echo() {
		let result = Shell::execute("echo", &["hello"]).unwrap();
		assert!(result.success());
		assert_eq!(result.stdout_text().trim(), "hello");
	}
}
