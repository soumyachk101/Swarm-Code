use async_trait::async_trait;
use std::sync::Arc;

use super::session::{
    ProviderError, ProviderSession, SessionConfiguration, SessionStatus, TurnInput,
};
use crate::models::provider::{ModelOption, ProviderKind, SlashCommand};
use crate::models::timeline::{ContextUsage, Notice, NoticeLevel};
use crate::runtime::thread_runtime::{AgentSpawn, ApprovalRequest, ProviderEvent, ToolCall, ToolUpdate};

// ---------------------------------------------------------------------------
// ClaudeSession
//
// Drives the Claude Code CLI in headless stream-json mode over stdio.
// Communicates using the LSP-like JSON wire protocol that Claude Code
// exposes when run with --input-format stream-json --output-format stream-json.
// ---------------------------------------------------------------------------

pub struct ClaudeSession {
    config: SessionConfiguration,
    event_handler: Option<Arc<dyn Fn(ProviderEvent) + Send + Sync>>,

    // Process management
    process: Option<std::process::Child>,
    stdin_writer: Option<tokio::process::ChildStdin>,
    stdout_reader: Option<tokio::process::ChildStdout>,
    stderr_reader: Option<tokio::process::ChildStderr>,

    // State
    session_id: Option<String>,
    permission_mode: String,
    runtime_mode: crate::models::provider::RuntimeMode,
    model: Option<String>,
    control_counter: u64,
    pending_control: std::collections::HashMap<String, tokio::sync::oneshot::Sender<serde_json::Value>>,
    pending_tools: std::collections::HashMap<String, PendingTool>,
    tool_names: std::collections::HashMap<String, String>,
    turn_active: bool,
    interrupt_requested: bool,
    is_stopping: bool,
    // Hydra / multi-agent state
    main_stream: StreamState,
    agent_streams: std::collections::HashMap<String, StreamState>,
    agents_by_task: std::collections::HashMap<String, String>,
    tasks_by_agent: std::collections::HashMap<String, String>,

    // Background task handles
    read_handle: Option<tokio::task::JoinHandle<()>>,
    stderr_handle: Option<tokio::task::JoinHandle<()>>,
}

#[derive(Debug, Clone, Default)]
struct StreamState {
    current_message_id: Option<String>,
    block_ids: std::collections::HashMap<usize, String>,
    open_text: std::collections::HashMap<String, Vec<String>>,
    open_thinking: std::collections::HashMap<String, Vec<String>>,
}

#[derive(Debug, Clone)]
struct PendingTool {
    name: String,
    input: serde_json::Value,
    suggestions: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// Lazy statics for JSON value helpers
// ---------------------------------------------------------------------------

impl ClaudeSession {
    pub fn new(config: SessionConfiguration) -> Self {
        let mode_name = Self::mode_name(config.runtime_mode, config.interaction_mode);
        Self {
            config,
            event_handler: None,
            process: None,
            stdin_writer: None,
            stdout_reader: None,
            stderr_reader: None,
            session_id: None,
            permission_mode: mode_name,
            runtime_mode: crate::models::provider::RuntimeMode::default(),
            model: None,
            control_counter: 0,
            pending_control: std::collections::HashMap::new(),
            pending_tools: std::collections::HashMap::new(),
            tool_names: std::collections::HashMap::new(),
            turn_active: false,
            interrupt_requested: false,
            is_stopping: false,
            main_stream: StreamState::default(),
            agent_streams: std::collections::HashMap::new(),
            agents_by_task: std::collections::HashMap::new(),
            tasks_by_agent: std::collections::HashMap::new(),
            read_handle: None,
            stderr_handle: None,
        }
    }

    fn emit(&self, event: ProviderEvent) {
        if let Some(ref handler) = self.event_handler {
            handler(event);
        }
    }

    fn working_directory(&self) -> &str {
        &self.config.working_directory
    }

    /// Maps runtime+interaction modes to Claude Code's permission mode string.
    fn mode_name(runtime: crate::models::provider::RuntimeMode, interaction: crate::models::provider::InteractionMode) -> &'static str {
        if interaction == crate::models::provider::InteractionMode::Plan {
            return "plan";
        }
        match runtime {
            crate::models::provider::RuntimeMode::Supervised => "default",
            crate::models::provider::RuntimeMode::AutoAcceptEdits => "acceptEdits",
            crate::models::provider::RuntimeMode::Auto => "auto",
            crate::models::provider::RuntimeMode::FullAccess => "bypassPermissions",
        }
    }
}

