pub mod acp;
pub mod antigravity;
pub mod claude;
pub mod codex;
pub mod copilot;
pub mod credits;
pub mod deepseek;
pub mod meta;
pub mod plan_limits;
pub mod registry;
pub mod session;
pub mod text_generation;

pub use registry::ProviderRegistry;

// ---------------------------------------------------------------------------
// init_providers
//
// Called once at startup with the raw window handle so that providers that
// need to register global assets (e.g. tray icons, platform-specific
// credential stores) have the app handle available.
// ---------------------------------------------------------------------------

pub fn init_providers() {
 // Intentionally empty: provider capabilities are self-contained.
 // The parameter exists so that future providers that need a window
 // handle or app-identifier can receive it here without a breaking
 // change to the call-site.
}
