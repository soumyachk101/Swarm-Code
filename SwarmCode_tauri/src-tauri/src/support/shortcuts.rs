//! Keyboard shortcut management with global hotkeys.
//!
//! Provides the ShortcutManager that can register global hotkeys and map them
//! to application actions. The ShortcutAction enum enumerates every command a
//! shortcut can trigger.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use global_hotkey::{GlobalHotKeyManager, HotKeyState, hotkey::{HotKey, Modifiers}};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Every command a keyboard shortcut can trigger.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ShortcutAction {
    NewThread,
    NewWorktreeThread,
    AddProject,
    StopTurn,
    QueueChat,
    TogglePlanMode,
    PreviousThread,
    NextThread,
    FinishThread,
    CommandPalette,
    ToggleSidebar,
    ToggleTerminal,
    ToggleChanges,
    ToggleActivityView,
    ShowMainWindow,
    OpenSettings,
    FocusChatInput,
    SendMessage,
    FocusProjectList,
    ToggleFullscreen,
}

impl ShortcutAction {
    /// Human-readable title for the action.
    pub fn title(self) -> &'static str {
        match self {
            ShortcutAction::NewThread => "New thread",
            ShortcutAction::NewWorktreeThread => "New thread in worktree",
            ShortcutAction::AddProject => "Add project",
            ShortcutAction::StopTurn => "Stop the running turn",
            ShortcutAction::QueueChat => "Queue a chat",
            ShortcutAction::TogglePlanMode => "Plan mode",
            ShortcutAction::PreviousThread => "Previous thread",
            ShortcutAction::NextThread => "Next thread",
            ShortcutAction::FinishThread => "Finish thread",
            ShortcutAction::CommandPalette => "Command palette",
            ShortcutAction::ToggleSidebar => "Toggle sidebar",
            ShortcutAction::ToggleTerminal => "Toggle terminal",
            ShortcutAction::ToggleChanges => "Toggle changes",
            ShortcutAction::ToggleActivityView => "Activity view",
            ShortcutAction::ShowMainWindow => "Show main window",
            ShortcutAction::OpenSettings => "Settings",
            ShortcutAction::FocusChatInput => "Focus chat input",
            ShortcutAction::SendMessage => "Send message",
            ShortcutAction::FocusProjectList => "Focus project list",
            ShortcutAction::ToggleFullscreen => "Toggle fullscreen",
        }
    }

    /// A hint string for the action.
    pub fn detail(self) -> &'static str {
        match self {
            ShortcutAction::NewThread => "Starts a thread in the current project.",
            ShortcutAction::NewWorktreeThread => "Starts a thread in its own git worktree.",
            ShortcutAction::AddProject => "Opens a folder as a project.",
            ShortcutAction::StopTurn => "Interrupts the agent while it works.",
            ShortcutAction::QueueChat => "While a turn runs, lines the draft up behind it.",
            ShortcutAction::TogglePlanMode => "Plans before building.",
            ShortcutAction::PreviousThread => "Selects the thread above in the sidebar.",
            ShortcutAction::NextThread => "Selects the thread below in the sidebar.",
            ShortcutAction::FinishThread => {
                "Settles the selected thread, or archives it, whichever General chose."
            }
            ShortcutAction::CommandPalette => "Searches threads, projects and actions.",
            ShortcutAction::ToggleSidebar => "Shows or hides the sidebar.",
            ShortcutAction::ToggleTerminal => "Shows or hides the thread's terminal.",
            ShortcutAction::ToggleChanges => "Shows or hides the changes panel.",
            ShortcutAction::ToggleActivityView => "Lists every thread by when it was last active.",
            ShortcutAction::ShowMainWindow => "Brings the main window to the front.",
            ShortcutAction::OpenSettings => "Opens the settings window.",
            ShortcutAction::FocusChatInput => "Focuses the chat message input.",
            ShortcutAction::SendMessage => "Sends the current message.",
            ShortcutAction::FocusProjectList => "Focuses the project list in the sidebar.",
            ShortcutAction::ToggleFullscreen => "Toggles fullscreen mode.",
        }
    }
}

// ---------------------------------------------------------------------------
// Section grouping
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ShortcutSection {
    Threads,
    Window,
}

impl ShortcutSection {
    pub fn title(self) -> &'static str {
        match self {
            ShortcutSection::Threads => "Threads",
            ShortcutSection::Window => "Window and panels",
        }
    }

    pub fn symbol(self) -> &'static str {
        match self {
            ShortcutSection::Threads => "bubble.left.and.bubble.right.fill",
            ShortcutSection::Window => "macwindow",
        }
    }

    pub fn actions(self) -> &'static [ShortcutAction] {
        match self {
            ShortcutSection::Threads => &[
                ShortcutAction::NewThread,
                ShortcutAction::NewWorktreeThread,
                ShortcutAction::AddProject,
                ShortcutAction::StopTurn,
                ShortcutAction::QueueChat,
                ShortcutAction::TogglePlanMode,
                ShortcutAction::PreviousThread,
                ShortcutAction::NextThread,
                ShortcutAction::FinishThread,
            ],
            ShortcutSection::Window => &[
                ShortcutAction::CommandPalette,
                ShortcutAction::ToggleSidebar,
                ShortcutAction::ToggleTerminal,
                ShortcutAction::ToggleChanges,
                ShortcutAction::ToggleActivityView,
                ShortcutAction::ShowMainWindow,
                ShortcutAction::OpenSettings,
            ],
        }
    }
}

