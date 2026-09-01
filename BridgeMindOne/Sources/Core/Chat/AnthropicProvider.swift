//
// AnthropicProvider.swift
// Real Anthropic Claude Messages API implementation
//
// Uses URLSession with streaming SSE response parsing.
// Supports multi-turn context, tool definitions, and .
//

import Foundation

public struct AnthropicProvider: LLMProvider, Sendable {
 public let apiKey: String
 public let model: String
 public let baseURL: String
 public let maxTokens: Int
 public let temperature: Double

 public init(
 apiKey: String? = nil,
 model: String = "claude-sonnet-4-20250514",
 baseURL: String = "https://api.anthropic.com",
 maxTokens: Int = 4096,
 temperature: Double = 1.0
 ) {
 // Priority: explicit key → env var → empty (will fail at call time with a clear error)
 self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
 self.model = model
 self.baseURL = baseURL
 self.maxTokens = maxTokens
 self.temperature = temperature
 }

 public func apiKeyFromKeychain() async -> String {
 let store = CredentialStore()
 let identity = PluginIdentity(id: "anthropic", displayName: "Anthropic", type: .remote, authType: .apiKey)
 if let token = try? await store.retrieveToken(for: identity) {
 return token.accessToken
 }
 return apiKey
 }

 // MARK: - LLMProvider