#[async_trait]
impl ProviderSession for ClaudeSession {
    fn on_event(&self) -> Option<Arc<dyn Fn(ProviderEvent) + Send + Sync>> {
        self.event_handler.clone()
    }

    fn set_on_event(&mut self, handler: Arc<dyn Fn(ProviderEvent) + Send + Sync>) {
        self.event_handler = Some(handler);
    }

    fn status(&self) -> SessionStatus {
        if self.is_running() {
            SessionStatus::Running
        } else {
            SessionStatus::Idle
        }
    }

    fn is_running(&self) -> bool {
        self.process
            .as_ref()
            .map(|p| match p.try_wait() {
                Ok(None) => true,
                _ => false,
            })
            .unwrap_or(false)
    }

    fn provider_kind(&self) -> ProviderKind {
        ProviderKind::Claude
    }

    async fn start(&mut self, config: SessionConfiguration) -> Result<String, ProviderError> {
        self.config = config;

        let executable = self.config.executable.as_ref()
            .ok_or_else(|| ProviderError::not_installed(ProviderKind::Claude))?;

        let id = self.config.resume_id.clone()
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string().replace('-', ""));

        let mut args: Vec<String> = vec![
            "-p".into(),
            "--input-format".into(), "stream-json".into(),
            "--output-format".into(), "stream-json".into(),
            "--verbose".into(),
            "--include-partial-messages".into(),
            "--permission-prompt-tool".into(), "stdio".into(),
            "--setting-sources".into(), "user,project,local".into(),
            "--allow-dangerously-skip-permissions".into(),
            "--permission-mode".into(), self.permission_mode.into(),
        ];

        if let Some(ref model) = self.config.model {
            if model != "default" {
                args.extend(["--model".into(), model.clone()]);
            }
        }
        if let Some(ref effort) = self.config.effort {
            if !effort.is_empty() {
                args.extend(["--effort".into(), effort.clone()]);
            }
        }
        if self.config.fast_mode {
            args.extend(["--settings".into(), r#"{"fastMode":true}"#.into()]);
        }

        // Hydra configuration
        if let Some(ref hydra) = self.config.hydra {
            if hydra.runs_natively {
                args.extend([
                    "--agents".into(),
                    Self::claude_agents_spec(hydra),
                    "--append-system-prompt".into(),
                    Self::hydra_policy(hydra),
                    "--system-prompt-snapshot".into(), "off".into(),
                    "--forward-subagent-text".into(),
                ]);
                if let Some(cap) = hydra.max_heads {
                    self.config.environment.insert(
                        "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS".into(),
                        cap.to_string(),
                    );
                }
            } else {
                args.extend([
                    "--append-system-prompt".into(),
                    Self::fallback_policy(hydra),
                    "--system-prompt-snapshot".into(), "off".into(),
                    "--disallowedTools".into(), "Agent".into(), "Task".into(),
                ]);
            }
        }

        // Resume or new session
        if let Some(ref resume_id) = self.config.resume_id {
            args.extend(["--resume".into(), resume_id.clone()]);
            if let Some(ref anchor) = self.config.resume_at {
                args.extend(["--resume-session-at".into(), anchor.clone()]);
            }
        } else {
            args.extend(["--session-id".into(), id.clone()]);
        }

        // Spawn the Claude Code process
        let mut cmd = tokio::process::Command::new(executable);
        cmd.args(&args)
            .current_dir(self.working_directory())
            .envs(&self.config.environment)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());

        let mut child = cmd.spawn()
            .map_err(|e| ProviderError::failed(format!("Failed to start Claude Code: {}", e)))?;

        let stdin = child.stdin.take()
            .ok_or_else(|| ProviderError::failed("Failed to open Claude Code stdin"))?;
        let stdout = child.stdout.take()
            .ok_or_else(|| ProviderError::failed("Failed to open Claude Code stdout"))?;
        let stderr = child.stderr.take()
            .ok_or_else(|| ProviderError::failed("Failed to open Claude Code stderr"))?;

        self.stdin_writer = Some(stdin);
        self.stdout_reader = Some(stdout);
        self.stderr_reader = Some(stderr);
        self.process = Some(child);
        self.session_id = Some(id.clone());
        self.spawn_read_task();

        // Wait for initialization message with timeout
        let init_timeout = std::time::Duration::from_secs(30);
        let init_result = tokio::time::timeout(init_timeout, self.wait_for_initialize()).await;

        match init_result {
            Ok(Ok(models)) => {
                if !models.is_empty() {
                    self.emit(ProviderEvent::Models(models, self.config.model.as_deref()));
                }
                let commands = self.read_commands().await;
                if !commands.is_empty() {
                    self.emit(ProviderEvent::Commands(commands));
                }
                Ok(id)
            }
            Ok(Err(e)) => Err(e),
            Err(_) => {
                self.stop();
                Err(ProviderError::failed("Claude Code initialization timed out after 30s"))
            }
        }
    }