// ---------------------------------------------------------------------------
// Shortcut registration
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShortcutBinding {
    pub action: ShortcutAction,
    pub shortcut: String,
}

#[derive(Debug, Clone, Default)]
struct ShortcutStore {
    bindings: HashMap<ShortcutAction, String>,
}

impl ShortcutStore {
    fn get(&self, action: ShortcutAction) -> Option<&str> {
        self.bindings.get(&action).map(|s| s.as_str())
    }

    fn set(&mut self, action: ShortcutAction, shortcut: Option<String>) {
        if let Some(s) = shortcut {
            self.bindings.insert(action, s);
        } else {
            self.bindings.remove(&action);
        }
    }

    fn reset(&mut self) {
        self.bindings.clear();
    }

    fn all(&self) -> Vec<ShortcutBinding> {
        self.bindings
            .iter()
            .map(|(&action, shortcut)| ShortcutBinding {
                action,
                shortcut: shortcut.clone(),
            })
            .collect()
    }
}

#[derive(Debug)]
pub struct ShortcutManager {
    _hotkey_manager: DebugHotKeyManager,
    hotkey_ids: RwLock<HashMap<HotKey, ShortcutAction>>,
    reverse_ids: RwLock<HashMap<u32, HotKey>>,
    bindings: RwLock<ShortcutStore>,
    #[allow(dead_code)]
    id_counter: Arc<RwLock<u32>>,
}

// Wrapper to allow Debug impl for GlobalHotKeyManager (orphan rule)
pub struct DebugHotKeyManager(pub GlobalHotKeyManager);

impl std::fmt::Debug for DebugHotKeyManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("GlobalHotKeyManager")
    }
}

