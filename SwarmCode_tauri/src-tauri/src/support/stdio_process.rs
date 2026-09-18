//! StdioProcess - manages child processes (AI CLI tools) with stdin/stdout/stderr.
//!
//! Mirrors the Swift `StdioProcess` class: wraps a spawned subprocess,
//! manages its I/O pipes, and provides clean lifecycle management.
//! Uses `tokio::process` for async I/O.

use std::collections::HashMap;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, Command};
use tokio::sync::{mpsc, RwLock};
use tokio::task::JoinHandle;

use crate::support::shell::ShellError;

// ---------------------------------------------------------------------------
// ProcessEvent
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum ProcessEvent {
	StdoutLine { pid: u32, line: String },
	StderrLine { pid: u32, line: String },
	Exited { pid: u32, exit_code: Option<i32> },
}

// ---------------------------------------------------------------------------
// StdioProcess
// ---------------------------------------------------------------------------

pub struct StdioProcess {
	pub(crate) pid: Option<u32>,
	pub(crate) name: String,
	pub(crate) args: Vec<String>,
	pub(crate) working_directory: Option<String>,
	pub(crate) env: HashMap<String, String>,
	pub(crate) child: Option<Child>,
	pub(crate) stdin: Option<ChildStdin>,
	pub(crate) _event_tx: Option<mpsc::UnboundedSender<ProcessEvent>>,
	pub(crate) _tasks: Vec<JoinHandle<()>>,
}

impl StdioProcess {
	/// Spawn a new process.
	pub fn spawn(
		name: impl Into<String>,
		args: Vec<String>,
		working_directory: Option<String>,
		env: HashMap<String, String>,
	) -> Result<Self, ShellError> {
		let name = name.into();
		let mut cmd = Command::new(&name);
		cmd
			.args(&args)
			.stdin(Stdio::piped())
			.stdout(Stdio::piped())
			.stderr(Stdio::piped())
			.kill_on_drop(true);

		if let Some(ref wd) = working_directory {
			cmd.current_dir(wd);
		}

		for (key, value) in &env {
			cmd.env(key, value);
		}

		let mut child = cmd.spawn()?;
		let pid = child.id();
		let stdin = child.stdin.take();
		let stdout = child.stdout.take();
		let stderr = child.stderr.take();

		let (event_tx, event_rx) = mpsc::unbounded_channel::<ProcessEvent>();
		let mut tasks: Vec<JoinHandle<()>> = Vec::new();

		if let Some(stdout_handle) = stdout {
			let tx = event_tx.clone();
			tasks.push(tokio::spawn(async move {
				let reader = BufReader::new(stdout_handle);
				let mut lines = reader.lines();
				loop {
					match lines.next_line().await {
						Ok(Some(line)) => {
							let _ = tx.send(ProcessEvent::StdoutLine {
								pid: pid.unwrap_or(0),
								line,
							});
						}
						Ok(None) | Err(_) => break,
					}
				}
			}));
		}

		if let Some(stderr_handle) = stderr {
			let tx = event_tx.clone();
			tasks.push(tokio::spawn(async move {
				let reader = BufReader::new(stderr_handle);
				let mut lines = reader.lines();
				loop {
					match lines.next_line().await {
						Ok(Some(line)) => {
							let _ = tx.send(ProcessEvent::StderrLine {
								pid: pid.unwrap_or(0),
								line,
							});
						}
						Ok(None) | Err(_) => break,
					}
				}
			}));
		}

		// Monitor exit
		if let Some(exit_pid) = pid {
			let tx = event_tx.clone();
			tasks.push(tokio::spawn(async move {
				let mut child_c = child;
				match child_c.wait().await {
					Ok(status) => {
						let _ = tx.send(ProcessEvent::Exited {
							pid: exit_pid,
							exit_code: status.code(),
						});
					}
					Err(_) => {}
				}
				drop(event_rx);
			}));
		} else {
			drop(event_rx);
		}

		Ok(Self {
			pid,
			name,
			args,
			working_directory,
			env,
			child: None,
			stdin,
			_event_tx: Some(event_tx),
			_tasks: tasks,
		})
	}

