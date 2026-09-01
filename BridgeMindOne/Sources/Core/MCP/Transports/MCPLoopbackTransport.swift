//
// MCPLoopbackTransport.swift
// Loopback HTTP transport for local MCP plugin communication
//
// Bridges external DCC tools (Blender, Unity, Unreal, ...) to BridgeMindOne's
// MCP runtime over localhost HTTP with JSON-RPC 2.0.
//
// Design choices
// ---------------
// - Listener -- Network.framework NWListener (preferred) with a BSD-socket
// fallback so the transport still functions on older macOS.
// - Concurrency -- Each inbound connection is handled on its own Task; shared
// mutable state is guarded by a concurrent DispatchQueue with barrier writes
// so the class stays Sendable-compatible.
// - Routing -- Plugins identify themselves via the X-MCP-Plugin-ID request
// header (or the first URL path segment). A plugin must call registerHandler
// before the server will dispatch to it.
// - Lifecycle -- connect() starts the listener; disconnect() tears it down
// and closes every active plugin connection.
//

import Foundation

#if canImport(Network)
import Network
#endif

// MARK: - Public API

/// Loopback HTTP transport that exposes an MCP-compatible JSON-RPC 2.0
/// endpoint on localhost.
///
/// Plugins connect to `http://127.0.0.1:<port>/rpc` and POST JSON-RPC payloads.
/// They identify themselves with the `X-MCP-Plugin-ID` header so the transport
/// can route requests and maintain per-plugin state.
public final class MCPLoopbackTransport: MCPTransport {

	// MARK: Types

	/// Per-plugin handler that processes a JSON-RPC request and returns a
	/// JSON-RPC response (or `nil` for notifications that need no reply).
	public typealias PluginHandler = (
		_ pluginId: String,
		_ request: JSONRPCRequest
	) async -> JSONRPCResponse?

	/// Information about a connected plugin.
	public struct PluginConnection: Sendable, Equatable {
		public let id: String
		public let remoteAddress: String
		public let connectedAt: Date
		public var lastActivity: Date
		public var requestCount: Int

		public init(
			id: String,
			remoteAddress: String,
			connectedAt: Date = Date(),
			lastActivity: Date = Date(),
			requestCount: Int = 0
		) {
			self.id = id
			self.remoteAddress = remoteAddress
			self.connectedAt = connectedAt
			self.lastActivity = lastActivity
			self.requestCount = requestCount
		}
	}

	/// Descriptor for a single active listener/connection.
	private final class ActiveConnection: Sendable {
		let id: UUID
		let pluginId: String?
		let remoteAddress: String
		let connectedAt: Date
		private let sendLock = NSLock()
		private var stream: (any Stream)?

		init(
			pluginId: String?,
			remoteAddress: String,
			stream: (any Stream)?
		) {
			self.id = UUID()
			self.pluginId = pluginId
			self.remoteAddress = remoteAddress
			self.connectedAt = Date()
			self.stream = stream
		}

		func close() {
			sendLock.lock()
			defer { sendLock.unlock() }
			stream?.close()
			stream = nil
		}

		func send(_ data: Data) throws {
			sendLock.lock()
			defer { sendLock.unlock() }
			try stream?.write(data)
		}
	}

	// MARK: Configuration

	/// Port the listener binds to. `0` lets the OS pick a free port, which is
	/// then reported via `resolvedPort` after `connect()` completes.
	public let port: UInt16

	/// Actual port the listener is bound to (set after `connect()`).
	public private(set) var resolvedPort: UInt16?

	/// Maximum number of concurrent plugin connections.
	public let maxConnections: Int

	/// How long a plugin connection can be idle before it is closed.
	public let connectionIdleTimeout: TimeInterval

	// MARK: State

	public private(set) var isConnected: Bool = false
	public private(set) var sessionId: String?
	public var sessionToken: String?

	private let transportQueue = DispatchQueue(
		label: "BridgeMindOne.MCPLoopbackTransport",
		attributes: .concurrent
	)

	// Guarded by transportQueue barrier.
	private var listener: (any Listener)?
	private var connections: [UUID: ActiveConnection] = [:]
	private var handlers: [String: PluginHandler] = [:]
	private var connectionCount: Int = 0
	private var errorHandler: ((Error) -> Void)?

