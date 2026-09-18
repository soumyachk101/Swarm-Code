use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

// =============================================================================
// Wire-Protocol Models (mirror SwarmAI/Bridge/API/BridgeEvent.swift)
// =============================================================================

// ---- WebSocket Event Envelope ----

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BridgeEvent {
    // Server → Mobile
    #[serde(rename = "messageDelta")]
    MessageDelta {
        threadID: Uuid,
        content: String,
        isTool: bool,
    },
    #[serde(rename = "messageComplete")]
    MessageComplete {
        threadID: Uuid,
        messageID: String,
    },
    #[serde(rename = "toolCall")]
    ToolCall {
        threadID: Uuid,
        tool: String,
        input: String,
    },
    #[serde(rename = "toolResult")]
    ToolResult {
        threadID: Uuid,
        result: String,
        error: Option<String>,
    },
    #[serde(rename = "approvalRequest")]
    ApprovalRequest {
        threadID: Uuid,
        action: String,
        details: String,
    },
    #[serde(rename = "thinkingDelta")]
    ThinkingDelta {
        threadID: Uuid,
        content: String,
    },
    #[serde(rename = "error")]
    Error {
        threadID: Option<Uuid>,
        #[serde(rename = "reason")]
        message: String,
    },
    #[serde(rename = "terminalOutput")]
    TerminalOutput {
        threadID: Uuid,
        output: String,
    },
    #[serde(rename = "threadUpdated")]
    ThreadUpdated { threadID: Uuid },
    #[serde(rename = "paired")]
    Paired { sessionToken: String },
    #[serde(rename = "pairFailed")]
    PairFailed { reason: String },

    // Mobile → Server
    #[serde(rename = "sendMessage")]
    SendMessage { threadID: Uuid, content: String },
    #[serde(rename = "approve")]
    Approve {
        threadID: Uuid,
        #[serde(rename = "messageID")]
        actionID: String,
    },
    #[serde(rename = "reject")]
    Reject {
        threadID: Uuid,
        #[serde(rename = "messageID")]
        actionID: String,
    },
    #[serde(rename = "createThread")]
    CreateThread {
        projectID: Uuid,
        #[serde(rename = "content")]
        prompt: String,
    },
    #[serde(rename = "switchModel")]
    SwitchModel { threadID: Uuid, model: String },
    #[serde(rename = "pair")]
    Pair { code: String },
}

// ---- REST DTOs ----

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeThreadSummary {
    pub id: Uuid,
    #[serde(rename = "projectID")]
    pub project_id: Uuid,
    #[serde(rename = "projectName")]
    pub project_name: String,
    pub title: String,
    pub provider: String,
    pub model: String,
    #[serde(rename = "lastStatus")]
    pub last_status: String,
    #[serde(rename = "hasUnread")]
    pub has_unread: bool,
    #[serde(rename = "updatedAt")]
    pub updated_at: DateTime<Utc>,
    #[serde(rename = "messageCount")]
    pub message_count: i32,
    #[serde(rename = "lastMessagePreview")]
    pub last_message_preview: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeThreadDetail {
    pub id: Uuid,
    #[serde(rename = "projectID")]
    pub project_id: Uuid,
    #[serde(rename = "projectPath")]
    pub project_path: String,
    pub title: String,
    pub provider: String,
    pub model: String,
    #[serde(rename = "runtimeMode")]
    pub runtime_mode: String,
    #[serde(rename = "createdAt")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt")]
    pub updated_at: DateTime<Utc>,
    pub entries: Vec<BridgeTimelineEntry>,
    pub approvals: Vec<BridgeApproval>,
    #[serde(rename = "diffRevision")]
    pub diff_revision: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeTimelineEntry {
    pub id: String,
    pub kind: String,
    pub date: DateTime<Utc>,
    pub text: Option<String>,
    pub name: Option<String>,
    pub input: Option<String>,
    pub output: Option<String>,
    pub error: Option<String>,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeApproval {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub detail: Option<String>,
    pub options: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeStatus {
    pub status: String,
    pub version: String,
    #[serde(rename = "threadCount")]
    pub thread_count: i32,
    pub paired: bool,
    #[serde(rename = "connectedClients")]
    pub connected_clients: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeModels {
    pub providers: std::collections::HashMap<String, BridgeProviderInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeProviderInfo {
    pub id: String,
    pub models: Vec<String>,
}

// init_models — no-op for now.
pub fn init_models() {}