 public func stream(context: [ChatMessage], tools: [MCPTool]) async throws -> AsyncStream<ChatStreamEvent> {
 let resolvedKey: String
 if apiKey.isEmpty {
 resolvedKey = await apiKeyFromKeychain()
 } else {
 resolvedKey = apiKey
 }

 guard !resolvedKey.isEmpty else {
 return AsyncStream { continuation in
 continuation.yield(.error("No Anthropic API key found. Set ANTHROPIC_API_KEY or save it in Settings > Engines."))
 continuation.finish()
 }
 }

 let requestBody = buildRequestBody(context: context, tools: tools)

 guard let url = URL(string: "\(baseURL)/v1/messages") else {
 return AsyncStream { continuation in
 continuation.yield(.error("Invalid API URL"))
 continuation.finish()
 }
 }

 var request = URLRequest(url: url)
 request.httpMethod = "POST"
 request.setValue("application/json", forHTTPHeaderField: "Content-Type")
 request.setValue(resolvedKey, forHTTPHeaderField: "x-api-key")
 request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
 request.setValue("claude-bridge-mind/1.0", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")

 do {
 let bodyData = try JSONEncoder().encode(requestBody)
 request.httpBody = bodyData

 let (stream, response) = try URLSession.shared.bytes(for: request)

 guard let httpResponse = response as? HTTPURLResponse else {
 return AsyncStream { continuation in
 continuation.yield(.error("Invalid server response"))
 continuation.finish()
 }
 }

 if httpResponse.statusCode != 200 {
 return AsyncStream { continuation in
 let errorDetail: String
 if let body = try? JSONDecoder().decode([String: String].self, from: Data(stream as! [UInt8])) {
 errorDetail = body["error"] ?? body["message"] ?? String(httpResponse.statusCode)
 } else {
 errorDetail = "HTTP \(httpResponse.statusCode)"
 }
 continuation.yield(.error("API error (\(httpResponse.statusCode)): \(errorDetail)"))
 continuation.finish()
 }
 }

 return AsyncStream { continuation in
 Task {
 do {
 let buffer = NSMutableData()
 for try await byte in stream {
 buffer.append(byte)
 let events = parseSSEBytes(buffer as Data)
 for event in events {
 continuation.yield(event)
 if case .done = event {
 continuation.finish()
 return
 }
 if case .error = event {
 continuation.finish()
 return
 }
 }
 }
 // Flush any remaining data
 let finalEvents = parseSSEBytes(buffer as Data)
 for event in finalEvents {
 continuation.yield(event)
 if case .done = event {
 continuation.finish()
 return
 }
 if case .error = event {
 continuation.finish()
 return
 }
 }
 continuation.yield(.done)
 continuation.finish()
 } catch {
 continuation.yield(.error(error.localizedDescription))
 continuation.finish()
 }
 }
 }

 } catch {
 return AsyncStream { continuation in
 continuation.yield(.error("Network error: \(error.localizedDescription)"))
 continuation.finish()
 }
 }
 }

 public func complete(context: [ChatMessage], tools: [MCPTool]) async throws -> ChatMessage {
 let stream = try await self.stream(context: context, tools: tools)
 var fullText = ""
 var toolCalls: [ToolCall] = []

 for await event in stream {
 switch event {
 case .chunk(let text):
 fullText += text
 case .toolCall(let call):
 toolCalls.append(call)
 case .message(let msg):
 return msg
 case .error(let msg):
 throw NSError(domain: "AnthropicProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
 case .done:
 break
 }
 }

 let toolCall = toolCalls.first
 return ChatMessage(
 role: .assistant,
 content: fullText,
 toolCall: toolCall,
 createdAt: Date()
 )
 }

 // MARK: - Request Body Builder

 private func buildRequestBody(context: [ChatMessage], tools: [MCPTool]) -> AnthropicMessagesRequest {
 // Separate system messages from conversation
 var systemMessages: [String] = []
 var conversation: [AnthropicMessage] = []

 for message in context {
 switch message.role {
 case .system:
 if let text = message.content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
 systemMessages.append(message.content)
 }
 case .user:
 var contentBlocks: [AnthropicContentBlock] = [.text(message.content)]
 // If this message triggered tool results, add them as user content
 if message.content.hasPrefix("[Tool Result]") {
 contentBlocks = [.text(message.content)]
 }
 conversation.append(.user(contentBlocks))
 case .assistant:
 var assistantBlocks: [AnthropicContentBlock] = []
 if let toolCall = message.toolCall {
 assistantBlocks.append(.toolUse(
 id: toolCall.id,
 name: toolCall.name,
 input: toolCall.arguments.compactMapValues { $0.stringValue ?? "" }
 ))
 }
 if !message.content.isEmpty {
 assistantBlocks.append(.text(message.content))
 }
 conversation.append(.assistant(assistantBlocks))
 case .tool:
 // Tool results come as user messages in Anthropic's format
 conversation.append(.user([.toolResult(id: message.toolCallId ?? UUID().uuidString, content: message.content)]))
 }
 }

 // If last message is from assistant with tool_use, we don't send it yet (the engine handles that)
 if let last = conversation.last, case .assistant = last {
 if conversation.count > 1, case .user = conversation[conversation.count - 2] {
 // keep the conversation as-is for multi-turn tool use
 }
 }

 // Convert MCP tools to Anthropic tool format
 let anthropicTools: [AnthropicToolDefinition] = tools.map { tool in
 let schema = tool.inputSchema.dictionaryValue ?? ["type": "object", "properties": [:]]
 return AnthropicToolDefinition(
 name: tool.name,
 description: tool.description,
 inputSchema: schema
 )
 }

 return AnthropicMessagesRequest(
 model: model,
 maxTokens: maxTokens,
 system: systemMessages.isEmpty ? nil : systemMessages.joined(separator: "\n\n"),
 messages: conversation,
 tools: anthropicTools.isEmpty ? nil : anthropicTools,
 temperature: temperature
 )
 }

 // MARK: - SSE Parser

 private func parseSSEBytes(_ buffer: Data) -> [ChatStreamEvent] {
 guard let text = String(data: buffer, encoding: .utf8) else { return [] }

 let lines = text.components(separatedBy: .newlines)
 var events: [ChatStreamEvent] = []
 var currentEventType = ""
 var currentData = ""

 for line in lines {
 let trimmed = line.trimmingCharacters(in: .whitespaces)

 if trimmed.isEmpty {
 if !currentData.isEmpty && !currentData.contains("[DONE]") {
 let event = parseAnthropicEvent(data: currentData)
 if let ev = event { events.append(ev) }
 }
 currentData = ""
 currentEventType = ""
 continue
 }

 if trimmed.hasPrefix("event:") {
 currentEventType = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
 } else if trimmed.hasPrefix("data:") {
 currentData = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
 }
 }

 return events
 }

 private func parseAnthropicEvent(data: String) -> ChatStreamEvent? {
 guard let jsonData = data.data(using: .utf8) else { return nil }

 // Try to parse as a dictionary first to check event type
 if let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
 // Check for error
 if let error = dict["error"] as? [String: Any] {
 let message = error["message"] as? String ?? "Unknown API error"
 return .error(message)
 }

 // Check for content block delta (streaming text)
 if let type = dict["type"] as? String, type == "content_block_delta",
 let delta = dict["delta"] as? [String: Any],
 let text = delta["text"] as? String {
 return .chunk(text)
 }

 // Check for content block start (tool use)
 if let type = dict["type"] as? String, type == "content_block_start",
 let contentBlock = dict["content_block"] as? [String: Any],
 let blockType = contentBlock["type"] as? String, blockType == "tool_use" {
 // Tool use started — signal via chunk with metadata
 return .chunk("[TOOL_USE_START]")
 }

 // Check for message_start
 if let type = dict["type"] as? String, type == "message_start" {
 return nil // ignore, just setup
 }

 // Check for message_delta (stop reason)
 if let type = dict["type"] as? String, type == "message_delta" {
 if let stopReason = dict["stop_reason"] as? String, stopReason == "tool_use" {
 return .chunk("[TOOL_USE_REQUEST]")
 }
 return .done
 }

 // Check for ping
 if let type = dict["type"] as? String, type == "ping" {
 return nil
 }
 }

 // Try parsing as structured Anthropic response types
 if let event = try? JSONDecoder().decode(AnthropicContentBlockDelta.self, from: jsonData) {
 if let text = event.delta?.text {
 return .chunk(text)
 }
 }

 if let event = try? JSONDecoder().decode(AnthropicMessageDelta.self, from: jsonData) {
 if event.stopReason == "end_turn" || event.stopReason == "stop_sequence" {
 return .done
 }
 if event.stopReason == "tool_use" {
 return .chunk("[TOOL_USE_REQUEST]")
 }
 }

 return nil
 }
}