	// MARK: Init

	/// Create a new loopback transport.
	///
	/// - Parameters:
	/// - port: TCP port to listen on. Pass `0` for auto-assignment.
	/// - maxConnections: Upper bound on simultaneous plugin connections.
	/// - connectionIdleTimeout: Seconds of inactivity before a plugin socket is closed.
	public init(
		port: UInt16 = 8765,
		maxConnections: Int = 64,
		connectionIdleTimeout: TimeInterval = 300
	) {
		self.port = port
		self.maxConnections = maxConnections
		self.connectionIdleTimeout = connectionIdleTimeout
	}

	// MARK: - MCPTransport

	public func connect() async throws {
		try await withCheckedThrowingContinuation { continuation in
			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else {
					continuation.resume(throwing: MCPTransportError.ioError("Transport deallocated"))
					return
				}
				do {
					try self.startListener()
					self.isConnected = true
					self.sessionId = UUID().uuidString
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	public func disconnect() async {
		await withCheckedContinuation { continuation in
			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else { continuation.resume(); return }
				self.stopListener()
				self.isConnected = false
				self.sessionId = nil
				continuation.resume()
			}
		}
	}

	public func sendRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
		guard let pluginId = extractPluginId(from: request) else {
			throw MCPTransportError.invalidResponse
		}

		return try await withCheckedThrowingContinuation { continuation in
			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else {
					continuation.resume(throwing: MCPTransportError.ioError("Transport deallocated"))
					return
				}
				guard let connection = self.connections.values.first(where: { $0.pluginId == pluginId }) else {
					continuation.resume(throwing: MCPTransportError.serverNotAvailable)
					return
				}
				do {
					let payload = try JSONEncoder().encode(request)
					let httpBody = self.wrapJSONRPCInHTTP(body: payload)
					try connection.send(httpBody)
					continuation.resume(returning: JSONRPCResponse(
						id: request.id,
						result: .object([:])
					))
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	public func sendNotification(_ notification: JSONRPCNotification) async throws {
		let payload = try JSONEncoder().encode(notification)

		try await withCheckedThrowingContinuation { continuation in
			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else {
					continuation.resume(throwing: MCPTransportError.ioError("Transport deallocated"))
					return
				}
				let httpBody = self.wrapNotificationInHTTP(body: payload)
				for connection in self.connections.values {
					do { try connection.send(httpBody) } catch { /* best-effort */ }
				}
				continuation.resume()
			}
		}
	}

	public func listen() async throws -> AsyncStream<JSONValue> {
		AsyncStream { continuation in
			let token = UUID().uuidString
			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else {
					continuation.finish()
					return
				}
				self.handlers[token] = { [weak self] _, request in
					guard let self else { return nil }
					continuation.yield(.object([
						.string("id"): request.params ?? .null
					]))
					return JSONRPCResponse(id: request.id, result: .object([:]))
				}
			}
			continuation.onTermination = { @Sendable [weak self] in
				self?.transportQueue.async(flags: .barrier) {
					self?.handlers.removeValue(forKey: token)
				}
			}
		}
	}

	// MARK: - Plugin Registration

	/// Register an async handler for a specific plugin.
	public func registerHandler(for pluginId: String, handler: @escaping PluginHandler) {
		transportQueue.async(flags: .barrier) { [weak self] in
			self?.handlers[pluginId] = handler
		}
	}

	/// Remove the handler for a plugin (e.g., when a plugin disconnects).
	public func unregisterHandler(for pluginId: String) {
		transportQueue.async(flags: .barrier) { [weak self] in
			self?.handlers.removeValue(forKey: pluginId)
		}
	}

	/// Set a catch-all error handler for connection-level failures.
	public func onError(_ handler: @escaping @Sendable (Error) -> Void) {
		transportQueue.async(flags: .barrier) { [weak self] in
			self?.errorHandler = handler
		}
	}

	/// Snapshot of currently connected plugins.
	public var connectedPlugins: [PluginConnection] {
		get async {
			await withCheckedContinuation { continuation in
				transportQueue.sync { [weak self] in
					guard let self else { continuation.resume(returning: []); return }
					let snapshot = self.connections.values.map { conn in
						PluginConnection(
							id: conn.pluginId ?? "unknown-\(conn.id)",
							remoteAddress: conn.remoteAddress,
							connectedAt: conn.connectedAt,
							lastActivity: conn.connectedAt,
							requestCount: 0
						)
					}
					continuation.resume(returning: snapshot)
				}
			}
		}
	}

	// MARK: - Listener Lifecycle (private)

	private func startListener() throws {
		guard listener == nil else {
			throw MCPTransportError.ioError("Listener already active")
		}

		#if canImport(Network)
		let nwListener = try startNWListener()
		listener = nwListener
		#else
		let bsListener = try startBSDListener()
		listener = bsListener
		#endif
	}

	private func stopListener() {
		for connection in connections.values {
			connection.close()
		}
		connections.removeAll()
		connectionCount = 0
		listener?.stop()
		listener = nil
		resolvedPort = nil
	}

	// MARK: - Network.framework Listener

	#if canImport(Network)

	private class NWListenerTransport: NSObject, @unchecked Sendable, Listener {
		private let listener: NWListener
		private let handler: (Connection) -> Void

		init(listener: NWListener, handler: @escaping (Connection) -> Void) {
			self.listener = listener
			self.handler = handler
		}

		func start() {
			listener.start(queue: .main)
		}

		func stop() {
			listener.cancel()
		}
	}

	private func startNWListener() throws -> any Listener {
		let nwParameters = NWParameters.tcp
		nwParameters.requiredInterfaceType = .loopback
		nwParameters.allowLocalEndpointReuse = true

		let listener = try NWListener(using: nwParameters, on: .init(rawValue: Int(port)))

		let connectionHandler: (NWConnection) -> Void = { [weak self] nwConnection in
			guard let self else { return }
			self.handleNewConnection(nwConnection)
		}

		listener.newConnectionHandler = connectionHandler
		listener.stateUpdateHandler = { [weak self] state in
			switch state {
			case .ready:
				self?.transportQueue.async(flags: .barrier) {
					self?.resolvedPort = UInt16(listener.port!.rawValue)
				}
			case .failed(let error):
				self?.reportError(error)
				self?.transportQueue.async(flags: .barrier) {
					self?.listener = nil
					self?.isConnected = false
				}
			case .cancelled:
				self?.transportQueue.async(flags: .barrier) {
					self?.listener = nil
				}
			default:
				break
			}
		}

		let transport = NWListenerTransport(listener: listener) { connection in
			self.dispatchIncoming(connection)
		}
		transport.start()
		return transport
	}

	private func handleNewConnection(_ nwConnection: NWConnection) {
		transportQueue.async(flags: .barrier) { [weak self] in
			guard let self else { return }
			guard self.connectionCount < self.maxConnections else {
				nwConnection.cancel()
				return
			}
			self.connectionCount += 1
			nwConnection.start(queue: .main)
		}

		Task { [weak self] in
			guard let self else { return }
			do {
				let stream = try await NWConnectionStream(nwConnection)
				let remoteAddress = nwConnection.endpoint.debugDescription
				let active = ActiveConnection(
					pluginId: nil,
					remoteAddress: remoteAddress,
					stream: stream
				)

				transportQueue.async(flags: .barrier) {
					self.connections[active.id] = active
				}

				try await self.readLoop(connection: active, stream: stream)
			} catch {
				self.reportError(error)
				transportQueue.async(flags: .barrier) { [weak self] in
					guard let self else { return }
					self.connections.removeValue(forKey: active.id)
					self.connectionCount = max(0, self.connectionCount - 1)
				}
			}
		}
	}

	#endif

	// MARK: - BSD Socket Listener (fallback)

	private class BSDListenerTransport: NSObject, @unchecked Sendable, Listener {
		private let socket: Int32
		private let port: UInt16
		private let acceptQueue = DispatchQueue(label: "BridgeMindOne.BSDAccept")
		private let handler: (Connection) -> Void
		private var running = true
		private let stateLock = NSLock()

		init(socket: Int32, port: UInt16, handler: @escaping (Connection) -> Void) {
			self.socket = socket
			self.port = port
			self.handler = handler
		}

		func start() {
			acceptQueue.async { [weak self] in
				guard let self, self.running else { return }
				self.acceptLoop()
			}
		}

		func stop() {
			stateLock.lock()
			running = false
			stateLock.unlock()
			Darwin.shutdown(socket, SHUT_RDWR)
			Darwin.close(socket)
		}

		private func acceptLoop() {
			var addr = sockaddr_in()
			var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

			while true {
				stateLock.lock()
				let stillRunning = running
				stateLock.unlock()
				guard stillRunning else { break }

				let clientFd = withUnsafeMutablePointer(to: &addr) { addrPtr in
					addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
						Darwin.accept(socket, sockaddrPtr, &addrLen)
					}
				}

				guard clientFd >= 0 else { break }

				let remoteIP = withUnsafePointer(to: &addr) { ptr -> String in
					let ip = inet_ntoa(ptr.pointee.sin_addr)
					return ip.map { String(cString: $0) } ?? "unknown"
				}
				let remotePort = UInt16(addr.sin_port).bigEndian

				let stream = BSDStream(fd: clientFd)
				let connection = BSDConnection(
					remoteAddress: "\(remoteIP):\(remotePort)",
					stream: stream
				)
				handler(connection)
			}
		}
	}

	private func startBSDListener() throws -> any Listener {
		let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
		guard fd >= 0 else {
			throw MCPTransportError.ioError("socket() failed: \(Darwin.strerror(Darwin.errno) ?? "unknown")")
		}

		var opt: Int32 = 1
		setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

		var addr = sockaddr_in()
		addr.sin_family = sa_family_t(AF_INET)
		addr.sin_port = in_port_t(port).bigEndian
		addr.sin_addr = in_addr(s_addr: INADDR_ANY)

		let bindResult = withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}

		guard bindResult == 0 else {
			Darwin.close(fd)
			throw MCPTransportError.ioError("bind() failed: \(Darwin.strerror(Darwin.errno) ?? "unknown")")
		}

		guard Darwin.listen(fd, SOMAXCONN) == 0 else {
			Darwin.close(fd)
			throw MCPTransportError.ioError("listen() failed: \(Darwin.strerror(Darwin.errno) ?? "unknown")")
		}

		// Determine the actual bound port via getsockname.
		var boundAddr = sockaddr_in()
		var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
		withUnsafeMutablePointer(to: &boundAddr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.getsockname(fd, $0, &boundLen)
			}
		}

