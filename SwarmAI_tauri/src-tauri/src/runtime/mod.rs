//! Runtime module - manages background AI agent execution.
//!
//! The runtime layer owns a thread's live state: its timeline, provider
//! session and pending requests. It mirrors the Swift `ThreadRuntime`
//! class and `AutoContinue` type.

pub mod auto_continue;
pub mod thread_runtime;

pub use auto_continue::{AutoContinue, CONTINUE_MESSAGE, MARGIN_SECONDS, UsageLimitSignal};

// ---------------------------------------------------------------------------
// init_runtime
// ---------------------------------------------------------------------------

pub fn init_runtime() {
 // Intentionally empty.
}