    async fn send(&mut self, input: TurnInput) -> Result<(), ProviderError> {
        if !self.is_running() {
            return Err(ProviderError::not_running());
        }

        self.runtime_mode = input.runtime_mode;
        let mode = Self::mode_name(input.runtime_mode, input.interaction_mode);
        if mode != self.permission_mode {
            let _ = self.send_control(&serde_json::json!({
                "subtype": "set_permission_mode",
                "mode": mode
            })).await;
            self.permission_mode = mode;
        }

        if input.model.as_deref() != self.model.as_deref() {
            let wire = match input.model.as_deref() {
                Some("default") | None => serde_json::Value::Null,
                Some(m) => serde_json::Value::String(m.into()),
            };
            let _ = self.send_control(&serde_json::json!({
                "subtype": "set_model",
                "model": wire
            })).await;
            self.model = input.model.clone();
        }

        // Build content array with images and text
        let mut content: Vec<serde_json::Value> = Vec::new();
        for attachment in &input.images {
            if let Some(ref content_b64) = attachment.content {
                content.push(serde_json::json!({
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": attachment.mime_type,
                        "data": content_b64,
                    }
                }));
            }
        }
        content.push(serde_json::json!({
            "type": "text",
            "text": input.text
        }));

        let message = serde_json::json!({
            "type": "user",
            "session_id": "",
            "message": {
                "role": "user",
                "content": content,
            },
            "parent_tool_use_id": serde_json::Value::Null,
        });

