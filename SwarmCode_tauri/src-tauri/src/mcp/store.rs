//! MCP Store - manages MCP connections and their state

use std::collections::HashMap;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Types (duplicated here to avoid circular deps with mod.rs)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MCPConnectionStateValue {
    NotConnected,
    Connecting,
    Connected,
    Error,
}

impl Default for MCPConnectionStateValue {
    fn default() -> Self {
        Self::NotConnected
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MCPConnectionState {
    pub connection_state: MCPConnectionStateValue,
    pub error_message: Option<String>,
    pub tool_count: usize,
}

impl MCPConnectionState {
    pub fn is_connected(&self) -> bool {
        matches!(self.connection_state, MCPConnectionStateValue::Connected)
    }
}

// ---------------------------------------------------------------------------
// MCPConnection
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPConnection {
    pub catalog_id: String,
    pub values: HashMap<String, String>,
    pub is_enabled: bool,
    pub connected_at: Option<String>,
    pub error: Option<String>,
    pub tools: Vec<String>,
    pub state: MCPConnectionState,
}

impl Default for MCPConnection {
    fn default() -> Self {
        Self {
            catalog_id: String::new(),
            values: HashMap::new(),
            is_enabled: false,
            connected_at: None,
            error: None,
            tools: Vec::new(),
            state: MCPConnectionState::default(),
        }
    }
}

// ---------------------------------------------------------------------------
// MCPStore
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MCPStore {
    pub connections: Vec<MCPConnection>,
}

impl Default for MCPStore {
    fn default() -> Self {
        Self {
            connections: Vec::new(),
        }
    }
}

impl MCPStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn state(&self, id: &str) -> MCPConnectionState {
        self.connections
            .iter()
            .find(|c| c.catalog_id == id)
            .map(|c| c.state.clone())
            .unwrap_or_default()
    }

    pub fn connection(&self, id: &str) -> Option<&MCPConnection> {
        self.connections.iter().find(|c| c.catalog_id == id)
    }

    pub fn connection_mut(&mut self, id: &str) -> Option<&mut MCPConnection> {
        self.connections.iter_mut().find(|c| c.catalog_id == id)
    }

    pub fn enabled_servers(&self) -> Vec<&MCPConnection> {
        self.connections.iter().filter(|c| c.is_enabled && c.connected_at.is_some()).collect()
    }

    pub fn get_or_create(&mut self, catalog_id: &str) -> &mut MCPConnection {
        if let Some(idx) = self.connections.iter().position(|c| c.catalog_id == catalog_id) {
            return &mut self.connections[idx];
        }
        let conn = MCPConnection::default();
        self.connections.push(conn);
        let last = self.connections.last_mut().unwrap();
        last.catalog_id = catalog_id.to_string();
        last
    }

    pub fn update_connection(&mut self, conn: MCPConnection) {
        if let Some(idx) = self.connections.iter().position(|c| c.catalog_id == conn.catalog_id) {
            self.connections[idx] = conn;
        } else {
            self.connections.push(conn);
        }
    }
}
