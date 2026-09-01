//
// MCPTransport.swift
// Protocol for all MCP transports
//

import Foundation

/// Errors that can occur during MCP transport operations
public enum MCPTransportError: LocalizedError, Equatable, Sendable {
    case notConnected
    case invalidResponse(status: Int = -1)
    case timeout
    case processFailed(Int32)
    case ioError(String)
    case unsupportedProtocolVersion(String)
    case protocolViolation(String)
    case sessionRequired
    case serverNotAvailable
    case transportClosed
    case validationFailed(String)
    case authenticationFailed
    case sessionRejected
    case connectionFailed(String)
    case malformedSSE(String)
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP server"
        case .invalidResponse(let status): return "Invalid response from MCP server (status: \(status))"
        case .timeout: return "Request timed out"
        case .processFailed(let code): return "MCP process failed with exit code \(code)"
        case .ioError(let msg): return "I/O error: \(msg)"
        case .unsupportedProtocolVersion(let v): return "Unsupported MCP version: \(v)"
        case .protocolViolation(let msg): return "MCP protocol violation: \(msg)"
        case .sessionRequired: return "Session required for this operation"
        case .serverNotAvailable: return "MCP server not available"
        case .transportClosed: return "MCP transport closed"
        case .validationFailed(let msg): return "Validation failed: \(msg)"
        case .authenticationFailed: return "Authentication failed"
        case .sessionRejected: return "Session rejected by server"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .malformedSSE(let msg): return "Malformed SSE: \(msg)"
        case .networkUnavailable: return "Network unavailable"
        }
    }
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
