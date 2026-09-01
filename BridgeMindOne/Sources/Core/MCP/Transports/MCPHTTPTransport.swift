import Foundation
import os.log

// MARK: - Session ID Generator

public protocol MCPSessionIDGenerator: Sendable {
 func generate() -> String
}

public struct MCPSessionIDGeneratorImpl: MCPSessionIDGenerator {
 private let formatter: UUID

 public init(formatter: UUID = UUID()) {
 self.formatter = formatter
 }

 public func generate() -> String {
 let uuid = formatter.uuid
 return uuid.uuidString.lowercased()
 }
}

// MARK: - Request Validator

public protocol MCPHTTPRequestValidator: Sendable {
 func validate(_ request: URLRequest) throws
}

public struct MCPHTTPRequestValidatorImpl: MCPHTTPRequestValidator {
 private let allowedSchemes: [String] = ["https", "http"]

 public init(allowedSchemes: [String] = ["https", "http"]) {
 self.allowedSchemes = allowedSchemes
 }

 public func validate(_ request: URLRequest) throws {
 guard let url = request.url else {
 throw MCPTransportError.validationFailed("Request URL is nil")
 }

 guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
 throw MCPTransportError.validationFailed(
 "URL scheme '\(url.scheme ?? "nil")' not allowed. Allowed: \(allowedSchemes.joined(separator: ", "))"
 )
 }

 guard let method = request.httpMethod, !method.isEmpty else {
 throw MCPTransportError.validationFailed("HTTP method is empty")
 }

 if let body = request.httpBody, body.isEmpty == false {
 // Ensure body is valid JSON
 let json = try? JSONSerialization.jsonObject(with: body)
 if json == nil {
 throw MCPTransportError.validationFailed("Request body is not valid JSON")
 }
 }

 guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
 contentType.contains("application/json") else {
 throw MCPTransportError.validationFailed(
 "Missing or invalid Content-Type header (expected application/json)"
 )
 }
 }
}

// MARK: - Context Provider

public protocol MCPHTTPContextProviding: Sendable {
 func headers(for request: inout URLRequest) throws
 func shouldRetry(_ error: Error, statusCode: Int?) -> Bool
}

public struct MCPHTTPContextProvider: MCPHTTPContextProviding {
 private let sessionID: String?
 private let bearerToken: String?
 private let defaultHeaders: [String: String]

 public init(
 sessionID: String? = nil,
 bearerToken: String? = nil,
 defaultHeaders: [String: String] = [:]
 ) {
 self.sessionID = sessionID
 self.bearerToken = bearerToken
 self.defaultHeaders = defaultHeaders
 }

 public func headers(for request: inout URLRequest) throws {
 for (key, value) in defaultHeaders {
 request.setValue(value, forHTTPHeaderField: key)
 }

 if let token = bearerToken, !token.isEmpty {
 request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
 }

 if let sessionID = sessionID, !sessionID.isEmpty {
 request.setValue(sessionID, forHTTPHeaderField: "MCP-Session-Id")
 }
 }

 public func shouldRetry(_ error: Error, statusCode: Int?) -> Bool {
 if case MCPTransportError.networkUnavailable = error {
 return true
 }
 if let status = statusCode {
 return status == 429 || (500 ..< 600).contains(status)
 }
 return false
 }
}

// MARK: - SSE Stream Parser

internal struct MCPSSEParser: AsyncSequence {
 public typealias Element = JSONValue

 private let data: Data
 private var offset: Int = 0

 init(data: Data) {
 self.data = data
 }

 struct AsyncIterator: AsyncIteratorProtocol {
 private let parser: MCPSSEParser

 init(parser: MCPSSEParser) {
 self.parser = parser
 }

 mutating func next() async throws -> JSONValue? {
 // SSE format: lines of "field: value\n\n" separated events
 // We parse "data: <json>\n\n" events
 var buffer = String(bytes: parser.data.dropFirst(parser.offset), encoding: .utf8) ?? ""
 guard !buffer.isEmpty else { return nil }

 // Find the next double-newline separator (SSE event delimiter)
 guard let eventEnd = buffer.range(of: "\n\n") else {
 // Incomplete event — return nil, will arrive with more data
 return nil
 }

 let eventBlock = String(buffer[..<eventEnd.lowerBound])
 parser.offset += eventEnd.lowerBound.utf8Offset

 // Parse "data: <json>" lines within the event block
 let lines = eventBlock.split(separator: "\n")
 for line in lines {
 let trimmed = line.trimmingCharacters(in: .whitespaces)
 if trimmed.hasPrefix("data: ") {
 let jsonStr = String(trimmed.dropFirst(6))
 if let jsonData = jsonStr.data(using: .utf8) {
 do {
 let decoded = try JSONDecoder().decode(JSONValue.self, from: jsonData)
 return decoded
 } catch {
 throw MCPTransportError.malformedSSE("Invalid JSON in data line: \(error)")
 }
 }
 throw MCPTransportError.malformedSSE("Unable to encode data line")
 }
 }

 return nil
 }
 }

