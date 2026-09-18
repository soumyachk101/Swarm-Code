//! MCP (Model Context Protocol) module
//! Mirrors the Swarm Code MCP subsystem: catalog, connection state, and commands.

pub mod catalog;
pub mod store;

use serde::{Deserialize, Serialize};

// Re-export the concrete types from store so the rest of the codebase sees one stable path
pub use store::{
    MCPConnection, MCPConnectionState, MCPConnectionStateValue, MCPStore,
};

// Re-export catalog exports for convenience
pub use catalog::MCPCatalog;

// ---------------------------------------------------------------------------
// Field/Transport/CatalogEntry types (also defined here for serde stability)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MCPTransport {
    Stdio,
    Http,
    Sse,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MCPFieldKind {
    Text,
    Secret,
    Path,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPField {
    pub key: String,
    pub label: String,
    pub placeholder: String,
    pub kind: MCPFieldKind,
    pub help: String,
    pub is_required: bool,
    pub default_value: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPTransportConfig {
    pub transport: MCPTransport,
    pub command: Option<String>,
    pub args: Vec<String>,
    pub url: Option<String>,
    pub headers: Vec<(String, String)>,
}

#[derive(Debug, Clone, Serialize)]
pub struct MCPCatalogEntry {
    pub id: &'static str,
    pub name: &'static str,
    pub vendor: &'static str,
    pub summary: &'static str,
    pub category: MCPCategory,
    pub asset: String,
    pub color: u32,
    pub is_monochrome: bool,
    pub transport: MCPTransportConfig,
    pub fields: Vec<MCPField>,
    pub docs_url: &'static str,
    pub sample_tools: Vec<String>,
    pub keys_url: Option<&'static str>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MCPCategory {
    Developer,
    Browser,
    Knowledge,
    Database,
    Communication,
}

impl MCPCategory {
    pub fn title(&self) -> &'static str {
        match self {
            Self::Developer => "Developer",
            Self::Browser => "Browser",
            Self::Knowledge => "Knowledge",
            Self::Database => "Database",
            Self::Communication => "Communication",
        }
    }
}
