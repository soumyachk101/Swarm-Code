//
// AnthropicProvider.swift
// Real Anthropic Claude Messages API implementation
//
// Uses URLSession with streaming SSE response parsing.
// Supports multi-turn context, tool definitions, and streaming.
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

 return AsyncStream { continuation in
 Task {
 do {
 var request = URLRequest(url: url)
 request.httpMethod = "POST"
 request.setValue("application/json", forHTTPHeaderField: "Content-Type")
 request.setValue(resolvedKey, forHTTPHeaderField: "x-api-key")
 request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

 let bodyData = try JSONEncoder().encode(requestBody)
 request.httpBody = bodyData

 let (byteStream, response) = try await URLSession.shared.bytes(for: request)

 guard let httpResponse = response as? HTTPURLResponse else {
 continuation.yield(.error("Invalid server response"))
 continuation.finish()
 return
 }

 if httpResponse.statusCode != 200 {
 let errorBody = String(decoding: Array(byteStream), as: UTF8.self)
 let truncated = String(errorBody.prefix(500))
 continuation.yield(.error("API error (\(httpResponse.statusCode)): \(truncated)"))
 continuation.finish()
 return
 }

 var buffer = [UInt8]()
 for try await byte in byteStream {
 buffer.append(byte)
 let events = parseSSEBytes(buffer)
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

 let finalEvents = parseSSEBytes(buffer)
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
 continuation.yield(.error("Network error: \(error.localizedDescription)"))
 continuation.finish()
 }
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
 systemMessages.append(message.content)
 case .user:
 var contentBlocks: [AnthropicContentBlock] = [.text(message.content)]
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
 conversation.append(.user([.toolResult(id: message.toolCallId ?? UUID().uuidString, content: message.content)]))
 }
 }

 // Convert MCP tools to Anthropic tool format
 let anthropicTools: [AnthropicToolDefinition] = tools.map { tool in
 let rawSchema = tool.inputSchema.dictionaryValue ?? ["type": "object", "properties": JSONValue.object([:])]
 let converted: [String: JSONValue] = rawSchema.mapValues { value in
 switch value {
 case .string(let s):
 if let data = s.data(using: .utf8),
 let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
 return JSONValue.object(decoded.mapValues { JSONValue($0) })
 }
 return .string(s)
 default:
 return value
 }
 }
 return AnthropicToolDefinition(
 name: tool.name,
 description: tool.description,
 inputSchema: JSONValue.object(converted)
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

 private func parseSSEBytes(_ buffer: [UInt8]) -> [ChatStreamEvent] {
 guard let text = String(bytes: buffer, encoding: .utf8) else { return [] }

 let lines = text.components(separatedBy: .newlines)
 var events: [ChatStreamEvent] = []
 var currentData = ""

 for line in lines {
 let trimmed = line.trimmingCharacters(in: .whitespaces)

 if trimmed.isEmpty {
 if !currentData.isEmpty && !currentData.contains("[DONE]") {
 let event = parseAnthropicEvent(data: currentData)
 if let ev = event { events.append(ev) }
 }
 currentData = ""
 continue
 }

 if trimmed.hasPrefix("data:") {
 currentData = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
 }
 }

 return events
 }

 private func parseAnthropicEvent(data: String) -> ChatStreamEvent? {
 guard let jsonData = data.data(using: .utf8) else { return nil }

 // Parse as dictionary to inspect event type
 guard let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
 return nil
 }

 // Error response
 if let error = dict["error"] as? [String: Any] {
 let message = error["message"] as? String ?? "Unknown API error"
 return .error(message)
 }

 // Content block delta — streaming text chunk
 if let type = dict["type"] as? String, type == "content_block_delta",
 let delta = dict["delta"] as? [String: Any],
 let text = delta["text"] as? String {
 return .chunk(text)
 }

 // Content block start (tool use beginning)
 if let type = dict["type"] as? String, type == "content_block_start" {
 return nil
 }

 // Message delta — signals completion or tool use
 if let type = dict["type"] as? String, type == "message_delta",
 let deltaDict = dict["delta"] as? [String: Any] {
 let stopReason = deltaDict["stop_reason"] as? String
 if stopReason == "tool_use" {
 return .chunk("[TOOL_USE_REQUEST]")
 }
 return .done
 }

 // Ping — no-op
 if let type = dict["type"] as? String, type == "ping" {
 return nil
 }

 return nil
 }
}

// MARK: - Anthropic API Types

private struct AnthropicMessagesRequest: Codable, Equatable, Sendable {
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
