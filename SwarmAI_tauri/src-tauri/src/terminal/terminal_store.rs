//! TerminalStore - manages pseudo-terminal sessions for interactive threads.
//!
//! Stub implementation for Tauri compilation. Terminal functionality is
//! implemented in the frontend and via the commands in
//! src/commands/terminal.rs using std::process::Command.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TerminalSize {
 pub cols: u16,
 pub rows: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalState {
 Active,
 Detached,
 Closed,
}

impl Default for TerminalState {
 fn default() -> Self {
 Self::Active
 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionKind {
 Agent { thread_id: Uuid, pair_id: Uuid },
 Winch { pair_id: Uuid },
}

impl SessionKind {
 pub fn thread_id(&self) -> Option<Uuid> {
 match self {
 Self::Agent { thread_id, .. } => Some(*thread_id),
 Self::Winch { .. } => None,
 }
 }

 pub fn pair_id(&self) -> Uuid {
 match self {
 Self::Agent { pair_id, .. } => *pair_id,
 Self::Winch { pair_id } => *pair_id,
 }
 }
}

#[derive(Debug)]
pub struct PairedSession {
 pub id: Uuid,
 pub name: Option<String>,
 pub command: Vec<String>,
 pub kind: SessionKind,
 pub size: RwLock<TerminalSize>,
 pub state: RwLock<TerminalState>,
 pub pid: Option<u32>,
}

impl PairedSession {
 pub fn new(
 id: Uuid,
 name: Option<String>,
 command: Vec<String>,
 kind: SessionKind,
 ) -> Self {
 let size = TerminalSize { cols: 80, rows: 24 };
 Self {
 id,
 name,
 command,
 kind,
 size: RwLock::new(size),
 state: RwLock::new(TerminalState::Active),
 pid: None,
 }
 }

 pub fn is_for_thread(&self, thread_id: Uuid) -> bool {
 self.kind.thread_id() == Some(thread_id)
 }
}

#[derive(Debug, Clone)]
pub enum SessionEvent {
 SessionStarted { session_id: Uuid, pid: u32 },
 SessionExited { session_id: Uuid },
 SessionOutput { session_id: Uuid, data: Vec<u8> },
 SessionResized { session_id: Uuid, size: TerminalSize },
}

#[derive(Debug, thiserror::Error)]
pub enum TerminalError {
 #[error("terminal subsystem is disabled")]
 Disabled,

 #[error("terminal session not found: {0}")]
 NotFound(Uuid),

 #[error("PTY spawn failed: {0}")]
 PtySpawn(String),

 #[error("terminal operation failed: {0}")]
 Other(String),

 #[error("unsupported: {0}")]
 Unsupported(String),
}

// ---------------------------------------------------------------------------
// TerminalStore
// ---------------------------------------------------------------------------

pub struct TerminalStore {
 sessions: RwLock<HashMap<Uuid, Arc<PairedSession>>>,
 enabled: RwLock<bool>,
}

impl TerminalStore {
 pub fn new() -> Self {
 Self {
 sessions: RwLock::new(HashMap::new()),
 enabled: RwLock::new(true),
 }
 }

 pub async fn is_enabled(&self) -> bool {
 *self.enabled.read().await
 }

 pub async fn set_enabled(&self, value: bool) {
 let mut guard = self.enabled.write().await;
 *guard = value;
 }

 pub async fn spawn_agent(
 &self,
 thread_id: Uuid,
 command: Vec<String>,
 size: TerminalSize,
 ) -> Result<Arc<PairedSession>, TerminalError> {
 let pair_id = Uuid::new_v4();
 let session_id = Uuid::new_v4();
 let kind = SessionKind::Agent { thread_id, pair_id };

 let session = Arc::new(PairedSession::new(
 session_id,
 Some(format!("agent-{}", thread_id)),
 command,
 kind,
 ));

 let mut sessions = self.sessions.write().await;
 sessions.insert(session_id, session.clone());
 Ok(session)
 }

 pub async fn spawn_winch(
 &self,
 pair_id: Uuid,
 command: Vec<String>,
 ) -> Result<Arc<PairedSession>, TerminalError> {
 let session_id = Uuid::new_v4();
 let kind = SessionKind::Winch { pair_id };

 let session = Arc::new(PairedSession::new(
 session_id,
 Some(format!("winch-{}", pair_id)),
 command,
 kind,
 ));

 let mut sessions = self.sessions.write().await;
 sessions.insert(session_id, session.clone());
 Ok(session)
 }

 pub async fn detach(&self, session_id: Uuid) -> Result<(), TerminalError> {
 let sessions = self.sessions.read().await;
 if let Some(s) = sessions.get(&session_id) {
 let mut state = s.state.write().await;
 *state = TerminalState::Detached;
 Ok(())
 } else {
 Err(TerminalError::NotFound(session_id))
 }
 }

 pub async fn attach(&self, session_id: Uuid) -> Result<(), TerminalError> {
 let sessions = self.sessions.read().await;
 if let Some(s) = sessions.get(&session_id) {
 let mut state = s.state.write().await;
 *state = TerminalState::Active;
 Ok(())
 } else {
 Err(TerminalError::NotFound(session_id))
 }
 }

 pub async fn resize(&self, session_id: Uuid, size: TerminalSize) -> Result<(), TerminalError> {
 let sessions = self.sessions.read().await;
 if let Some(s) = sessions.get(&session_id) {
 let mut sz = s.size.write().await;
 *sz = size;
 Ok(())
 } else {
 Err(TerminalError::NotFound(session_id))
 }
 }

 pub async fn close(&self, session_id: Uuid) -> Result<(), TerminalError> {
 let mut sessions = self.sessions.write().await;
 sessions.remove(&session_id);
 Ok(())
 }

 pub async fn close_for_thread(&self, thread_id: Uuid) {
 let mut sessions = self.sessions.write().await;
 let to_close: Vec<Uuid> = sessions
 .iter()
 .filter(|(_, s)| s.is_for_thread(thread_id))
 .map(|(id, _)| *id)
 .collect();
 for id in to_close {
 sessions.remove(&id);
 }
 }

 pub async fn is_running_for(&self, thread_id: Uuid) -> bool {
 let sessions = self.sessions.read().await;
 for s in sessions.values() {
 if s.is_for_thread(thread_id) {
 let state = s.state.read().await;
 if matches!(*state, TerminalState::Active) {
 return true;
 }
 }
 }
 false
 }

 pub async fn get(&self, session_id: Uuid) -> Option<Arc<PairedSession>> {
 let sessions = self.sessions.read().await;
 sessions.get(&session_id).cloned()
 }

 pub async fn all(&self) -> Vec<Arc<PairedSession>> {
 let sessions = self.sessions.read().await;
 sessions.values().cloned().collect()
 }

 pub async fn shutdown(&self) {
 let mut sessions = self.sessions.write().await;
 sessions.clear();
 }
}

impl Default for TerminalStore {
 fn default() -> Self {
 Self::new()
 }
}