 func makeAsyncIterator() -> AsyncIterator {
 AsyncIterator(parser: self)
 }
}

// MARK: - Token Refresh

public enum MCPTokenRefreshHandler: Sendable {
 case none
 case custom(@Sendable () async throws -> String?)
}

// MARK: - MCPHTTPTransport

public final class MCPHTTPTransport: @unchecked Sendable {
    public typealias Message = JSONValue

 // MARK: Properties
 public let baseURL: URL
 public let sessionID: String?
 public private(set) var isClosed = false

 private let sessionIDGenerator: MCPSessionIDGenerator
 private let validator: MCPHTTPRequestValidator
 private let contextProvider: MCPHTTPContextProviding
 private let tokenRefreshHandler: MCPTokenRefreshHandler

 private var urlSession: URLSession
 private var activeSSETasks: [UUID] = []
 private let logger = Logger(subsystem: "com.bridgemind.mcp", category: "MCPHTTPTransport")
 private let streamState: StreamState

 struct StreamState: Sendable {
 var continuation: AsyncThrowingStream<JSONValue, Error>.Continuation?
 }

 // MARK: Configuration

 public struct Configuration: Sendable {
 public var sessionID: String?
 public var bearerToken: String?
 public var timeout: TimeInterval
 public var maximumRetryCount: Int
 public var additionalHeaders: [String: String]

 public init(
 sessionID: String? = nil,
 bearerToken: String? = nil,
 timeout: TimeInterval = 30,
 maximumRetryCount: Int = 3,
 additionalHeaders: [String: String] = [:]
 ) {
 self.sessionID = sessionID
 self.bearerToken = bearerToken
 self.timeout = timeout
 self.maximumRetryCount = maximumRetryCount
 self.additionalHeaders = additionalHeaders
 }
 }

 // MARK: Init

 public init(
 baseURL: URL,
 configuration: Configuration = Configuration(),
 sessionIDGenerator: MCPSessionIDGenerator = MCPSessionIDGeneratorImpl(),
 validator: MCPHTTPRequestValidator = MCPHTTPRequestValidatorImpl(),
 tokenRefreshHandler: MCPTokenRefreshHandler = .none
 ) async throws {
 self.baseURL = baseURL
 self.sessionID = configuration.sessionID ?? sessionIDGenerator.generate()
 self.sessionIDGenerator = sessionIDGenerator
 self.validator = validator
 self.tokenRefreshHandler = tokenRefreshHandler

 // Read bearer token from env if not provided
 let resolvedToken: String?
 if let explicit = configuration.bearerToken {
 resolvedToken = explicit
 } else {
 resolvedToken = ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_TOKEN"]
 }

 self.contextProvider = MCPHTTPContextProvider(
 sessionID: self.sessionID,
 bearerToken: resolvedToken,
 defaultHeaders: configuration.additionalHeaders
 )

 let sessionConfig = URLSessionConfiguration.default
 sessionConfig.timeoutIntervalForRequest = configuration.timeout
 sessionConfig.timeoutIntervalForResource = configuration.timeout
 sessionConfig.waitsForConnectivity = true
 sessionConfig.allowsCellularAccess = true

 self.urlSession = URLSession(configuration: sessionConfig)
 self.streamState = StreamState()

 logger.info("MCPHTTPTransport initialized for \(self.baseURL.absoluteString, privacy: .public) session \(self.sessionID ?? "nil", privacy: .public)")
    }

    // MARK: - Lifecycle

    public func connect() async throws {
        isClosed = false
    }

    public func disconnect() async {
        try? await close()
    }

    // MARK: - Send