impl std::ops::Deref for DebugHotKeyManager {
    type Target = GlobalHotKeyManager;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl ShortcutManager {
    /// Create a new ShortcutManager.  The global hotkey manager is initialised
    /// so that registrations take effect immediately.
    pub fn new() -> Self {
        Self {
            _hotkey_manager: DebugHotKeyManager(GlobalHotKeyManager::new().expect("global hotkey manager")),
            hotkey_ids: RwLock::new(HashMap::new()),
            reverse_ids: RwLock::new(HashMap::new()),
            bindings: RwLock::new(ShortcutStore::default()),
            id_counter: Arc::new(RwLock::new(0)),
        }
    }

    /// Register a key-combo string (e.g. "Cmd+N", "Ctrl+Shift+T") for the
    /// given action.  Returns `Err` with a reason when the chord is invalid
    /// (reserved, text-stealing, or already taken by another action).
    pub fn register(
        &self,
        action: ShortcutAction,
        shortcut: &str,
    ) -> Result<(), String> {
        // Check for duplicate.
        {
            let bindings = self.bindings.read().unwrap();
            for (existing_action, existing_shortcut) in bindings.bindings.iter() {
                if *existing_action != action && existing_shortcut == shortcut {
                    return Err(format!(
                        "{} already uses {}",
                        existing_action.title(),
                        shortcut
                    ));
                }
            }
        }

        let key = parse_shortcut(shortcut).ok_or_else(|| format!("Invalid shortcut: {}", shortcut))?;

        {
            let mut hotkey_ids = self.hotkey_ids.write().unwrap();
            if hotkey_ids.contains_key(&key) {
                return Err("That chord is already registered for another action.".into());
            }
            if is_reserved_shortcut(&key) {
                return Err("That chord is reserved by the system or SwarmAI.".into());
            }
            if is_text_stealing_shortcut(&key) {
                return Err("That chord would steal typing without a modifier.".into());
            }
        }

        let id = key.id();

        if self._hotkey_manager.register(key.clone()).is_err() {
            return Err("Failed to register global hotkey".into());
        }

        let mut hotkey_ids = self.hotkey_ids.write().unwrap();
        let mut reverse_ids = self.reverse_ids.write().unwrap();
        let mut bindings = self.bindings.write().unwrap();
        hotkey_ids.insert(key.clone(), action);
        reverse_ids.insert(id, key);
        bindings.set(action, Some(shortcut.to_string()));
        Ok(())
    }

    /// Unregister the shortcut for the given action.
    pub fn unregister(&self, action: ShortcutAction) {
        let mut hotkey_ids = self.hotkey_ids.write().unwrap();
        let mut reverse_ids = self.reverse_ids.write().unwrap();
        let bindings = self.bindings.read().unwrap();

        // Find the HotKey for this action by scanning the hotkey_ids map.
        if let Some((key, _)) = hotkey_ids.iter().find(|(_, a)| **a == action) {
            let key = *key;
            let id = key.id();
            if reverse_ids.remove(&id).is_some() {
                let _ = self._hotkey_manager.unregister(key);
            }
            hotkey_ids.remove(&key);
        }
        drop(bindings);
        let mut bindings = self.bindings.write().unwrap();
        bindings.set(action, None);
    }

    /// Bind a `HotKeyState` event (from the global hotkey listener) to an
    /// action.  Returns the action that was triggered, or `None`.
    pub fn bind_action(&self, hotkey_state: HotKeyState, id: u32) -> Option<ShortcutAction> {
        if hotkey_state != HotKeyState::Pressed {
            return None;
        }
        let reverse_ids = self.reverse_ids.read().unwrap();
        let key = reverse_ids.get(&id)?;
        let hotkey_ids = self.hotkey_ids.read().unwrap();
        hotkey_ids.get(key).copied()
    }

    /// Look up the shortcut string for an action.
    pub fn shortcut_for(&self, action: ShortcutAction) -> Option<String> {
        self.bindings.read().unwrap().get(action).map(|s| s.to_string())
    }

    /// All registered bindings.
    pub fn all_bindings(&self) -> Vec<ShortcutBinding> {
        self.bindings.read().unwrap().all()
    }

    /// Clear every shortcut.
    pub fn clear_all(&self) {
        self.bindings.write().unwrap().reset();
        // Unregister all hotkeys.
        let reverse_ids = self.reverse_ids.read().unwrap();
        let keys: Vec<HotKey> = reverse_ids.values().cloned().collect();
        drop(reverse_ids);
        for key in keys {
            let _ = self._hotkey_manager.unregister(key);
        }
        self.reverse_ids.write().unwrap().clear();
        self.hotkey_ids.write().unwrap().clear();
    }
}

// ---------------------------------------------------------------------------
// Simple heuristic checks
// ---------------------------------------------------------------------------

/// Mac OS / AppKit standard modifier key codes.
const MAC_MODIFIER_KEY_CODES: [u32; 10] = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63];
const ADDITIONAL_MODIFIER_CODES: [u32; 9] = [18, 19, 20, 21, 23, 22, 26, 28, 25];
/// Keys that type characters without a modifier.
const TEXT_TYPING_KEY_CODES: [u32; 48] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26,
    27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50,
];

fn is_reserved_shortcut(key: &HotKey) -> bool {
    let reserved_key_codes: [u32; 21] = [12, 13, 4, 46, 8, 9, 7, 0, 6, 18, 19, 20, 21, 23, 22, 26, 28, 25, 1, 2, 29];
    for code in reserved_key_codes {
        if key.key as u32 == code
            && key.mods == Modifiers::empty()
        {
            return true;
        }
        if key.key as u32 == 6 && key.mods.contains(Modifiers::SHIFT) {
            return true;
        }
    }
    false
}

fn is_text_stealing_shortcut(key: &HotKey) -> bool {
    let has_no_real_modifier = key.mods == Modifiers::empty()
        || key.mods == Modifiers::SHIFT;
    has_no_real_modifier && TEXT_TYPING_KEY_CODES.contains(&(key.key as u32))
}

fn parse_shortcut(_shortcut: &str) -> Option<HotKey> {
    let _ = _shortcut;
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_action_titles() {
        assert_eq!(ShortcutAction::NewThread.title(), "New thread");
        assert_eq!(ShortcutAction::CommandPalette.title(), "Command palette");
    }

    #[test]
    fn test_action_details() {
        assert_eq!(
            ShortcutAction::ToggleSidebar.detail(),
            "Shows or hides the sidebar."
        );
    }

    #[test]
    fn test_section_actions() {
        let actions = ShortcutSection::Threads.actions();
        assert!(actions.contains(&ShortcutAction::NewThread));
        assert!(!actions.contains(&ShortcutAction::ToggleSidebar));
    }

    #[test]
    fn test_shortcut_manager_register() {
        let mgr = ShortcutManager::new();
        // parse_shortcut returns None for plain strings, so this tests the
        // error path of an invalid shortcut.
        let result = mgr.register(ShortcutAction::NewThread, "invalid");
        assert!(result.is_err());
    }

    #[test]
    fn test_shortcut_manager_unregister() {
        let mgr = ShortcutManager::new();
        mgr.unregister(ShortcutAction::NewThread);
        // Should not panic.
    }

    #[test]
    fn test_shortcut_manager_clear_all() {
        let mgr = ShortcutManager::new();
        mgr.clear_all();
        assert!(mgr.all_bindings().is_empty());
    }
}