		let actualPort = UInt16(boundAddr.sin_port).bigEndian
		resolvedPort = actualPort

		let transport = BSDListenerTransport(socket: fd, port: actualPort) { [weak self] connection in
			self?.dispatchBSDFallback(connection)
		}
		transport.start()
		return transport
	}

	private func dispatchBSDFallback(_ connection: any Connection) {
		Task { [weak self] in
			guard let self else { return }
			transportQueue.async(flags: .barrier) {
				guard self.connectionCount < self.maxConnections else { return }
				self.connectionCount += 1
			}

			let stream = connection.stream
			let remoteAddress = connection.remoteAddress

			let active = ActiveConnection(
				pluginId: nil,
				remoteAddress: remoteAddress,
				stream: stream
			)

			transportQueue.async(flags: .barrier) {
				self.connections[active.id] = active
			}

			do {
				try await readLoop(connection: active, stream: stream)
			} catch {
				self.reportError(error)
			}

			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else { return }
				self.connections.removeValue(forKey: active.id)
				self.connectionCount = max(0, self.connectionCount - 1)
			}
		}
	}

	// MARK: - Read / Dispatch Loop

	private func readLoop(connection: ActiveConnection, stream: any Stream) async throws {
		var idleTimer: Task<Void, any Error>?
		var buffer = Data()

		while true {
			// Reset the idle timer on each read cycle.
			idleTimer?.cancel()
			idleTimer = Task { [weak self] in
				try await Task.sleep(nanoseconds: UInt64(self?.connectionIdleTimeout ?? 300) * 1_000_000_000)
				self?.transportQueue.async(flags: .barrier) {
					self?.closeConnection(connection)
				}
			}

			let chunk = try await stream.read()
			if chunk.isEmpty {
				break // EOF
			}

			buffer.append(chunk)

			// Try to extract complete HTTP requests from the buffer.
			while let request = extractHTTPRequest(from: &buffer) {
				idleTimer?.cancel()
				idleTimer = nil

				let pluginId = request.headers["X-MCP-Plugin-ID"]
					?? extractPluginId(fromPath: request.path)

				// Update connection metadata with the resolved plugin id.
				transportQueue.async(flags: .barrier) {
					if let existing = self.connections[connection.id] {
						let updated = ActiveConnection(
							pluginId: pluginId ?? existing.pluginId,
							remoteAddress: existing.remoteAddress,
							stream: existing.stream
						)
						self.connections[connection.id] = updated
					}
				}

				let response: Data
				do {
					response = try await handleRequest(
						pluginId: pluginId,
						request: request,
						connectionId: connection.id
					)
				} catch {
					response = buildHTTPResponse(statusCode: 500, headers: [:], body: error.localizedDescription)
				}

				try stream.write(response)
			}
		}

		idleTimer?.cancel()
	}

	private func dispatchIncoming(_ connection: any Connection) {
		// Entry point for Network.framework connections.
		Task { [weak self] in
			guard let self else { return }
			transportQueue.async(flags: .barrier) {
				guard self.connectionCount < self.maxConnections else { return }
				self.connectionCount += 1
			}

			let stream = connection.stream
			let remoteAddress = connection.remoteAddress

			let active = ActiveConnection(
				pluginId: nil,
				remoteAddress: remoteAddress,
				stream: stream
			)

			transportQueue.async(flags: .barrier) {
				self.connections[active.id] = active
			}

			do {
				try await readLoop(connection: active, stream: stream)
			} catch {
				self.reportError(error)
			}

			transportQueue.async(flags: .barrier) { [weak self] in
				guard let self else { return }
				self.connections.removeValue(forKey: active.id)
				self.connectionCount = max(0, self.connectionCount - 1)
			}
		}
	}

	// MARK: - HTTP Routing

	private struct ParsedHTTPRequest {
		let method: String
		let path: String
		let headers: [String: String]
		let body: Data
	}

	private func extractHTTPRequest(from buffer: inout Data) -> ParsedHTTPRequest? {
		// Find the end of headers (\r\n\r\n).
		guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
			return nil
		}

		let headerData = buffer.subdata(in: buffer.startIndex ..< headerEnd.lowerBound)
		let headerLines = String(data: headerData, encoding: .utf8)?
			.split(separator: "\r\n", omittingEmptySubsequences: false) ?? []

		guard let requestLine = headerLines.first else { return nil }
		let parts = requestLine.split(separator: " ", maxSplits: 2)
		guard parts.count >= 2 else { return nil }

		let method = String(parts[0]).uppercased()
		let path = String(parts[1])

		var headers: [String: String] = [:]
		for line in headerLines.dropFirst() {
			if let colonRange = line.firstIndex(of: ":") {
				let key = String(line[..<colonRange]).trimmingCharacters(in: .whitespaces)
				let value = String(line[line.index(after: colonRange)...]).trimmingCharacters(in: .whitespaces)
				headers[key] = value
			}
		}

		// Determine body length.
		let bodyStart = headerEnd.upperBound
		let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0

		let bodyStartOffset = buffer.startIndex.utf8Offset(in: buffer)
		guard buffer.count >= bodyStartOffset + contentLength else {
			return nil // Incomplete body -- wait for more data.
		}

		let body = buffer.subdata(
			in: bodyStart ..< buffer.index(bodyStart, offsetBy: contentLength)
		)
		buffer.removeSubrange(buffer.startIndex ..< buffer.index(bodyStart, offsetBy: contentLength))

		return ParsedHTTPRequest(method: method, path: path, headers: headers, body: body)
	}

	private func handleRequest(
		pluginId: String?,
		request: ParsedHTTPRequest,
		connectionId: UUID
	) async throws -> Data {
		switch (request.method, request.path) {
		case ("GET", "/health"):
			return buildHTTPResponse(
				statusCode: 200,
				headers: ["Content-Type": "application/json"],
				body: #"{"status":"ok","version":"1.0.0"}"#
			)

		case ("POST", "/rpc"):
			let resolvedPluginId = pluginId ?? "default"
			guard let handler = handlers[resolvedPluginId] else {
				return buildJSONRPCErrorResponse(
					requestId: nil,
					code: -32601,
					message: "No handler registered for plugin '\(resolvedPluginId)'"
				)
			}

			let rpcRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: request.body)

			// Handler returns nil for notifications (no response needed).
			let responseData = try await handler(resolvedPluginId, rpcRequest)
			if let response = responseData {
				let jsonData = try JSONEncoder().encode(response)
				return buildHTTPResponse(
					statusCode: 200,
					headers: ["Content-Type": "application/json"],
					body: String(data: jsonData, encoding: .utf8) ?? ""
				)
			} else {
				return buildHTTPResponse(statusCode: 204, headers: [:], body: "")
			}

		case ("GET", "/plugins"):
			let pluginList = handlers.keys.sorted().joined(separator: ",")
			return buildHTTPResponse(
				statusCode: 200,
				headers: ["Content-Type": "text/plain"],
				body: pluginList
			)

		default:
			return buildHTTPResponse(
				statusCode: 404,
				headers: ["Content-Type": "application/json"],
				body: #"{"error":"Not found"}"#
			)
		}
	}

	// MARK: - Helpers

	private func closeConnection(_ connection: ActiveConnection) {
		connection.close()
		connections.removeValue(forKey: connection.id)
		connectionCount = max(0, connectionCount - 1)
	}

	private func reportError(_ error: Error) {
		transportQueue.async(flags: .barrier) { [weak self] in
			self?.errorHandler?(error)
		}
	}

	private func extractPluginId(from request: JSONRPCRequest) -> String? {
		// Convention: plugin id encoded as the method namespace, e.g.
		// "blender/tools.list" rather than "plugin.blender/tools.list".
		let components = request.method.split(separator: "/", maxSplits: 1)
		if components.count >= 2, let namespace = components.first {
			return String(namespace)
		}
		return nil
	}

	private func extractPluginId(fromPath path: String) -> String? {
		// Convention: /rpc/{plugin-id}/...
		let components = path.split(separator: "/").map(String.init)
		if components.count >= 3, components[1] == "rpc" {
			return components[2]
		}
		return nil
	}

	private func wrapJSONRPCInHTTP(body: Data) -> Data {
		let headers = [
			"Content-Type: application/json",
			"Content-Length: \(body.count)",
			"Connection: close"
		]
		let headerString = headers.joined(separator: "\r\n")
		return "\(headerString)\r\n\r\n".data(using: .utf8)! + body
	}

	private func wrapNotificationInHTTP(body: Data) -> Data {
		wrapJSONRPCInHTTP(body: body)
	}

	private func buildHTTPResponse(statusCode: Int, headers: [String: String], body: String) -> Data {
		let statusText: String
		switch statusCode {
		case 200: statusText = "OK"
		case 204: statusText = "No Content"
		case 400: statusText = "Bad Request"
		case 404: statusText = "Not Found"
		case 500: statusText = "Internal Server Error"
		default: statusText = "Unknown"
		}

		var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
		for (key, value) in headers {
			response += "\(key): \(value)\r\n"
		}
		response += "Connection: close\r\n"
		response += "Content-Length: \(body.utf8.count)\r\n"
		response += "\r\n\(body)"
		return response.data(using: .utf8)!
	}

	private func buildJSONRPCErrorResponse(
		requestId: String?,
		code: Int,
		message: String
	) -> Data {
		let errorResponse = JSONRPCResponse(
			id: requestId ?? "",
			error: JSONRPCError(code: code, message: message)
		)
		let jsonData = (try? JSONEncoder().encode(errorResponse)) ?? Data()
		return buildHTTPResponse(
			statusCode: 200,
			headers: ["Content-Type": "application/json"],
			body: String(data: jsonData, encoding: .utf8) ?? ""
		)
	}

	/// Return the URL plugins should connect to.
	public var baseURL: URL {
		URL(string: "http://127.0.0.1:\(resolvedPort ?? port)")!
	}
}