        self.write_line(&message).await?;
        self.turn_active = true;
        self.interrupt_requested = false;
        self.emit(ProviderEvent::TurnStarted(None));
        Ok(())
    }

    async fn interrupt(&mut self) {
        if !self.turn_active {
            return;
        }
        self.interrupt_requested = true;

        // Deny all pending tool approvals
        let request_ids: Vec<String> = self.pending_tools.keys().cloned().collect();
        for request_id in request_ids {
            self.send_control(&serde_json::json!({
                "subtype": "control_response",
                "request_id": request_id,
                "response": {
                    "subtype": "success",
                    "request_id": request_id,
                    "response": {
                        "behavior": "deny",
                        "message": "The user stopped the turn.",
                        "interrupt": true,
                    }
                }
            })).await;
            self.emit(ProviderEvent::RequestResolved(request_id));
        }
        self.pending_tools.clear();

        // Send interrupt control
        let _ = self.send_control(&serde_json::json!({
            "subtype": "interrupt"
        })).await;
    }

    async fn compact(&mut self) -> Result<(), ProviderError> {
        if !self.is_running() {
            return Err(ProviderError::not_running());
        }
        self.write_line(&serde_json::json!({
            "type": "user",
            "session_id": "",
            "message": {
                "role": "user",
                "content": [{"type": "text", "text": "/compact"}],
            },
            "parent_tool_use_id": serde_json::Value::Null,
        })).await?;
        Ok(())
    }

    async fn resolve_approval(&mut self, request_id: String, option_id: String) {
        let pending = match self.pending_tools.remove(&request_id) {
            Some(p) => p,
            None => return,
        };

        let response = if option_id == "allow" || option_id == "always" {
            let mut resp = serde_json::json!({
                "behavior": "allow",
                "updatedInput": pending.input,
            });
            if option_id == "always" {
                if let Some(ref suggestions) = pending.suggestions {
                    resp["updatedPermissions"] = suggestions.clone();
                }
            }
            resp
        } else {
            let msg = if pending.name == "ExitPlanMode" {
                "The user wants to keep planning. Wait for their feedback before changing anything."
            } else {
                "The user declined this action."
            };
            serde_json::json!({
                "behavior": "deny",
                "message": msg,
            })
        };

        let _ = self.send_control(&serde_json::json!({
            "subtype": "control_response",
            "request_id": request_id,
            "response": {
                "subtype": "success",
                "request_id": request_id,
                "response": response,
            }
        })).await;

        if pending.name == "ExitPlanMode" {
            self.emit(ProviderEvent::ModeChanged(crate::models::provider::InteractionMode::Build));
            let mode = Self::mode_name(self.runtime_mode, crate::models::provider::InteractionMode::Build);
            self.permission_mode = mode;
        }

        self.emit(ProviderEvent::RequestResolved(request_id));
    }

    async fn answer_question(
        &mut self,
        request_id: String,
        answers: std::collections::HashMap<String, Vec<String>>,
    ) {
        let pending = match self.pending_tools.remove(&request_id) {
            Some(p) => p,
            None => return,
        };

        let mut input = pending.input.as_object().cloned().unwrap_or_default();
        let mut mapped: serde_json::Map<String, serde_json::Value> = serde_json::Map::new();
        for (question, values) in answers {
            mapped.insert(question, serde_json::Value::String(values.join(", ")));
        }
        input.insert("answers".into(), serde_json::Value::Object(mapped));

        let _ = self.send_control(&serde_json::json!({
            "subtype": "control_response",
            "request_id": request_id,
            "response": {
                "subtype": "success",
                "request_id": request_id,
                "response": {
                    "behavior": "allow",
                    "updatedInput": serde_json::Value::Object(input),
                }
            }
        })).await;

        self.emit(ProviderEvent::RequestResolved(request_id));
    }

    async fn stop(&mut self) {
        self.is_stopping = true;
        if let Some(mut process) = self.process.take() {
            let _ = process.kill().await;
        }
        self.read_handle.take();
        self.stderr_handle.take();
        self.stdin_writer = None;
        self.stdout_reader = None;
        self.stderr_reader = None;
        self.turn_active = false;
    }

    async fn stop_agent(&mut self, id: String) -> bool {
        if let Some(task_id) = self.tasks_by_agent.get(&id) {
            return self.send_control(&serde_json::json!({
                "subtype": "stop_task",
                "task_id": task_id,
            })).await.is_ok();
        }
        false
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

impl ClaudeSession {
    /// Sends a control request and awaits the response via a oneshot channel.
    async fn send_control(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, ProviderError> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        self.control_counter += 1;
        let request_id = format!("swarmai-{}", self.control_counter);
        self.pending_control.insert(request_id.clone(), tx);

        let wire = serde_json::json!({
            "type": "control_request",
            "request_id": request_id,
            "request": request,
        });
        self.write_line(&wire).await?;

        match rx.await {
            Ok(val) => Ok(val),
            Err(_) => Err(ProviderError::failed("Control request cancelled: Claude Code exited")),
        }
    }

    async fn write_line(&mut self, value: &serde_json::Value) -> Result<(), ProviderError> {
        use tokio::io::AsyncWriteExt;
        let mut writer = self.stdin_writer.as_mut()
            .ok_or_else(|| ProviderError::not_running())?;
        let line = serde_json::to_string(value)
            .map_err(|e| ProviderError::failed(format!("JSON serialization: {}", e)))?;
        let bytes = format!("{}\n", line);
        writer.write_all(bytes.as_bytes()).await
            .map_err(|e| ProviderError::failed(format!("Write error: {}", e)))?;
        writer.flush().await
            .map_err(|e| ProviderError::failed(format!("Flush error: {}", e)))?;
        Ok(())
    }

    /// Waits for the initialize message from Claude Code.
    async fn wait_for_initialize(&mut self) -> Result<Vec<ModelOption>, ProviderError> {
        // The initialize result comes back through the control channel.
        // We send an initialize control and wait for the response which contains models.
        let init = serde_json::json!({
            "subtype": "initialize",
            "hooks": serde_json::Value::Null,
            "agentProgressSummaries": true,
            "forwardSubagentText": true,
        });

        match self.send_control(&init).await {
            Ok(result) => {
                let models: Vec<ModelOption> = result.get("models")
                    .and_then(|m| m.as_array())
                    .map_or(&[], |v| v)
                    .iter()
                    .filter_map(|entry| {
                        let value = entry.get("value")?.as_str()?;
                        Some(ModelOption {
                            id: value.to_string(),
                            name: entry.get("displayName")?.as_str().unwrap_or(value).to_string(),
                            detail: entry.get("description").and_then(|d| d.as_str()).map(|s| s.to_string()),
                            efforts: entry.get("supportedEffortLevels")
                                .and_then(|e| e.as_array())
                                .map_or(&[], |v| v)
                                .iter()
                                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                .collect(),
                            default_effort: None,
                            is_default: value == "default",
                            fast_tier: if entry.get("supportsFastMode").and_then(|v| v.as_bool()) == Some(true) {
                                Some("fast".into())
                            } else {
                                None
                            },
                        })
                    })
                    .collect();
                Ok(models)
            }
            Err(e) => Err(e),
        }
    }

    async fn read_commands(&mut self) -> Vec<SlashCommand> {
        // Commands come in the initialize response or as subsequent events.
        // For now return empty - they'll be populated when initialize arrives.
        Vec::new()
    }

    fn spawn_read_task(&mut self) {
        let handler = match self.event_handler.clone() {
            Some(h) => h,
            None => return,
        };

        let reader = match self.stdout_reader.take() {
            Some(s) => s,
            None => return,
        };

        self.read_handle = Some(tokio::spawn(async move {
            let mut line_reader = tokio::io::AsyncBufReadExt::lines(
                tokio::io::BufReader::new(reader)
            );

            loop {
                match line_reader.next_line().await {
                    Ok(Some(line)) => {
                        if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
                            ClaudeSession::dispatch_message(&value, &handler);
                        }
                    }
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
        }));
    }

    fn dispatch_message(message: &serde_json::Value, handler: &Arc<dyn Fn(ProviderEvent) + Send + Sync>) {
        let msg_type = match message.get("type").and_then(|t| t.as_str()) {
            Some(t) => t,
            None => return,
        };

        match msg_type {
            "control_response" => {
                // Control responses are handled via the pending_control map.
                // This is a simplified version - in practice we'd need shared state.
            }
            "system" => {
                if let Some(subtype) = message.get("subtype").and_then(|s| s.as_str()) {
                    match subtype {
                        "init" => {
                            if let Some(session_id) = message.get("session_id").and_then(|s| s.as_str()) {
                                handler(ProviderEvent::session_started(session_id.to_string()));
                            }
                        }
                        "compact_boundary" => {
                            handler(ProviderEvent::notice(Notice::new("info", "Context compacted.")));
                        }
                        _ => {}
                    }
                }
            }
            "stream_event" => {
                Self::handle_stream_event(message, handler);
            }
            "assistant" => {
                Self::handle_assistant(message, handler);
            }
            "result" => {
                Self::handle_result(message, handler);
            }
            "rate_limit_event" => {
                if let Some(info) = message.get("rate_limit_info") {
                    if info.get("status").and_then(|s| s.as_str()) == Some("rejected") {
                        handler(ProviderEvent::notice(Notice::new("warning",
                            "Claude hit a usage limit.")));
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_stream_event(message: &serde_json::Value, handler: &Arc<dyn Fn(ProviderEvent) + Send + Sync>) {
        let event = message.get("event");
        let event_type = match event.and_then(|e| e.get("type")).and_then(|t| t.as_str()) {
            Some(t) => t,
            None => return,
        };

        match event_type {
            "message_start" => {
                // Stream started - would track current message id
            }
            "content_block_start" => {
                if let Some(index) = event.and_then(|e| e.get("index")).and_then(|i| i.as_u64()) {
                    if let Some(block) = event.and_then(|e| e.get("content_block")) {
                        let block_type = block.get("type").and_then(|t| t.as_str()).unwrap_or("");
                        match block_type {
                            "text" => {
                                let text = block.get("text").and_then(|t| t.as_str()).unwrap_or("");
                                handler(ProviderEvent::message_chunk(text.to_string()));
                            }
                            "thinking" => {
                                let thinking = block.get("thinking").and_then(|t| t.as_str()).unwrap_or("");
                                handler(ProviderEvent::reasoning(thinking.to_string()));
                            }
                            "tool_use" => {
                                let tool_id = block.get("id").and_then(|i| i.as_str()).unwrap_or("");
                                let name = block.get("name").and_then(|n| n.as_str()).unwrap_or("unknown");
                                handler(ProviderEvent::tool_call(tool_id.to_string(), name.to_string(),
                                    serde_json::Value::Object(block.get("input").cloned().unwrap_or_default().as_object().cloned().unwrap_or_default())));
                            }
                            _ => {}
                        }
                    }
                }
            }
            "content_block_delta" => {
                if let Some(delta) = event.and_then(|e| e.get("delta")) {
                    let delta_type = delta.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    match delta_type {
                        "text_delta" => {
                            if let Some(text) = delta.get("text").and_then(|t| t.as_str()) {
                                handler(ProviderEvent::message_chunk(text.to_string()));
                            }
                        }
                        "thinking_delta" => {
                            if let Some(text) = delta.get("thinking").and_then(|t| t.as_str()) {
                                handler(ProviderEvent::reasoning(text.to_string()));
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_assistant(message: &serde_json::Value, handler: &Arc<dyn Fn(ProviderEvent) + Send + Sync>) {
        if let Some(body) = message.get("message") {
            if let Some(content) = body.get("content").and_then(|c| c.as_array()) {
                for block in content {
                    let block_type = block.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    match block_type {
                        "text" => {
                            let text = block.get("text").and_then(|t| t.as_str()).unwrap_or("");
                            handler(ProviderEvent::message_chunk(text.to_string()));
                        }
                        "thinking" => {
                            let text = block.get("thinking").and_then(|t| t.as_str()).unwrap_or("");
                            handler(ProviderEvent::reasoning(text.to_string()));
                        }
                        "tool_use" => {
                            let tool_id = block.get("id").and_then(|i| i.as_str()).unwrap_or("");
                            let name = block.get("name").and_then(|n| n.as_str()).unwrap_or("unknown");
                            let input = block.get("input")
                                .cloned()
                                .unwrap_or(serde_json::Value::Null);
                            handler(ProviderEvent::tool_call(tool_id.to_string(), name.to_string(),
                                input.as_object().cloned().unwrap_or_default()));
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    fn handle_result(message: &serde_json::Value, handler: &Arc<dyn Fn(ProviderEvent) + Send + Sync>) {
        let is_error = message.get("is_error").and_then(|e| e.as_bool()).unwrap_or(false)
            || message.get("subtype").and_then(|s| s.as_str()) != Some("success");

        if let Some(usage) = message.get("usage") {
            let used = usage.get("input_tokens").and_then(|t| t.as_u64()).unwrap_or(0)
                + usage.get("output_tokens").and_then(|t| t.as_u64()).unwrap_or(0)
                + usage.get("cache_read_input_tokens").and_then(|t| t.as_u64()).unwrap_or(0)
                + usage.get("cache_creation_input_tokens").and_then(|t| t.as_u64()).unwrap_or(0);
            if used > 0 {
                handler(ProviderEvent::usage(ContextUsage::new(used as usize, None)));
            }
        }

        let status = if is_error {
            crate::providers::session::SessionStatus::Failed
        } else {
            crate::providers::session::SessionStatus::Completed
        };

        handler(ProviderEvent::session_ended(status, None));
    }

    // Hydra prompt helpers
    fn claude_agents_spec(_hydra: &crate::types::HydraRun) -> String {
        // Returns a JSON array of agent definitions for --agents flag
        // Simplified: in production this would render full agent specs
        r#"[{"type": "agent", "name": "head", "description": "Hydra head"}]"#.into()
    }

    fn hydra_policy(_hydra: &crate::types::HydraRun) -> String {
        format!(
            "You have access to sub-agents. Use the Task tool to delegate work. Maximum {} heads.",
            _hydra.max_heads.unwrap_or(4)
        )
    }

    fn fallback_policy(_hydra: &crate::types::HydraRun) -> String {
        "Delegate work to available sub-agents using the Agent tool.".into()
    }
}
