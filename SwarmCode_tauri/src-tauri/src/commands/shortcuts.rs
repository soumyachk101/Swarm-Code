use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::types::Shortcut;
use crate::store::AppStore;

// ---------------------------------------------------------------------------
// Known action names (mirrors the Swift AppShortcut enum)
// ---------------------------------------------------------------------------
pub const SHORTCUT_NEW_THREAD: &str = "new_thread";
pub const SHORTCUT_NEW_WORKTREE: &str = "new_worktree_thread";
pub const SHORTCUT_ADD_PROJECT: &str = "add_project";
pub const SHORTCUT_STOP_TURN: &str = "stop_turn";
pub const SHORTCUT_QUEUE_CHAT: &str = "queue_chat";
pub const SHORTCUT_TOGGLE_PLAN: &str = "toggle_plan_mode";
pub const SHORTCUT_PREV_THREAD: &str = "previous_thread";
pub const SHORTCUT_NEXT_THREAD: &str = "next_thread";
pub const SHORTCUT_FINISH_THREAD: &str = "finish_thread";
pub const SHORTCUT_COMMAND_PALETTE: &str = "command_palette";
pub const SHORTCUT_TOGGLE_SIDEBAR: &str = "toggle_sidebar";
pub const SHORTCUT_TOGGLE_TERMINAL: &str = "toggle_terminal";
pub const SHORTCUT_TOGGLE_CHANGES: &str = "toggle_changes";
pub const SHORTCUT_TOGGLE_ACTIVITY: &str = "toggle_activity_view";
pub const SHORTCUT_SHOW_MAIN: &str = "show_main_window";
pub const SHORTCUT_OPEN_SETTINGS: &str = "open_settings";

// Default key bindings
fn default_chord(action: &str) -> Option<(String, Vec<String>)> {
 match action {
 SHORTCUT_NEW_THREAD => Some(("t".into(), vec!["command".into()])),
 SHORTCUT_NEW_WORKTREE => Some(("t".into(), vec!["shift".into(), "command".into()])),
 SHORTCUT_ADD_PROJECT => Some(("o".into(), vec!["command".into()])),
 SHORTCUT_STOP_TURN => Some((".".into(), vec!["command".into()])),
 SHORTCUT_QUEUE_CHAT => Some(("return".into(), vec!["command".into()])),
 SHORTCUT_TOGGLE_PLAN => Some(("p".into(), vec!["shift".into(), "command".into()])),
 SHORTCUT_PREV_THREAD => Some(("up".into(), vec!["option".into(), "command".into()])),
 SHORTCUT_NEXT_THREAD => Some(("down".into(), vec!["option".into(), "command".into()])),
 SHORTCUT_FINISH_THREAD => Some(("delete".into(), vec!["shift".into(), "command".into()])),
 SHORTCUT_COMMAND_PALETTE => Some(("k".into(), vec!["command".into(), "shift".into()])),
 SHORTCUT_TOGGLE_SIDEBAR => Some(("b".into(), vec!["control".into(), "command".into()])),
 SHORTCUT_TOGGLE_TERMINAL => Some(("j".into(), vec!["command".into()])),
 SHORTCUT_TOGGLE_CHANGES => Some(("d".into(), vec!["command".into()])),
 SHORTCUT_TOGGLE_ACTIVITY => Some(("u".into(), vec!["option".into(), "command".into()])),
 SHORTCUT_SHOW_MAIN => Some(("h".into(), vec!["command".into(), "shift".into()])),
 SHORTCUT_OPEN_SETTINGS => Some((",".into(), vec!["command".into()])),
 _ => None,
 }
}

#[tauri::command]
pub async fn register_shortcut(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 shortcut: String,
 action: String,
) -> Result<(), String> {
 let _id = Uuid::new_v4(); // In production: register with OS-level global shortcut API

 // In a real implementation, this would:
 // 1. Register the shortcut with the OS (via tauri-plugin-global-shortcut or platform APIs)
 // 2. Persist the mapping in the store's settings
 // 3. Wire up the Tauri event to fire the action

 Ok(())
}

#[tauri::command]
pub async fn unregister_shortcut(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
 action: String,
) -> Result<(), String> {
 // In a real implementation, this would remove the OS-level binding
 // and clear the persisted mapping.
 Ok(())
}

#[tauri::command]
pub async fn get_registered_shortcuts(
 _state: tauri::State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<Shortcut>, String> {
 let actions = [
 SHORTCUT_NEW_THREAD,
 SHORTCUT_NEW_WORKTREE,
 SHORTCUT_ADD_PROJECT,
 SHORTCUT_STOP_TURN,
 SHORTCUT_QUEUE_CHAT,
 SHORTCUT_TOGGLE_PLAN,
 SHORTCUT_PREV_THREAD,
 SHORTCUT_NEXT_THREAD,
 SHORTCUT_FINISH_THREAD,
 SHORTCUT_COMMAND_PALETTE,
 SHORTCUT_TOGGLE_SIDEBAR,
 SHORTCUT_TOGGLE_TERMINAL,
 SHORTCUT_TOGGLE_CHANGES,
 SHORTCUT_TOGGLE_ACTIVITY,
 SHORTCUT_SHOW_MAIN,
 SHORTCUT_OPEN_SETTINGS,
 ];

 let shortcuts: Vec<Shortcut> = actions
 .iter()
 .filter_map(|action| {
 default_chord(action).map(|(key, mods)| {
 let display = format!(
 "{}{}",
 mods.iter().map(|m| match m.as_str() {
 "command" => "Cmd+",
 "control" => "Ctrl+",
 "option" => "Alt+",
 "shift" => "Shift+",
 _ => m.as_str(),
 }).collect::<String>(),
 key,
 );
 Shortcut {
 action: action.to_string(),
 key: key.clone(),
 modifiers: mods,
 display,
 }
 })
 })
 .collect();

 Ok(shortcuts)
}
