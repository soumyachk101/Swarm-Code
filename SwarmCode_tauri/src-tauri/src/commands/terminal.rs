use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use tauri::{AppHandle, Emitter, State};

use crate::types::{TerminalSession, TerminalStream};
use crate::store::AppStore;

pub struct TerminalState {
    pub sessions: HashMap<Uuid, TerminalSessionInternal>,
    pub stdin_tx: HashMap<Uuid, tokio::sync::mpsc::UnboundedSender<String>>,
}

impl Default for TerminalState {
    fn default() -> Self {
        Self::new()
    }
}

impl TerminalState {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            stdin_tx: HashMap::new(),
        }
    }
}

pub struct TerminalSessionInternal {
    pub session: TerminalSession,
    pub child: Option<std::process::Child>,
}

#[tauri::command]
pub async fn create_terminal_session(
    command: Option<String>,
    cwd: Option<String>,
    app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<TerminalSession, String> {
    let working_dir = cwd.unwrap_or_else(|| {
        std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| ".".to_string())
    });

    let session_id = Uuid::new_v4();
    let cmd_str = command.clone().unwrap_or_else(|| {
        if cfg!(target_os = "windows") {
            "cmd".to_string()
        } else {
            "bash".to_string()
        }
    });
    let _child = if cfg!(target_os = "windows") {
        std::process::Command::new("cmd")
            .args(["/C", &cmd_str])
            .current_dir(&working_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn terminal: {e}"))?
    } else {
        std::process::Command::new("bash")
            .args(["-c", &cmd_str])
            .current_dir(&working_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn terminal: {e}"))?
    };

    let session = TerminalSession {
        id: session_id,
        thread_id: Uuid::nil(),
        directory: working_dir.clone(),
        title: cmd_str.chars().take(40).collect(),
        is_running: true,
        cols: 80,
        rows: 24,
    };

    let _ = app.emit(
        "terminal_session_created",
        serde_json::json!({
            "session_id": session_id.to_string(),
            "directory": working_dir,
            "command": cmd_str,
        }),
    );

    Ok(session)
}

#[tauri::command]
pub async fn execute_in_terminal(
    command: String,
    cwd: Option<String>,
    app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<TerminalSession, String> {
    create_terminal_session(Some(command), cwd, app, _state).await
}

#[tauri::command]
pub async fn write_terminal_input(
    _session_id: String,
    _input: String,
    _app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn send_terminal_signal(
    _session_id: String,
    _signal: String,
    _app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn resize_terminal(
    _session_id: String,
    _cols: u16,
    _rows: u16,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn close_terminal_session(
    _id: String,
    _app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn close_terminal(
    _session_id: String,
    _app: AppHandle,
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn get_terminal_sessions(
    _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<TerminalSession>, String> {
    Ok(Vec::new())
}

pub fn emit_terminal_output_internal(
    app: &AppHandle,
    session_id: Uuid,
    output: &str,
    stream: TerminalStream,
) {
    let _ = app.emit(
        "terminal_output",
        serde_json::json!({
            "session_id": session_id.to_string(),
            "output": output,
            "stream": stream,
        }),
    );
}
