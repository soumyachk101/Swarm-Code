use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

pub mod provider;
pub mod thread;
pub mod timeline;
pub mod hydra;
pub mod theme;
pub mod requests;
pub mod library;
pub mod merge_link;

pub use provider::*;
pub use thread::*;
pub use timeline::*;
pub use hydra::*;
pub use theme::*;
pub use requests::*;
pub use library::*;
pub use merge_link::*;

// ---------------------------------------------------------------------------
// init_models
//
// Module-level initializer for the model layer. Currently a no-op because
// all models are static data definitions, but exposed as a hook so future
// schema-registration or capability-table logic has a stable entry point.
// ---------------------------------------------------------------------------

pub fn init_models() {
 // Intentionally empty: models are pure data definitions.
}
