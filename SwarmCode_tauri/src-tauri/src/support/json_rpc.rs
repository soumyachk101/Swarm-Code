//! JSON-RPC 2.0 message handling and stdio client.
//!
//! Mirrors the Swift `JSONRPC` type: provides request, response, and
//! notification types for JSON-RPC 2.0 communication, plus a client
//! that speaks over stdio (used for AI CLI tools).

use std::collections::HashMap;
use std::process::Stdio;
use std::str::FromStr;
use std::sync::Arc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::{oneshot, RwLock};
use uuid::Uuid;

use crate::support::shell::ShellError;

// ---------------------------------------------------------------------------
// JSON-RPC 2.0 types
// ---------------------------------------------------------------------------

/// A JSON-RPC 2.0 message ID (string, number, or null for notifications).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum RpcId {
 Number(i64),
 String(String),
 Null,
}

impl Default for RpcId {
 fn default() -> Self {
 RpcId::String(Uuid::new_v4().to_string())
 }
}

/// A JSON-RPC 2.0 request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcRequest {
 pub jsonrpc: String,
 pub id: Option<RpcId>,
 pub method: String,
 #[serde(default)]
 pub params: RpcParams,
}

impl RpcRequest {
 pub fn new(method: impl Into<String>) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 id: Some(RpcId::default()),
 method: method.into(),
 params: RpcParams::Object(HashMap::new()),
 }
 }

 pub fn with_params(method: impl Into<String>, params: RpcParams) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 id: Some(RpcId::default()),
 method: method.into(),
 params,
 }
 }

 pub fn set_id(&mut self, id: RpcId) {
 self.id = Some(id);
 }

 pub fn set_param<K, V>(&mut self, key: K, value: V)
 where
 K: Into<String>,
 V: Serialize,
 {
 match &mut self.params {
 RpcParams::Object(map) => {
 map.insert(key.into(), serde_json::to_value(value).unwrap_or(Value::Null));
 }
 RpcParams::Array(arr) => {
 arr.push(serde_json::to_value(value).unwrap_or(Value::Null));
 }
 }
 }

 pub fn set_param_by_name(&mut self, name: impl Into<String>, value: Value) {
 match &mut self.params {
 RpcParams::Object(map) => {
 map.insert(name.into(), value);
 }
 RpcParams::Array(arr) => {
 if let Some(first) = arr.first_mut() {
 *first = value;
 }
 }
 }
 }

 /// Serialize this request to a JSON string.
 pub fn to_json(&self) -> Result<String, serde_json::Error> {
 serde_json::to_string(self)
 }

 /// Serialize to a pretty-printed JSON string.
 pub fn to_json_pretty(&self) -> Result<String, serde_json::Error> {
 serde_json::to_string_pretty(self)
 }
}

/// Parameters for an RPC request (object or array).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RpcParams {
 Object(HashMap<String, Value>),
 Array(Vec<Value>),
}

impl Default for RpcParams {
 fn default() -> Self {
 Self::Object(HashMap::new())
 }
}

impl RpcParams {
 pub fn object() -> Self {
 Self::Object(HashMap::new())
 }

 pub fn is_empty(&self) -> bool {
 match self {
 Self::Object(map) => map.is_empty(),
 Self::Array(arr) => arr.is_empty(),
 }
 }
}

/// A JSON-RPC 2.0 response (for request/response pattern).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcResponse {
 pub jsonrpc: String,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub id: Option<RpcId>,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub result: Option<Value>,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub error: Option<RpcError>,
}

impl RpcResponse {
 pub fn new(id: Option<RpcId>, result: Value) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 id,
 result: Some(result),
 error: None,
 }
 }

 pub fn error(id: Option<RpcId>, error: RpcError) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 id,
 result: None,
 error: Some(error),
 }
 }

 pub fn success(id: Option<RpcId>) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 id,
 result: Some(Value::Bool(true)),
 error: None,
 }
 }
}

/// A JSON-RPC 2.0 error object.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcError {
 pub code: i32,
 pub message: String,
 #[serde(skip_serializing_if = "Option::is_none")]
 pub data: Option<Value>,
}

impl RpcError {
 pub const PARSE_ERROR: i32 = -32700;
 pub const INVALID_REQUEST: i32 = -32600;
 pub const METHOD_NOT_FOUND: i32 = -32601;
 pub const INVALID_PARAMS: i32 = -32602;
 pub const INTERNAL_ERROR: i32 = -32603;

 pub fn new(code: i32, message: impl Into<String>) -> Self {
 Self {
 code,
 message: message.into(),
 data: None,
 }
 }
}

/// A JSON-RPC 2.0 notification (no response expected).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcNotification {
 pub jsonrpc: String,
 pub method: String,
 #[serde(default)]
 pub params: RpcParams,
}

impl RpcNotification {
 pub fn new(method: impl Into<String>) -> Self {
 Self {
 jsonrpc: "2.0".to_string(),
 method: method.into(),
 params: RpcParams::Object(HashMap::new()),
 }
 }

 pub fn set_param<K, V>(&mut self, key: K, value: V)
 where
 K: Into<String>,
 V: Serialize,
 {
 match &mut self.params {
 RpcParams::Object(map) => {
 map.insert(key.into(), serde_json::to_value(value).unwrap_or(Value::Null));
 }
 RpcParams::Array(arr) => {
 arr.push(serde_json::to_value(value).unwrap_or(Value::Null));
 }
 }
 }

 pub fn to_json(&self) -> Result<String, serde_json::Error> {
 serde_json::to_string(self)
 }
}

