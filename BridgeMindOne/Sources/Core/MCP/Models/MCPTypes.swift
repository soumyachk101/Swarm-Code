//
// MCPTypes.swift
// Core Model Context Protocol types
//

import Foundation

// MARK: - JSON-RPC 2.0

public struct JSONRPCRequest: Codable, Equatable {
 public let jsonrpc: String = "2.0"
 public let id: String
 public let method: String
 public let params: JSONValue?

 public init(id: String, method: String, params: JSONValue? = nil) {
 self.id = id
 self.method = method
 self.params = params
 }
}

public struct JSONRPCResponse: Codable, Equatable {
 public let jsonrpc: String = "2.0"
 public let id: String
 public let result: JSONValue?
 public let error: JSONRPCError?

 public init(id: String, result: JSONValue? = nil, error: JSONRPCError? = nil) {
 self.id = id
 self.result = result
 self.error = error
 }
}

public struct JSONRPCError: Codable, Equatable, Error {
 public let code: Int
 public let message: String
 public let data: JSONValue?

 public init(code: Int, message: String, data: JSONValue? = nil) {
 self.code = code
 self.message = message
 self.data = data
 }

 public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
 public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
 public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
 public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
 public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}

public struct JSONRPCNotification: Codable, Equatable {
 public let jsonrpc: String = "2.0"
 public let method: String
 public let params: JSONValue?
}

// MARK: - JSON Value (untyped)

public enum JSONValue: Codable, Sendable, Equatable {
 case string(String)
 case number(Double)
 case bool(Bool)
 case null
 case object([String: JSONValue])
 case array([JSONValue])

 public init(from decoder: Decoder) throws {
 let container = try decoder.singleValueContainer()
 if let v = try? container.decode(String.self) { self = .string(v); return }
 if let v = try? container.decode(Double.self) { self = .number(v); return }
 if let v = try? container.decode(Bool.self) { self = .bool(v); return }
 if container.decodeNil() { self = .null; return }
 if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
 if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
 throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
 }

 public func encode(to encoder: Encoder) throws {
 var container = encoder.singleValueContainer()
 switch self {
 case .string(let v): try container.encode(v)
 case .number(let v): try container.encode(v)
 case .bool(let v): try container.encode(v)
 case .null: try container.encodeNil()
 case .object(let v): try container.encode(v)
 case .array(let v): try container.encode(v)
 }
 }

 public var stringValue: String? {
 if case .string(let v) = self { return v }
 return nil
 }

 public var dictionaryValue: [String: JSONValue]? {
 if case .object(let v) = self { return v }
 return nil
 }

 public var arrayValue: [JSONValue]? {
 if case .array(let v) = self { return v }
 return nil
 }
}

// MARK: - MCP Protocol Types

public struct MCPTool: Codable, Equatable, Identifiable {
 public let name: String
 public let description: String
 public let inputSchema: JSONValue

 public var id: String { name }

 public init(name: String, description: String, inputSchema: JSONValue) {
 self.name = name
 self.description = description
 self.inputSchema = inputSchema
 }
}

public struct MCPResource: Codable, Equatable, Identifiable {
 public let uri: String
 public let name: String
 public let description: String?
 public let mimeType: String?

 public var id: String { uri }

 public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil) {
 self.uri = uri
 self.name = name
 self.description = description
 self.mimeType = mimeType
 }
}

public struct MCPPrompt: Codable, Equatable, Identifiable {
 public let name: String
 public let description: String?
 public let arguments: [MCPPromptArgument]?

 public var id: String { name }

 public init(name: String, description: String? = nil, arguments: [MCPPromptArgument]? = nil) {
 self.name = name
 self.description = description
 self.arguments = arguments
 }
}

public struct MCPPromptArgument: Codable, Equatable {
 public let name: String
 public let description: String?
 public let required: Bool

 public init(name: String, description: String? = nil, required: Bool = false) {
 self.name = name
 self.description = description
 self.required = required
 }
}

public struct MCPContent: Codable, Equatable {
 public let type: String
 public let text: String?
 public let data: String?
 public let mimeType: String?

 public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
 self.type = type
 self.text = text
 self.data = data
 self.mimeType = mimeType
 }
}

public struct MCPInitializeResult: Codable, Equatable {
 public let protocolVersion: String
 public let capabilities: MCPServerCapabilities
 public let serverInfo: MCPServerInfo

 public init(protocolVersion: String, capabilities: MCPServerCapabilities, serverInfo: MCPServerInfo) {
 self.protocolVersion = protocolVersion
 self.capabilities = capabilities
 self.serverInfo = serverInfo
 }
}

public struct MCPServerCapabilities: Codable, Equatable {
 public let tools: MCCToolsCapability?
 public let resources: MCPResourcesCapability?
 public let prompts: MCPPromptsCapability?
 public let logging: MCPLoggingCapability?

 public init(tools: MCCToolsCapability? = nil, resources: MCPResourcesCapability? = nil, prompts: MCPPromptsCapability? = nil, logging: MCPLoggingCapability? = nil) {
 self.tools = tools
 self.resources = resources
 self.prompts = prompts
 self.logging = logging
 }
}

public struct MCCToolsCapability: Codable, Equatable {
 public let listChanged: Bool?

 public init(listChanged: Bool? = nil) {
 self.listChanged = listChanged
 }
}

public struct MCPResourcesCapability: Codable, Equatable {
 public let subscribe: Bool?
 public let listChanged: Bool?

 public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
 self.subscribe = subscribe
 self.listChanged = listChanged
 }
}

public struct MCPPromptsCapability: Codable, Equatable {
 public let listChanged: Bool?

 public init(listChanged: Bool? = nil) {
 self.listChanged = listChanged
 }
}

public struct MCPLoggingCapability: Codable, Equatable {
 // empty for now
 public init() {}
}

public struct MCPServerInfo: Codable, Equatable {
 public let name: String
 public let version: String

 public init(name: String, version: String) {
 self.name = name
 self.version = version
 }
}

public struct MCPClientInfo: Codable, Equatable {
 public let name: String
 public let version: String

 public init(name: String, version: String) {
 self.name = name
 self.version = version
 }
}

// MARK: - MCP Methods

public enum MCPMethod: String, Codable, Equatable, CaseIterable {
 // Lifecycle
 case initialize = "initialize"
 case initialized = "notifications/initialized"
 case shutdown = "shutdown"
 case exit = "exit"

 // Tools
 case toolsList = "tools/list"
 case toolsCall = "tools/call"

 // Resources
 case resourcesList = "resources/list"
 case resourcesRead = "resources/read"
 case resourcesSubscribe = "resources/subscribe"
 case resourcesUnsubscribe = "resources/unsubscribe"

 // Prompts
 case promptsList = "prompts/list"
 case promptsGet = "prompts/get"

 // Logging
 case loggingSetLevel = "logging/setLevel"
 case loggingMessage = "notifications/message"

 // Ping
 case ping = "ping"
}

// MARK: - MCP Session

public struct MCPSession: Equatable {
 public let id: String
 public let createdAt: Date
 public let lastActivity: Date
 public var sessionToken: String?

 public init(id: String, createdAt: Date = Date(), lastActivity: Date = Date(), sessionToken: String? = nil) {
 self.id = id
 self.createdAt = createdAt
 self.lastActivity = lastActivity
 self.sessionToken = sessionToken
 }
}
