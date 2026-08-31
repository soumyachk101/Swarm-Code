//
// MockLLMProvider.swift
// Mock LLM provider for testing/development
//

import Foundation
import Core

public struct MockLLMProvider: LLMProvider {
 public init() {}

 public func stream(context: [ChatMessage], tools: [MCPTool]) -> AsyncStream<ChatStreamEvent> {
 AsyncStream { continuation in
 Task {
 let lastMessage = context.last?.content ?? ""

 // Simulate thinking delay
 try? await Task.sleep(nanoseconds: 500_000_000)

 // Generate a simple response
 let response: String
 if lastMessage.isEmpty {
 response = "Hello! I'm ready to help. What would you like to work on?"
 } else if lastMessage.count < 50 {
 response = "I understand you said: \"\(lastMessage)\". How can I help with that?"
 } else {
 response = "I've processed your message. Here's what I found:\n\n• Your message is \(lastMessage.count) characters\n• It contains \(lastMessage.components(separatedBy: " ").count) words\n• I'm ready to help you with any coding or development task.\n\nTry using the available plugins to access external services, or ask me to research, debug, or write code."
 }

 continuation.yield(.chunk(response))
 continuation.yield(.done)
 continuation.finish()
 }
 }
 }
}

public struct MockToolRouter: MCPToolRouter {
 public init() {}

 public func callTool(_ call: ToolCall) async throws -> String {
 return "Tool '\(call.name)' executed with arguments: \(call.arguments)"
 }

 public func listAvailableTools(pluginIds: [String]?) async throws -> [MCPTool] {
 return []
 }
}