// MARK: - MCPTransport Conformance

extension MCPLoopbackTransport {
	public typealias Message = JSONValue
}

// MARK: - Internal Protocols (Listener, Stream, Connection)

private protocol Listener: Sendable {
	func start()
	func stop()
}

private protocol Stream: Sendable {
	func read() async throws -> Data
	func write(_ data: Data) async throws
	func close()
}

private protocol Connection: Sendable {
	var remoteAddress: String { get }
	var stream: any Stream { get }
}

// MARK: - Network.framework Connection Wrapper

#if canImport(Network)

private actor NWConnectionStream: Stream {
	private let connection: NWConnection

	init(_ connection: NWConnection) {
		self.connection = connection
	}

	func read() async throws -> Data {
		try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}
				if isComplete {
					continuation.resume(returning: data ?? Data())
					return
				}
				continuation.resume(returning: data ?? Data())
			}
		}
	}

	func write(_ data: Data) async throws {
		try await withCheckedThrowingContinuation { continuation in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}

	func close() {
		connection.cancel()
	}
}

private struct NWConnectionTransport: Connection, Sendable {
	let remoteAddress: String
	let stream: any Stream

	init(_ connection: NWConnection) {
		self.remoteAddress = connection.endpoint.debugDescription
		self.stream = NWConnectionStream(connection)
	}
}

