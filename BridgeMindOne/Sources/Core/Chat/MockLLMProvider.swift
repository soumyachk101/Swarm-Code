//
// MockLLMProvider.swift
// Mock LLM provider for testing/development
//

import Foundation

public struct MockLLMProvider: LLMProvider {
    public init() {}

    public func stream(context: [ChatMessage], tools: [MCPTool]) async throws -> AsyncStream<ChatStreamEvent> {
        AsyncStream { continuation in
            Task {
                let lastMessage = context.last?.content ?? ""

                // Simulate thinking delay
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Generate a response
                let response: String
                if lastMessage.isEmpty {
                    response = "Hello! I'm BridgeMind One, your AI development orchestrator. How can I help you today?"
                } else if lastMessage.lowercased().contains("hello") || lastMessage.lowercased().contains("hi") {
                    response = "Hello! I am connected and ready to orchestrate your AI coding agents, execute MCP tools, and manage development workflows."
                } else {
                    response = "I have received your instruction: \"\(lastMessage)\".\n\nI can assist you with:\n• Running Claude Code, Codex, Cursor, Copilot, or Aider\n• Utilizing 24 connected MCP plugins\n• Executing specialized skills\n• Persisting your development session"
                }

                continuation.yield(.chunk(response))
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    public func complete(context: [ChatMessage], tools: [MCPTool]) async throws -> ChatMessage {
        let stream = try await self.stream(context: context, tools: tools)
        var fullText = ""
        for await event in stream {
            if case .chunk(let text) = event {
                fullText += text
            }
        }
        return ChatMessage(role: .assistant, content: fullText)
    }
}

public struct MockToolRouter: MCPToolRouter {
    public init() {}

    public func callTool(_ call: ToolCall) async throws -> String {
        return "Tool '\(call.name)' executed successfully."
    }

    public func listAvailableTools(pluginIds: [String]?) async throws -> [MCPTool] {
        return []
    }
}

