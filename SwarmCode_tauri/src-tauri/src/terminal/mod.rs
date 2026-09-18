//! Terminal module - manages PTY-based terminal sessions.
//!
//! Mirrors the Swift `TerminalStore` class: spawns PTY-backed shell
//! sessions, handles I/O streaming, and manages session lifecycle.

pub mod terminal_store;

pub use terminal_store::TerminalStore;

// ---------------------------------------------------------------------------
// init_terminal
// ---------------------------------------------------------------------------

pub fn init_terminal() {
 // Intentionally empty.
}