    public func sendRequest(_ message: JSONValue) async throws -> JSONValue {
        guard !isClosed else {
            throw MCPTransportError.transportClosed
        }

        var request = try buildRequest(for: message)
        try validator.validate(request)
        try contextProvider.headers(for: &request)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MCPTransportError.invalidResponse(status: status)
        }

        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return json
        }
        return .object(["result": .string("ok")])
    }

    public func send(_ message: JSONValue) async throws {
 guard !isClosed else {
 throw MCPTransportError.transportClosed
 }

 var request = try buildRequest(for: message)
 try validator.validate(request)
 try contextProvider.headers(for: request: &request)

 var retriesRemaining = 0 // will be handled via config in future
 var lastError: Error?

 for attempt in 0 ..< 1 {
 do {
 let (data, response) = try await urlSession.data(for: request)
 guard let httpResponse = response as? HTTPURLResponse else {
 throw MCPTransportError.invalidResponse(status: -1)
 }

 switch httpResponse.statusCode {
 case 200 ... 299:
 return
 case 401:
 if case .custom(let refresh) = tokenRefreshHandler {
 let newToken = try await refresh()
 if let newToken {
 request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
 continue // retry once
 }
 }
 throw MCPTransportError.authenticationFailed
 case 409:
 // Session conflict — regenerate
 logger.warning("Session conflict, attempting reconnection")
 continue
 default:
 throw MCPTransportError.invalidResponse(status: httpResponse.statusCode)
 }
 } catch let error as MCPTransportError {
 throw error
 } catch {
 lastError = error
 }
 }

 if let error = lastError {
 throw error
 }
 }

 // MARK: Listen (SSE)

 public func listen() -> AsyncThrowingStream<JSONValue, Error> {
 AsyncThrowingStream { continuation in
 guard !isClosed else {
 continuation.finish(throwing: MCPTransportError.transportClosed)
 return
 }

 streamState.continuation = continuation

 Task { [weak self] in
 guard let self else {
 continuation.finish(throwing: MCPTransportError.transportClosed)
 return
 }

 await self.startSSEListening(continuation: continuation)
 }
 }
 }

 // MARK: Close

 public func close() async throws {
 guard !isClosed else { return }
 isClosed = true

 for taskID in activeSSETasks {
 urlSession.getAllTasks { tasks in
 tasks.filter { $0.taskIdentifier == taskID }.forEach { $0.cancel() }
 }
 }
 activeSSETasks.removeAll()

 streamState.continuation?.finish()
 streamState.continuation = nil

 logger.info("MCPHTTPTransport closed")
 }

 // MARK: Private Helpers

 private func buildRequest(for message: JSONValue) throws -> URLRequest {
 guard let url = URL(string: baseURL.absoluteString + "/mcp") else {
 throw MCPTransportError.validationFailed("Cannot construct MCP endpoint URL")
 }

 var request = URLRequest(url: url)
 request.httpMethod = "POST"
 request.setValue("application/json", forHTTPHeaderField: "Content-Type")
 request.setValue("keep-alive", forHTTPHeaderField: "Connection")
 request.setValue("application/json", forHTTPHeaderField: "Accept")

 let bodyData = try JSONEncoder().encode(message)
 request.httpBody = bodyData

 return request
 }

 private func startSSEListening(continuation: AsyncThrowingStream<JSONValue, Error>.Continuation) async {
 guard let sseURL = URL(string: baseURL.absoluteString + "/mcp/events") else {
 continuation.finish(throwing: MCPTransportError.validationFailed("Invalid SSE endpoint"))
 return
 }

 var request = URLRequest(url: sseURL)
 request.httpMethod = "GET"
 request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
 request.setValue("keep-alive", forHTTPHeaderField: "Connection")
 request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

 do {
 try contextProvider.headers(for request: &request)
 try validator.validate(request)

 let (bodyStream, response) = try await urlSession.bytes(for: request)
 guard let httpResponse = response as? HTTPURLResponse,
 (200 ... 299).contains(httpResponse.statusCode) else {
 let status = (response as? HTTPURLResponse)?.statusCode ?? -1
 throw MCPTransportError.invalidResponse(status: status)
 }

 // Accumulate raw bytes and parse SSE events
 var accumulated = Data()

 for try await byte in bodyStream {
 accumulated.append(byte)

 // Try parsing SSE from accumulated buffer
 let parser = MCPSSEParser(data: accumulated)
 var iterator = parser.makeAsyncIterator()

 while let message = try? await iterator.next() {
 continuation.yield(message)
 }
 }

 continuation.finish()
 } catch {
 if isClosed {
 continuation.finish()
 } else {
 continuation.finish(throwing: error)
 }
 }
 }
}

// MARK: - Convenience Factory

public enum MCPHTTPTransportFactory: Sendable {
 public static func create(
 baseURL: URL,
 configuration: MCPHTTPTransport.Configuration = MCPHTTPTransport.Configuration()
 ) async throws -> MCPHTTPTransport {
 let explicitSessionID = ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_ID"]
 ?? configuration.sessionID

 let resolvedConfig = MCPHTTPTransport.Configuration(
 sessionID: explicitSessionID,
 bearerToken: configuration.bearerToken,
 timeout: configuration.timeout,
 maximumRetryCount: configuration.maximumRetryCount,
 additionalHeaders: configuration.additionalHeaders
 )

 return try await MCPHTTPTransport(
 baseURL: baseURL,
 configuration: resolvedConfig
 )
 }
}
