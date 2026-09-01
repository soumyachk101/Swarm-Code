//
// MCPTransport.swift
// Protocol for all MCP transports
//

import Foundation

/// Errors that can occur during MCP transport operations
public enum MCPTransportError: Error, Equatable {
 case notConnected
 case invalidResponse
 case timeout
 case processFailed(Int32)
 case ioError(String)
 case unsupportedProtocolVersion(String)
 case protocolViolation(String)
 case sessionRequired
 case serverNotAvailable
}

/// MCP transport abstraction — all transports (stdio, HTTP/SSE, loopback) implement this
public protocol MCPTransport: AnyObject, Sendable {
 associatedtype Message

 /// Connected state
 var isConnected: Bool { get async }

 /// Connect to the MCP server
 func connect() async throws

 /// Disconnect from the MCP server
 func disconnect() async

 /// Send a request and wait for response
 func sendRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse

 /// Send a notification (fire-and-forget)
 func sendNotification(_ notification: JSONRPCNotification) async throws

 /// Listen for server-sent notifications/messages
 func listen() async throws -> AsyncStream<JSONValue>

 /// Current session ID if any
 var sessionId: String? { get }

 /// Session token for authentication
 var sessionToken: String? { get set }
}

// MARK: - MCP HTTP Client Authorizer

public protocol MCPHTTPClientAuthorizer: Sendable {
 func authorize(request: inout URLRequest, session: MCPSession?) async throws
}

// MARK: - MCP HTTP Context Provider

public protocol MCPHTTPContextProviding: Sendable {
 func context(for session: MCPSession) async -> [String: String]
}

// MARK: - MCP Session Management

public protocol MCPSessionManaging: Sendable {
 func createSession() async -> MCPSession
 func getSession(id: String) async -> MCPSession?
 func updateSession(_ session: MCPSession) async
 func deleteSession(id: String) async
 func allSessions() async -> [MCPSession]
}

// MARK: - MCP Network Connection Protocol

public protocol MCPNetworkConnectionProtocol: Sendable {
 func connect(to url: URL) async throws
 func disconnect() async
 func send(_ data: Data) async throws
 func receive() async throws -> Data
 var isConnected: Bool { get }
}
