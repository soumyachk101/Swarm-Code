//! Support module - shared utilities (shell execution, audio, text helpers, etc.).

pub mod cache;
pub mod coding;
pub mod id;
pub mod json_rpc;
pub mod json_value;
pub mod migration;
pub mod shell;
pub mod shortcuts;
pub mod stdio_process;
pub mod text;
pub mod thumbnail;
pub mod tone;
pub mod tour_captures;
pub mod website_captures;

pub use id::next_id;

// ---------------------------------------------------------------------------
// init_support
// ---------------------------------------------------------------------------

pub fn init_support() {
 // Intentionally empty.
}
