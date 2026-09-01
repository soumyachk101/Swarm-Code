//
// MCPToolRouter.swift
// Bridges MCPToolRouter protocol to PluginRegistry transport layer
//
// This is the missing piece that dispatches tool calls from the chat engine
// to actual MCP plugins via their transports.

import Foundation

public actor MCPToolRouterImpl: MCPToolRouter, Sendable {
 private let pluginRegistry: PluginRegistry
 private let credentialStore: CredentialStore
 private let defaultTimeoutNanoseconds: UInt64

 public init(
 pluginRegistry: PluginRegistry,
 credentialStore: CredentialStore,
 defaultTimeoutSeconds: Int = 30
 ) {
 self.pluginRegistry = pluginRegistry
 self.credentialStore = credentialStore
 self.defaultTimeoutNanoseconds = UInt64(defaultTimeoutSeconds) * 1_000_000_000
 }

 // MARK: - MCPToolRouter

 public func callTool(_ call: ToolCall) async throws -> String {
 let pluginId = await extractPluginId(from: call.name)

 guard let transport = await pluginRegistry.transport(for: pluginId) else {
 throw ToolRouterError.pluginNotConnected(pluginId)
 }

 let request = JSONRPCRequest(
 id: UUID().uuidString,
 method: MCPMethod.toolsCall.rawValue,
 params: JSONValue.object([
 "name": .string(call.name),
 "arguments": .object(call.arguments.compactMapValues { $0 })
 ])
 )

 // Simple timeout pattern: race the request against a sleep
 try await withThrowingTaskGroup(of: String.self) { group in
 group.addTask {
 try await self.sendRequest(transport: transport, request: request)
 }

 group.addTask {
 try? await Task.sleep(nanoseconds: self.defaultTimeoutNanoseconds)
 throw ToolRouterError.timeout
 }

 if let result = try await group.next() {
 return result
 }
 throw ToolRouterError.timeout
 }
 }

 public func listAvailableTools(pluginIds: [String]?) async throws -> [MCPTool] {
 let allIds = await pluginRegistry.allPluginIds()
 let targets: [String]
 if let pluginIds = pluginIds, !pluginIds.isEmpty {
 targets = pluginIds
 } else {
 targets = allIds
 }

 var allTools: [MCPTool] = []

 for pluginId in targets {
 guard let transport = await pluginRegistry.transport(for: pluginId) else {
 continue
 }

 let request = JSONRPCRequest(
 id: UUID().uuidString,
 method: MCPMethod.toolsList.rawValue,
 params: JSONValue.object([:])
 )

 do {
 let response = try await transport.sendRequest(request)

 if let result = response.result, case .object(let dict) = result,
 let toolsArray = dict["tools"]?.arrayValue {
 for toolValue in toolsArray {
 if case .object(let toolDict) = toolValue,
 let name = toolDict["name"]?.stringValue,
 let description = toolDict["description"]?.stringValue {
 let schema = toolDict["inputSchema"] ?? JSONValue.object(["type": .string("object"), "properties": .object([:])])
 let fullName = "\(pluginId):\(name)"
 allTools.append(MCPTool(name: fullName, description: description, inputSchema: schema))
 }
 }
 }
 } catch {
 continue
 }
 }

 return allTools
 }

 // MARK: - Private

 private func extractPluginId(from toolName: String) async -> String {
 if let colonIndex = toolName.firstIndex(of: ":") {
 return String(toolName[..<colonIndex])
 }

 // Fallback: iterate over all plugins to find which owns this tool
 let allIds = await pluginRegistry.allPluginIds()
 for pluginId in allIds {
 if await pluginRegistry.isConnected(pluginId) {
 if toolName.lowercased().contains(pluginId.lowercased()) {
 return pluginId
 }
 }
 }
 return allIds.first { await pluginRegistry.isConnected($0) } ?? "unknown"
 }

 private func sendRequest(transport: AnyTransport, request: JSONRPCRequest) async throws -> String {
 let response = try await transport.sendRequest(request)

 if let error = response.error {
 throw ToolRouterError.remoteError(error.message)
 }

 if let result = response.result {
 return extractTextContent(from: result)
 }

 return "Tool executed successfully (no content)"
 }

 private func extractTextContent(from result: JSONValue) -> String {
 // MCP tool results have a "content" array with text blocks
 if case .object(let dict) = result,
 let contentArray = dict["content"]?.arrayValue {
 var texts: [String] = []
 for item in contentArray {
 if case .object(let itemDict) = item,
 let text = itemDict["text"]?.stringValue {
 texts.append(text)
 }
 }
 return texts.joined(separator: "\n")
 }

 // Fallback: just stringify the result
 if case .object(let dict) = result,
 let output = dict["output"]?.stringValue {
 return output
 }

 return String(describing: result)
 }
}

// MARK: - Errors

public enum ToolRouterError: Error, Equatable, LocalizedError {
 case pluginNotConnected(String)
 case executionFailed(String, String)
 case timeout
 case remoteError(String)

 public var errorDescription: String? {
 switch self {
 case .pluginNotConnected(let id):
 return "Plugin not connected: \(id). Connect it from the Plugins panel first."
 case .executionFailed(let tool, let reason):
 return "Tool '\(tool)' execution failed: \(reason)"
 case .timeout:
 return "Tool execution timed out after 30 seconds."
 case .remoteError(let msg):
 return "Remote tool error: \(msg)"
 }
 }
}
