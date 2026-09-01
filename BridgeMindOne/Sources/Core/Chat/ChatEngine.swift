//
// ChatEngine.swift
// Chat turn orchestration and streaming
//

import Foundation

// MARK: - Chat Turn Engine

public protocol ChatTurnEngine: Sendable {
 func executeTurn(
 session: ChatSession,
 message: ChatMessage,
 tools: [MCPTool]
 ) async throws -> AsyncStream<ChatStreamEvent>
}

public struct BatchedChatTurnEngine: ChatTurnEngine {
 private let llmProvider: LLMProvider
 private let toolRouter: MCPToolRouter

 public init(llmProvider: LLMProvider, toolRouter: MCPToolRouter) {
 self.llmProvider = llmProvider
 self.toolRouter = toolRouter
 }

    public func executeTurn(
        session: ChatSession,
        message: ChatMessage,
        tools: [MCPTool]
    ) -> AsyncStream<ChatStreamEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    // Build messages context
                    let context = buildContext(session: session, newMessage: message)

                    // Check if tools should be used
                    let shouldUseTools = !tools.isEmpty && message.shouldUseTools

                    if shouldUseTools {
                        // First: get tool call from LLM
                        let stream = try await llmProvider.stream(context: context, tools: tools)
                        for try await event in stream {
                            if case .toolCall(let call) = event {
                                // Execute tool via MCP
                                let result = try await toolRouter.callTool(call)
                                let toolMessage = ChatMessage(
                                    id: UUID().uuidString,
                                    role: .tool,
                                    content: result,
                                    toolCallId: call.id,
                                    createdAt: Date()
                                )
                                continuation.yield(.message(toolMessage))

                                // Send result back to LLM for final response
                                let finalStream = try await llmProvider.stream(context: context + [toolMessage], tools: tools)
                                for try await finalEvent in finalStream {
                                    continuation.yield(finalEvent)
                                    if case .done = finalEvent {
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                            continuation.yield(event)
                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    } else {
                        // Simple chat without tools
                        let stream = try await llmProvider.stream(context: context, tools: [])
                        for try await event in stream {
                            continuation.yield(event)
                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Chat Stream Events

public enum ChatStreamEvent: Equatable {
    case chunk(String)
    case toolCall(ToolCall)
    case message(ChatMessage)
    case error(String)
    case done
}

// MARK: - Chat Models

public struct ChatSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var agentId: String
    public var messages: [ChatMessage]
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        agentId: String = "claude",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.title = title
        self.agentId = agentId
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let toolCall: ToolCall?
    public let toolCallId: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        toolCall: ToolCall? = nil,
        toolCallId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCall = toolCall
        self.toolCallId = toolCallId
        self.createdAt = createdAt
    }
}

public enum MessageRole: String, Codable, Equatable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: JSONValue]

    public init(id: String = UUID().uuidString, name: String, arguments: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - LLM Provider

public protocol LLMProvider: Sendable {
 func stream(context: [ChatMessage], tools: [MCPTool]) async throws -> AsyncStream<ChatStreamEvent>
 func complete(context: [ChatMessage], tools: [MCPTool]) async throws -> ChatMessage
}

// MARK: - Tool Router

public protocol MCPToolRouter: Sendable {
 func callTool(_ call: ToolCall) async throws -> String
 func listAvailableTools(pluginIds: [String]?) async throws -> [MCPTool]
}

// MARK: - Chat Stream Parser

public struct ChatStreamParser {
    public static func parseSSEChunk(_ chunk: Data) -> [ChatStreamEvent] {
        guard let text = String(data: chunk, encoding: .utf8) else { return [] }

        let lines = text.components(separatedBy: .newlines)
        var events: [ChatStreamEvent] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data: ") {
                let payload = String(trimmed.dropFirst(6))
                if payload == "[DONE]" {
                    events.append(.done)
                    continue
                }
                if let data = payload.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(StreamingChunk.self, from: data) {
                    if let content = parsed.choices.first?.delta.content {
                        events.append(.chunk(content))
                    }
                }
            }
        }

        return events
    }
}

private struct StreamingChunk: Codable {
 let choices: [StreamChoice]
}

private struct StreamChoice: Codable {
 let delta: DeltaContent
 let finishReason: String?
}

private struct DeltaContent: Codable {
 let content: String?
 let role: String?
}

// MARK: - Helpers

private func buildContext(session: ChatSession, newMessage: ChatMessage) -> [ChatMessage] {
 // injection from skills
 var context = session.messages
 context.append(newMessage)
 return context
 }

extension ChatMessage {
 var shouldUseTools: Bool {
 !content.contains("NO_TOOLS") && !content.contains("[SILENT]")
 }
}