	/// Create an empty process handle (for stubbing).
	pub fn new(name: impl Into<String>, args: Vec<String>) -> Self {
		Self {
			pid: None,
			name: name.into(),
			args,
			working_directory: None,
			env: HashMap::new(),
			child: None,
			stdin: None,
			_event_tx: None,
			_tasks: Vec::new(),
		}
	}

	/// Write a line to stdin.
	pub async fn write_line(&mut self, line: &str) -> Result<(), ShellError> {
		if let Some(ref mut stdin) = self.stdin {
			stdin.write_all(line.as_bytes()).await?;
			stdin.write_all(b"\n").await?;
			stdin.flush().await?;
			Ok(())
		} else {
			Err(ShellError::Io("stdin not available".to_string()))
		}
	}

	/// Close stdin.
	pub async fn close_stdin(&mut self) -> Result<(), ShellError> {
		self.stdin = None;
		Ok(())
	}

	/// Send a signal to the process.
	pub async fn interrupt(&mut self) -> Result<(), ShellError> {
		if let Some(ref mut child) = self.child {
			child.start_kill().ok();
		}
		Ok(())
	}

	/// Check if the process is still running.
	pub async fn is_running(&mut self) -> Result<bool, ShellError> {
		match self.child.as_mut() {
			Some(child) => Ok(child.try_wait()?.is_none()),
			None => Ok(false),
		}
	}

	/// Wait for the process to exit and return the exit code.
	pub async fn wait(&mut self) -> Result<Option<i32>, ShellError> {
		if let Some(mut child) = self.child.take() {
			let status = child.wait().await?;
			Ok(status.code())
		} else {
			Ok(None)
		}
	}

	/// Kill the process.
	pub async fn terminate(&mut self) -> Result<(), ShellError> {
		if let Some(mut child) = self.child.take() {
			child.kill().await?;
		}
		Ok(())
	}

	/// Terminate after a timeout.
	pub async fn terminate_after_timeout(
		&mut self,
		timeout: tokio::time::Duration,
	) -> Result<Option<i32>, ShellError> {
		match tokio::time::timeout(timeout, self.wait()).await {
			Ok(result) => result,
			Err(_) => {
				self.terminate().await?;
				Ok(Some(-1))
			}
		}
	}

	/// Get the PID of the spawned process.
	pub fn pid(&self) -> Option<u32> {
		self.pid
	}

	/// Get the process name.
	pub fn name(&self) -> &str {
		&self.name
	}
}

impl Drop for StdioProcess {
	fn drop(&mut self) {
		if let Some(mut child) = self.child.take() {
			child.start_kill().ok();
		}
		// Abort all spawned tasks
		for handle in self._tasks.drain(..) {
			handle.abort();
		}
	}
}

// ---------------------------------------------------------------------------
// ProcessManager - registry of active processes
// ---------------------------------------------------------------------------

pub struct ProcessManager {
	processes: RwLock<HashMap<u32, StdioProcess>>,
}

impl ProcessManager {
	pub fn new() -> Self {
		Self {
			processes: RwLock::new(HashMap::new()),
		}
	}

	pub async fn spawn(
		&self,
		name: impl Into<String>,
		args: Vec<String>,
		cwd: Option<String>,
		env: HashMap<String, String>,
	) -> Result<u32, ShellError> {
		let process = StdioProcess::spawn(name, args, cwd, env)?;
		let pid = process.pid.unwrap_or(0);
		self.processes.write().await.insert(pid, process);
		Ok(pid)
	}

	pub async fn get(&self, pid: u32) -> Option<std::sync::Arc<RwLock<StdioProcess>>> {
		let processes = self.processes.read().await;
		processes.get(&pid).map(|p| {
			std::sync::Arc::new(RwLock::new(StdioProcess {
				pid: p.pid,
				name: p.name.clone(),
				args: p.args.clone(),
				working_directory: p.working_directory.clone(),
				env: p.env.clone(),
				child: None,
				stdin: None,
				_event_tx: None,
				_tasks: Vec::new(),
			}))
		})
	}

	pub async fn remove(&self, pid: u32) {
		self.processes.write().await.remove(&pid);
	}

	pub async fn shutdown_all(&self) {
		let mut processes = self.processes.write().await;
		for (_, mut p) in processes.drain() {
			let _ = p.terminate().await;
		}
	}
}

impl Default for ProcessManager {
	fn default() -> Self {
		Self::new()
	}
}