// MARK: - Anthropic API Types

private struct AnthropicMessagesRequest: Codable {
 let model: String
 let maxTokens: Int
 let system: String?
 let messages: [AnthropicMessage]
 let tools: [AnthropicToolDefinition]?
 let temperature: Double

 enum CodingKeys: String, CodingKey {
 case model, messages, tools, temperature
 case maxTokens = "max_tokens"
 case system = "system"
 }
}

private enum AnthropicMessage: Codable, Equatable, Sendable {
 case user([AnthropicContentBlock])
 case assistant([AnthropicContentBlock])

 enum CodingKeys: String, CodingKey {
 case role
 case content
 }

 init(from decoder: Decoder) throws {
 let container = try decoder.container(keyedBy: CodingKeys.self)
 let role = try container.decode(String.self, forKey: .role)
 let content = try container.decode([AnthropicContentBlock].self, forKey: .content)

 switch role {
 case "user": self = .user(content)
 case "assistant": self = .assistant(content)
 default: throw DecodingError.dataCorruptedError(forKey: .role, in: container, debugDescription: "Unknown role: \(role)")
 }
 }

 func encode(to encoder: Encoder) throws {
 var container = encoder.container(keyedBy: CodingKeys.self)
 switch self {
 case .user(let blocks):
 try container.encode("user", forKey: .role)
 try container.encode(blocks, forKey: .content)
 case .assistant(let blocks):
 try container.encode("assistant", forKey: .role)
 try container.encode(blocks, forKey: .content)
 }
 }

 var role: String {
 switch self {
 case .user: return "user"
 case .assistant: return "assistant"
 }
 }
}

private enum AnthropicContentBlock: Codable, Equatable, Sendable {
 case text(String)
 case toolUse(id: String, name: String, input: [String: String])
 case toolResult(id: String, content: String)

 enum CodingKeys: String, CodingKey {
 case type, text, id, name, input, content
 }

 init(from decoder: Decoder) throws {
 let container = try decoder.container(keyedBy: CodingKeys.self)
 let type = try container.decode(String.self, forKey: .type)

 switch type {
 case "text":
 let text = try container.decode(String.self, forKey: .text)
 self = .text(text)
 case "tool_use":
 let id = try container.decode(String.self, forKey: .id)
 let name = try container.decode(String.self, forKey: .name)
 let input = try container.decode([String: String].self, forKey: .input)
 self = .toolUse(id: id, name: name, input: input)
 case "tool_result":
 let id = try container.decode(String.self, forKey: .id)
 let content = try container.decode(String.self, forKey: .content)
 self = .toolResult(id: id, content: content)
 default:
 throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
 }
 }

 func encode(to encoder: Encoder) throws {
 var container = encoder.container(keyedBy: CodingKeys.self)
 switch self {
 case .text(let text):
 try container.encode("text", forKey: .type)
 try container.encode(text, forKey: .text)
 case .toolUse(let id, let name, let input):
 try container.encode("tool_use", forKey: .type)
 try container.encode(id, forKey: .id)
 try container.encode(name, forKey: .name)
 try container.encode(input, forKey: .input)
 case .toolResult(let id, let content):
 try container.encode("tool_result", forKey: .type)
 try container.encode(id, forKey: .id)
 try container.encode(content, forKey: .content)
 }
 }
}

private struct AnthropicToolDefinition: Codable, Equatable, Sendable {
 let name: String
 let description: String
 let inputSchema: JSONValue
}

private struct AnthropicContentBlockDelta: Codable, Equatable, Sendable {
 let type: String?
 let delta: AnthropicDelta?
}

private struct AnthropicDelta: Codable, Equatable, Sendable {
 let type: String?
 let text: String?
 let partialJson: String?
}

private struct AnthropicMessageDelta: Codable, Equatable, Sendable {
 let type: String?
 let delta: AnthropicDelta?
 let stopReason: String?
}

// MARK: - Errors

public enum AnthropicProviderError: Error, Equatable, LocalizedError {
 case noAPIKey
 case networkError(String)
 case apiError(String, Int?)
 case streamingError(String)

 public var errorDescription: String? {
 switch self {
 case .noAPIKey:
 return "No Anthropic API key configured. Set ANTHROPIC_API_KEY or save it in Settings > Engines."
 case .networkError(let msg):
 return "Network error: \(msg)"
 case .apiError(let msg, let code):
 if let code { return "API error (\(code)): \(msg)" }
 return "API error: \(msg)"
 case .streamingError(let msg):
 return "Streaming error: \(msg)"
 }
 }
}