#endif

// MARK: - BSD Socket Connection Wrapper (fallback)

private final class BSDStream: Stream, @unchecked Sendable {
	private let fd: Int32
	private let lock = NSLock()
	private var closed = false

	init(fd: Int32) {
		self.fd = fd
		// Set non-blocking.
		var flags = fcntl(fd, F_GETFL, 0)
		flags |= O_NONBLOCK
		fcntl(fd, F_SETFL, flags)
	}

	func read() async throws -> Data {
		return try await withCheckedThrowingContinuation { continuation in
			lock.lock()
			guard !closed else {
				lock.unlock()
				continuation.resume(returning: Data())
				return
			}
			lock.unlock()

			let maxRead = 64 * 1024
			let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxRead)
			defer { buffer.deallocate() }

			let readCount = Darwin.read(fd, buffer, maxRead)
			if readCount < 0 {
				let err = Darwin.errno
				if err == EAGAIN || err == EWOULDBLOCK {
					self.pollRead(maxRead: maxRead, continuation: continuation)
					return
				}
				continuation.resume(throwing: MCPTransportError.ioError("read() error: \(err)"))
			} else if readCount == 0 {
				continuation.resume(returning: Data()) // EOF
			} else {
				continuation.resume(returning: Data(bytes: buffer, count: readCount))
			}
		}
	}

	private func pollRead(
		maxRead: Int,
		continuation: CheckedContinuation<Data, any Error>
	) {
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [weak self] in
			guard let self else { continuation.resume(returning: Data()); return }
			let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxRead)
			defer { buffer.deallocate() }
			let readCount = Darwin.read(self.fd, buffer, maxRead)
			if readCount < 0 {
				let err = Darwin.errno
				if err == EAGAIN || err == EWOULDBLOCK {
					self.pollRead(maxRead: maxRead, continuation: continuation)
					return
				}
				continuation.resume(throwing: MCPTransportError.ioError("read() error: \(err)"))
			} else if readCount == 0 {
				continuation.resume(returning: Data())
			} else {
				continuation.resume(returning: Data(bytes: buffer, count: readCount))
			}
		}
	}

	func write(_ data: Data) async throws {
		lock.lock()
		guard !closed else { lock.unlock(); return }
		lock.unlock()

		return try await withCheckedThrowingContinuation { continuation in
			data.withUnsafeBytes { rawPtr in
				guard let base = rawPtr.baseAddress else {
					continuation.resume()
					return
				}
				var totalWritten = 0

				func doWrite() {
					guard totalWritten < data.count else {
						continuation.resume()
						return
					}
					let written = Darwin.write(
						self.fd,
						base.advanced(by: totalWritten),
						data.count - totalWritten
					)
					if written < 0 {
						let err = Darwin.errno
						if err == EAGAIN || err == EWOULDBLOCK {
							DispatchQueue.global().asyncAfter(deadline: .now() + 0.001) {
								doWrite()
							}
							return
						}
						continuation.resume(throwing: MCPTransportError.ioError("write() error: \(err)"))
						return
					}
					totalWritten += written
					doWrite()
				}
				doWrite()
			}
		}
	}

	func close() {
		lock.lock()
		closed = true
		lock.unlock()
		Darwin.shutdown(fd, SHUT_RDWR)
		Darwin.close(fd)
	}
}

private struct BSDConnection: Connection, Sendable {
	let remoteAddress: String
	let stream: any Stream

	init(remoteAddress: String, stream: any Stream) {
		self.remoteAddress = remoteAddress
		self.stream = stream
	}
}
