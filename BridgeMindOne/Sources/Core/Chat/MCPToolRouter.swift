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
 private let defaultTimeout: Duration

 public init(
 pluginRegistry: PluginRegistry,
 credentialStore: CredentialStore,
 defaultTimeout: Duration = .seconds(30)
 ) {
 self.pluginRegistry = pluginRegistry
 self.credentialStore = credentialStore
 self.defaultTimeout = defaultTimeout
 }

 // MARK: - MCPToolRouter

 public func callTool(_ call: ToolCall) async throws -> String {
 let pluginId = extractPluginId(from: call.name)

 guard let transport = pluginRegistry.transport(for: pluginId) else {
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

 do {
 let response = try await withThrowingTaskGroup(of: String.self) { group in
 group.addTask {
 try await self.sendWithTimeout(transport: transport, request: request)
 }
 for try await result in group {
 return result
 }
 throw NSError(domain: "MCPToolRouter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result from tool execution"])
 }
 } catch {
 throw ToolRouterError.executionFailed(call.name, error.localizedDescription)
 }
 }

 public func listAvailableTools(pluginIds: [String]?) async throws -> [MCPTool] {
 let targets: [String]
 if let pluginIds = pluginIds, !pluginIds.isEmpty {
 targets = pluginIds
 } else {
 targets = Array(pluginRegistry.allPluginIds())
 }

 var allTools: [MCPTool] = []

 for pluginId in targets {
 guard let transport = pluginRegistry.transport(for: pluginId) else {
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
 // Skip tools from plugins that fail to respond
 continue
 }
 }

 return allTools
 }

 // MARK: - Private

 private func extractPluginId(from toolName: String) -> String {
 // Tool names may be prefixed with "pluginId:toolName" or just "toolName"
 if let colonIndex = toolName.firstIndex(of: ":") {
 return String(toolName[..<colonIndex])
 }
 // Fallback: check all connected plugins to find which owns this tool
 return findOwningPlugin(for: toolName) ?? "unknown"
 }

 private func findOwningPlugin(for toolName: String) -> String? {
 let allIds = pluginRegistry.allPluginIds()
 for pluginId in allIds {
 if pluginRegistry.isConnected(pluginId) {
 // Quick heuristic: check if tool name contains plugin identifier
 if toolName.lowercased().contains(pluginId.lowercased()) {
 return pluginId
 }
 }
 }
 // Default: return first connected plugin (should be refined by the caller)
 return allIds.first { pluginRegistry.isConnected($0) }
 }

 private func sendWithTimeout(transport: AnyTransport, request: JSONRPCRequest) async throws -> String {
 try await withThrowingTaskGroup(of: String.self) { group in
 group.addTask {
 let response = try await transport.sendRequest(request)

 if let error = response.error {
 throw ToolRouterError.remoteError(error.message)
 }

 if let result = response.result {
 // Extract text content from tool result
 return extractTextContent(from: result)
 }

 return "Tool executed successfully (no content)"
 }

 // Timeout after defaultTimeout
 group.addTask {
 try? await Task.sleep(nanoseconds: UInt64(self.defaultTimeout.inNanoseconds))
 throw ToolRouterError.timeout
 }

 let result = try await group.next()!
 return result
 }
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

// MARK: - Duration helper

extension Duration {
 static func seconds(_ s: Int) -> Duration {
 .seconds(Double(s))
 }

 var inNanoseconds: UInt64 {
 UInt64(self.timeInterval * 1_000_000_000)
 }
}
