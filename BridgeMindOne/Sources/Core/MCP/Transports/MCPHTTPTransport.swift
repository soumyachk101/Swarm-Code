//
// MCPHTTPTransport.swift
// HTTP/SSE Transport for MCP
//

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
        formatter.uuidString.lowercased()
    }
}

// MARK: - Request Validator

public protocol MCPHTTPRequestValidator: Sendable {
    func validate(_ request: URLRequest) throws
}

public struct MCPHTTPRequestValidatorImpl: MCPHTTPRequestValidator {
    private let allowedSchemes: [String]

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

        if let body = request.httpBody, !body.isEmpty {
            let json = try? JSONSerialization.jsonObject(with: body)
            if json == nil {
                throw MCPTransportError.validationFailed("Request body is not valid JSON")
            }
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
        private var parser: MCPSSEParser

        init(parser: MCPSSEParser) {
            self.parser = parser
        }

        mutating func next() async throws -> JSONValue? {
            let buffer = String(bytes: parser.data.dropFirst(parser.offset), encoding: .utf8) ?? ""
            guard !buffer.isEmpty else { return nil }

            guard let eventEnd = buffer.range(of: "\n\n") else {
                return nil
            }

            let eventBlock = String(buffer[..<eventEnd.lowerBound])
            parser.offset += eventEnd.lowerBound.utf16Offset(in: buffer) + 2

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
    public let baseURL: URL
    public let sessionID: String?
    public private(set) var isClosed = false

    private let sessionIDGenerator: MCPSessionIDGenerator
    private let validator: MCPHTTPRequestValidator
    private let contextProvider: MCPHTTPContextProviding
    private let tokenRefreshHandler: MCPTokenRefreshHandler

    private var urlSession: URLSession
    private let logger = Logger(subsystem: "com.bridgemind.mcp", category: "MCPHTTPTransport")
    private let streamState = StreamState()

    final class StreamState: @unchecked Sendable {
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
    ) {
        self.baseURL = baseURL
        let explicitID = configuration.sessionID ?? sessionIDGenerator.generate()
        self.sessionID = explicitID
        self.sessionIDGenerator = sessionIDGenerator
        self.validator = validator
        self.tokenRefreshHandler = tokenRefreshHandler

        let resolvedToken = configuration.bearerToken ?? ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_TOKEN"]

        self.contextProvider = MCPHTTPContextProvider(
            sessionID: explicitID,
            bearerToken: resolvedToken,
            defaultHeaders: configuration.additionalHeaders
        )

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        sessionConfig.waitsForConnectivity = true
        sessionConfig.allowsCellularAccess = true

        self.urlSession = URLSession(configuration: sessionConfig)
    }

    // MARK: Lifecycle

    public func connect() async throws {
        isClosed = false
    }

    public func disconnect() async {
        await close()
    }

    public func close() async {
        guard !isClosed else { return }
        isClosed = true

        urlSession.invalidateAndCancel()
        streamState.continuation?.finish()
        streamState.continuation = nil

        logger.info("MCPHTTPTransport closed")
    }

    // MARK: Send

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
        _ = try await sendRequest(message)
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
            try contextProvider.headers(for: &request)
            try validator.validate(request)

            let (bodyStream, response) = try await urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MCPTransportError.invalidResponse(status: status)
            }

            var accumulated = Data()
            for try await byte in bodyStream {
                accumulated.append(byte)

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
    ) -> MCPHTTPTransport {
        let explicitSessionID = ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_ID"]
            ?? configuration.sessionID

        let resolvedConfig = MCPHTTPTransport.Configuration(
            sessionID: explicitSessionID,
            bearerToken: configuration.bearerToken,
            timeout: configuration.timeout,
            maximumRetryCount: configuration.maximumRetryCount,
            additionalHeaders: configuration.additionalHeaders
        )

        return MCPHTTPTransport(
            baseURL: baseURL,
            configuration: resolvedConfig
        )
    }
}