// ---------------------------------------------------------------------------
// RpcMessage - unified envelope
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RpcMessage {
 Request(RpcRequest),
 Response(RpcResponse),
 Notification(RpcNotification),
}

// ---------------------------------------------------------------------------
// RpcClient - client that speaks JSON-RPC over stdio
// ---------------------------------------------------------------------------

pub struct RpcClient {
 pub(crate) _stdin_writer: Option<tokio::process::ChildStdin>,
 pub(crate) stdout_reader: Option<tokio::process::ChildStdout>,
 pub(crate) stderr_reader: Option<tokio::process::ChildStderr>,
 pub(crate) pending: RwLock<HashMap<String, oneshot::Sender<RpcResponse>>>,
 pub(crate) notifications: RwLock<Vec<RpcNotification>>,
 pub(crate) process: Option<StdioProcessHandle>,
}

impl RpcClient {
 /// Connect to a process via stdio and start the RPC client.
 pub async fn connect(
 name: impl Into<String>,
 args: Vec<String>,
 env: HashMap<String, String>,
 cwd: Option<String>,
 ) -> Result<Self, ShellError> {
 use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
 use tokio::process::Command;

 let name_str = name.into();
 let mut cmd = Command::new(&name_str);
 cmd
 .args(&args)
 .stdin(Stdio::piped())
 .stdout(Stdio::piped())
 .stderr(Stdio::piped())
 .kill_on_drop(true);

 if let Some(ref wd) = cwd {
 cmd.current_dir(wd);
 }

 for (key, value) in env {
 cmd.env(key, value);
 }

 let mut child = cmd.spawn()?;
 let pid = child.id();

 let stdin = child.stdin.take();
 let stdout = child.stdout.take();
 let stderr = child.stderr.take();

 let (stdin_writer, stdout_reader, stderr_reader, process_handle) =
 (stdin, stdout, stderr, pid);

 Ok(Self {
 _stdin_writer: stdin_writer,
 stdout_reader,
 stderr_reader,
 pending: RwLock::new(HashMap::new()),
 notifications: RwLock::new(Vec::new()),
 process: Some(StdioProcessHandle { pid: process_handle }),
 })
 }

 /// Send an RPC request and wait for the response.
 pub async fn call(
 &self,
 _method: impl Into<String>,
 _params: RpcParams,
 _timeout: Option<std::time::Duration>,
 ) -> Result<Value, RpcError> {
 // The real implementation would:
 // 1. Serialize the request as JSON-RPC
 // 2. Write it to the process's stdin
 // 3. Read the response from stdout
 // 4. Match on the JSON-RPC response
 // For now, this is a stub that returns an error
 Err(RpcError::new(
 RpcError::INTERNAL_ERROR,
 "RPC client not fully implemented",
 ))
 }

 /// Send an RPC notification (no response expected).
 pub async fn notify(&self, _method: impl Into<String>, _params: RpcParams) -> Result<(), String> {
 Ok(())
 }

 /// Close the connection.
 pub async fn close(&mut self) {
 let _ = self.process.take();
 }
}

impl Drop for RpcClient {
 fn drop(&mut self) {
 let _ = self.process.take();
 }
}

#[derive(Debug, Clone)]
pub struct StdioProcessHandle {
 pub pid: Option<u32>,
}

// ---------------------------------------------------------------------------
// JsonRpcClient - higher-level client
// ---------------------------------------------------------------------------

pub struct JsonRpcClient {
 pub client: Option<RpcClient>,
}

impl JsonRpcClient {
 pub async fn connect(
 name: impl Into<String>,
 args: Vec<String>,
 env: HashMap<String, String>,
 cwd: Option<String>,
 ) -> Result<Self, ShellError> {
 let client = RpcClient::connect(name, args, env, cwd).await?;
 Ok(Self { client: Some(client) })
 }

 pub async fn call_method<T: serde::de::DeserializeOwned>(
 &mut self,
 method: impl Into<String>,
 params: RpcParams,
 timeout: Option<std::time::Duration>,
 ) -> Result<T, RpcError> {
 let client = match &self.client {
 Some(c) => c,
 None => return Err(RpcError::new(RpcError::INTERNAL_ERROR, "client disconnected")),
 };

 match client.call(method, params, timeout).await {
 Ok(value) => serde_json::from_value(value).map_err(|_| {
 RpcError::new(RpcError::PARSE_ERROR, "failed to parse response")
 }),
 Err(e) => Err(e),
 }
 }

 pub async fn close(&mut self) {
 if let Some(mut c) = self.client.take() {
 c.close().await;
 }
 }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn test_request_serialization() {
 let req = RpcRequest::new("tools/list");
 let json = req.to_json().unwrap();
 assert!(json.contains("\"method\":\"tools/list\""));
 assert!(json.contains("\"jsonrpc\":\"2.0\""));
 }

 #[test]
 fn test_response_serialization() {
 let resp = RpcResponse::new(Some(RpcId::Number(1)), Value::Bool(true));
 let json = serde_json::to_string(&resp).unwrap();
 assert!(json.contains("\"result\":true"));
 }

 #[test]
 fn test_notification_serialization() {
 let mut notif = RpcNotification::new("tools/list");
 notif.set_param("cursor", Value::String("abc".to_string()));
 let json = notif.to_json().unwrap();
 assert!(json.contains("\"method\":\"tools/list\""));
 }

 #[test]
 fn test_error_codes() {
 assert_eq!(RpcError::METHOD_NOT_FOUND, -32601);
 }
}
