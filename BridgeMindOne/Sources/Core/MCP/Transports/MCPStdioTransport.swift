import Foundation

// MARK: - MCPStdioTransport

/// Stdio-based MCP transport that launches a local server process and communicates
/// via newline-delimited JSON-RPC 2.0 messages over stdin/stdout.
///
/// Lifecycle:
/// 1. Call `connect()` to launch the server process and open pipes.
/// 2. Use `sendRequest(_:)` / `sendNotification(_:)` to communicate.
/// 3. Use `listen()` to receive unsolicited messages from the server.
/// 4. Call `disconnect()` to terminate the process and clean up.
///
/// If the process exits unexpectedly, all pending requests are failed and the
/// listen stream is closed automatically.
///
public final class MCPStdioTransport: @unchecked Sendable {

 // MARK: - Configuration

 /// Immutable configuration for the stdio transport.
 public struct Configuration: Sendable {

 /// Path to the server executable (e.g. `"npx"`, `"node"`, `"python3"`,
 /// or an absolute path to a compiled binary).
 public let executable: String

 /// Arguments forwarded to the executable.
 public let arguments: [String]

 /// Working directory for the child process. Defaults to the current
 /// process's working directory when `nil`.
 public let workingDirectory: String?

 /// Environment variables injected into the child process.
 ///
 /// These values take precedence over the current process environment.
 /// Typical use: auth tokens, `PATH` overrides, feature flags.
 public let environment: [String: String]

 /// Per-request timeout. Requests that don't receive a response within
 /// this window fail with `.timeout`.
 public let requestTimeout: Duration

 /// Optional handler invoked for each complete line written to the
 /// child process's stderr. Called on a dedicated background task.
 public let stderrLogHandler: (@Sendable (String) -> Void)?

 public init(
 executable: String,
 arguments: [String] = [],
 workingDirectory: String? = nil,
 environment: [String: String] = [:],
 requestTimeout: Duration = .seconds(30),
 stderrLogHandler: (@Sendable (String) -> Void)? = nil
 ) {
 self.executable = executable
 self.arguments = arguments
 self.workingDirectory = workingDirectory
 self.environment = environment
 self.requestTimeout = requestTimeout
 self.stderrLogHandler = stderrLogHandler
 }
 }

 // MARK: - MCPTransport Protocol Properties

 public var sessionId: String?

 public var sessionToken: String? {
 get { _sessionToken }
 set { _sessionToken = newValue }
 }

 private var _sessionToken: String?

 public var isConnected: Bool {
 get async {
 stateLock.perform {
 let running = process?.isRunning ?? false
 return running && !terminated
 }
 }
 }

 // MARK: - Private State

 private let configuration: Configuration

 // Process lifecycle
 private var process: Process?
 private var stdinPipe: Pipe?
 private var stdoutPipe: Pipe?
 private var stderrPipe: Pipe?
 private var terminated: Bool = false

 // Pending JSON-RPC requests keyed by request ID.
 private var pendingRequests: [String: CheckedContinuation<JSONRPCResponse, any Error>] = [:]
 private let pendingRequestsLock = NSLock()

 // Listen stream
 private var listenContinuation: AsyncStream<JSONValue>.Continuation?

 // Background tasks
 private var stdoutParsingTask: Task<Void, Never>?
 private var stderrLoggingTask: Task<Void, Never>?

 // Synchronization
 private let stateLock = NSLock()
 private let stdinWriteLock = NSLock()

 // Shared codec instances (thread-safe after Swift 5.5)
 private let jsonDecoder = JSONDecoder()
 private let jsonEncoder = JSONEncoder()

 // MARK: - Initialization

 /// Creates a stdio transport with an explicit configuration.
 ///
 /// - Parameter configuration: Server process configuration.
 public init(configuration: Configuration) {
 self.configuration = configuration
 }

 /// Convenience initializer.
 public convenience init(
 executable: String,
 arguments: [String] = [],
 workingDirectory: String? = nil,
 environment: [String: String] = [:],
 requestTimeout: Duration = .seconds(30),
 stderrLogHandler: (@Sendable (String) -> Void)? = nil
 ) {
 self.init(configuration: Configuration(
 executable: executable,
 arguments: arguments,
 workingDirectory: workingDirectory,
 environment: environment,
 requestTimeout: requestTimeout,
 stderrLogHandler: stderrLogHandler
 ))
 }

 deinit {
 terminateProcess()
 }

 // MARK: - Connect / Disconnect

 /// Launches the MCP server process, opens stdin/stdout/stderr pipes,
 /// and starts background tasks for reading output and logging stderr.
 ///
 /// If a previous process is still running it is terminated first.
 ///
 /// - Throws: ``MCPTransportError/serverNotAvailable`` if the transport
 /// has been permanently shut down, or any error from `Process.run()`.
 public func connect() async throws {
 try stateLock.perform {
 guard !terminated else {
 throw MCPTransportError.serverNotAvailable
 }
 }

 // Tear down any previous session.
 await disconnect()

 let proc = Process()
 let inPipe = Pipe()
 let outPipe = Pipe()
 let errPipe = Pipe()

 proc.executableURL = URL(fileURLWithPath: configuration.executable)
 proc.arguments = configuration.arguments
 proc.standardInput = inPipe
 proc.standardOutput = outPipe
 proc.standardError = errPipe

 if let workingDirectory = configuration.workingDirectory {
 proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
 }

 // Merge configured environment into the current environment.
 var env = ProcessInfo.processInfo.environment
 for (key, value) in configuration.environment {
 env[key] = value
 }
 proc.environment = env

 // Launch the child process.
 try proc.run()

 // Monitor process exit.
 proc.terminationHandler = { [weak self] _ in
 Task { [weak self] in
 await self?.handleProcessExit()
 }
 }

 // Store references under lock.
 stateLock.perform {
 self.process = proc
 self.stdinPipe = inPipe
 self.stdoutPipe = outPipe
 self.stderrPipe = errPipe
 self.terminated = false
 }

 // Start stdout NDJSON parser.
 stdoutParsingTask = Task { [weak self] in
 await self?.parseStdout()
 }

 // Start stderr line logger.
 stderrLoggingTask = Task { [weak self] in
 await self?.logStderr()
 }
 }

 /// Terminates the child process, cancels background tasks, fails any
 /// pending requests, and closes the listen stream.
 public func disconnect() async {
 terminateProcess()

 // Fail any requests that haven't received a response.
 let pendingIDs = pendingRequestsLock.perform {
 let keys = Array(pendingRequests.keys)
 pendingRequests.removeAll()
 return keys
 }

 let notConnected = MCPTransportError.notConnected
 for id in pendingIDs {
 pendingRequestsLock.perform {
 guard let continuation = self.pendingRequests.removeValue(forKey: id) else { return }
 continuation.resume(throwing: notConnected)
 }
 }

 // Close the listen stream.
 listenContinuation?.finish()
 listenContinuation = nil

 // Cancel I/O tasks.
 stdoutParsingTask?.cancel()
 stdoutParsingTask = nil
 stderrLoggingTask?.cancel()
 stderrLoggingTask = nil

 // Drop pipe references (process is kept until handleProcessExit clears it).
 stateLock.perform {
 self.stdinPipe = nil
 self.stdoutPipe = nil
 self.stderrPipe = nil
 }
 }

 // MARK: - Send Request

 /// Sends a JSON-RPC request and suspends until the matching response
 /// arrives, the request times out, or the server process exits.
 ///
 /// The request is written as a single NDJSON line to the server's stdin.
 /// Responses are correlated by their `id` field.
 ///
 /// - Parameter request: A fully-formed `JSONRPCRequest`.
 /// - Returns: The matching `JSONRPCResponse`.
 /// - Throws: ``MCPTransportError/timeout``, ``MCPTransportError/notConnected``,
 /// ``MCPTransportError/processFailed(Int32)``, or the JSON-RPC error from the server.
 public func sendRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
 guard stateLock.perform({ process != nil && !terminated }) else {
 throw MCPTransportError.notConnected
 }

 return try await withThrowingTaskGroup(of: JSONRPCResponse.self) { [requestTimeout] group in
 // ── Timeout child ──────────────────────────────────────────
 group.addTask { [requestId = request.id] in
 try await Task.sleep(for: requestTimeout)

 // Remove the pending continuation so late responses don't
 // try to resume a continuation that will never be read.
 _ = self.pendingRequestsLock.perform {
 self.pendingRequests.removeValue(forKey: requestId)
 }

 throw MCPTransportError.timeout
 }

 // ── Request / response child ───────────────────────────────
 group.addTask { [requestId = request.id] in
 try await withCheckedThrowingContinuation { continuation in
 let registered = self.pendingRequestsLock.perform {
 guard self.pendingRequests[requestId] == nil else {
 continuation.resume(throwing: MCPTransportError.protocolViolation(
 "Duplicate JSON-RPC request ID: \(requestId)"
 ))
 return false
 }
 self.pendingRequests[requestId] = continuation
 return true
 }

 guard registered else { return }

 // Encode the request.
 let data: Data
 do {
 data = try self.jsonEncoder.encode(request)
 } catch {
 self.pendingRequestsLock.perform { self.pendingRequests.removeValue(forKey: requestId) }
 continuation.resume(throwing: MCPTransportError.ioError(
 "Failed to encode JSON-RPC request: \(error.localizedDescription)"
 ))
 return
 }

 // Append newline (NDJSON framing) and write to stdin.
 var payload = data
 payload.append(0x0A) // '\n'

 self.stdinWriteLock.perform {
 guard let handle = self.stdinPipe?.fileHandleForWriting else {
 self.pendingRequestsLock.perform { self.pendingRequests.removeValue(forKey: requestId) }
 continuation.resume(throwing: MCPTransportError.notConnected)
 return
 }
 do {
 try handle.write(contentsOf: payload)
 try handle.synchronizeFile()
 } catch {
 self.pendingRequestsLock.perform { self.pendingRequests.removeValue(forKey: requestId) }
 continuation.resume(throwing: MCPTransportError.ioError(
 "Failed to write to server stdin: \(error.localizedDescription)"
 ))
 }
 }
 }
 }

 // Return whichever child finishes first (response or timeout).
 guard let response = try await group.next() else {
 throw MCPTransportError.notConnected
 }
 group.cancelAll()
 return response
 }
 }

 // MARK: - Send Notification

 /// Sends a JSON-RPC notification (fire-and-forget).
 ///
 /// Notifications have no `id` and expect no response. The call succeeds
 /// once the bytes are written to the server's stdin.
 ///
 /// - Parameter notification: The notification to send.
 /// - Throws: ``MCPTransportError/notConnected`` or an I/O error.
 public func sendNotification(_ notification: JSONRPCNotification) async throws {
 guard stateLock.perform({ process != nil && !terminated }) else {
 throw MCPTransportError.notConnected
 }

 let data: Data
 do {
 data = try jsonEncoder.encode(notification)
 } catch {
 throw MCPTransportError.ioError(
 "Failed to encode JSON-RPC notification: \(error.localizedDescription)"
 )
 }

 var payload = data
 payload.append(0x0A) // '\n'

 try stdinWriteLock.perform {
 guard let handle = stdinPipe?.fileHandleForWriting else {
 throw MCPTransportError.notConnected
 }
 try handle.write(contentsOf: payload)
 try handle.synchronizeFile()
 }
 }

 // MARK: - Listen

 /// Returns an async stream of messages from the MCP server.
 ///
 /// The stream yields:
 /// - Responses whose request ID didn't match any pending request
 /// - Server-sent notifications (no `id` field)
 /// - Any other JSON message received on stdout
 ///
 /// The stream finishes when the transport disconnects or the process exits.
 /// If the stream's consumer cancels iteration (e.g. `break` from a
 /// `for await` loop), the internal reference is released.
 ///
 /// - Returns: An `AsyncStream` of `JSONValue`.
 public func listen() async throws -> AsyncStream<JSONValue> {
 AsyncStream<JSONValue> { [weak self] continuation in
 self?.listenContinuation = continuation
 continuation.onTermination = { [weak self] _ in
 self?.listenContinuation = nil
 }
 }
 }

 // MARK: - Private — Stdout Parsing

 /// Background task that reads newline-delimited JSON from the server's
 /// stdout pipe and dispatches each parsed value.
 private func parseStdout() async {
 guard let handle = stdoutPipe?.fileHandleForReading else { return }

 let bufferSize = 8192
 var partialLine = ""

 while !Task.isCancelled {
 let data: Data
 do {
 data = try handle.read(upToCount: bufferSize) ?? Data()
 } catch {
 break
 }

 // Empty data signals EOF (pipe closed by the OS).
 if data.isEmpty {
 break
 }

 partialLine += String(data: data, encoding: .utf8) ?? ""

 // Extract complete lines.
 while let newlineIndex = partialLine.firstIndex(of: "\n") {
 let line = String(partialLine[..<newlineIndex])
 partialLine.removeSubrange(...newlineIndex)

 let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
 guard !trimmed.isEmpty else { continue }

 if let value = jsonDecoder.decodeLine(trimmed) {
 await deliverParsedValue(value)
 }
 }
 }

 // Flush any trailing partial line.
 let trimmed = partialLine.trimmingCharacters(in: .whitespacesAndNewlines)
 if !trimmed.isEmpty, let value = jsonDecoder.decodeLine(trimmed) {
 await deliverParsedValue(value)
 }
 }

 /// Attempts to match a parsed value to a pending request. If matched,
 /// the associated continuation is resumed. Otherwise the value is
 /// forwarded to the listen stream.
 private func deliverParsedValue(_ value: JSONValue) async {
 if let response = response(from: value) {
 let id = response.id
 let continuation = pendingRequestsLock.perform {
 return pendingRequests.removeValue(forKey: id)
 }

 if let continuation = continuation {
 if let error = response.error {
 continuation.resume(throwing: error)
 } else {
 continuation.resume(returning: response)
 }
 return
 }
 }

 // Unmatched response or notification — yield to the listen stream.
 listenContinuation?.yield(value)
 }

 // MARK: - Private — JSON-RPC Message Extraction

 /// Returns a `JSONRPCResponse` if `value` is a JSON-RPC 2.0 response object.
 private func response(from value: JSONValue) -> JSONRPCResponse? {
 guard case .object(let dict) = value else { return nil }
 guard dict["jsonrpc"]?.stringValue == "2.0" else { return nil }
 guard let id = dict["id"]?.stringValue else { return nil }
 guard dict["result"] != nil || dict["error"] != nil else { return nil }

 let result = dict["result"]

 if let errorDict = dict["error"]?.dictionaryValue {
 let code = Int(errorDict["code"]?.numberValue ?? 0)
 let message = errorDict["message"]?.stringValue ?? "Unknown error"
 let data = errorDict["data"]
 let error = JSONRPCError(code: code, message: message, data: data)
 return JSONRPCResponse(id: id, result: nil, error: error)
 }

 return JSONRPCResponse(id: id, result: result, error: nil)
 }

 // MARK: - Private — Process Exit

 /// Called when the child process terminates (via the `terminationHandler`).
 ///
 /// Fails all pending requests, closes the listen stream, and clears
 /// process references.
 private func handleProcessExit() async {
 let exitCode: Int32 = stateLock.perform {
 let code = process?.terminationStatus ?? -1
 process = nil
 terminated = true
 return code
 }

 // Fail all pending requests.
 let pendingIDs = pendingRequestsLock.perform {
 let keys = Array(pendingRequests.keys)
 pendingRequests.removeAll()
 return keys
 }

 let error: Error
 if exitCode != 0 {
 error = MCPTransportError.processFailed(exitCode)
 } else {
 error = MCPTransportError.serverNotAvailable
 }

 for id in pendingIDs {
 pendingRequestsLock.perform {
 guard let continuation = self.pendingRequests.removeValue(forKey: id) else { return }
 continuation.resume(throwing: error)
 }
 }

 // Close the listen stream.
 listenContinuation?.finish()
 listenContinuation = nil

 // Cancel background I/O tasks.
 stdoutParsingTask?.cancel()
 stdoutParsingTask = nil
 stderrLoggingTask?.cancel()
 stderrLoggingTask = nil
 }

 // MARK: - Private — Process Termination

 /// Sends SIGTERM to the process, waits briefly, then SIGKILL if still alive.
 private func terminateProcess() {
 stateLock.perform {
 guard let proc = process, proc.isRunning else { return }

 proc.terminate()

 // Grace period for clean shutdown (flushes buffers, etc.).
 Thread.sleep(forTimeInterval: 0.5)

 // Force-kill if the process ignored SIGTERM.
 if proc.isRunning {
 proc.kill()
 }

 terminated = true
 }
 }

 // MARK: - Private — Stderr Logging

 /// Background task that reads lines from the child process's stderr
 /// and forwards them to the configured log handler.
 private func logStderr() async {
 guard let handle = stderrPipe?.fileHandleForReading else { return }

 let bufferSize = 4096
 var accumulator = ""

 while !Task.isCancelled {
 let data: Data
 do {
 data = try handle.read(upToCount: bufferSize) ?? Data()
 } catch {
 break
 }

 if data.isEmpty {
 break
 }

 accumulator += (String(data: data, encoding: .utf8) ?? "")

 while let newlineIndex = accumulator.firstIndex(of: "\n") {
 let line = String(accumulator[..<newlineIndex])
 accumulator.removeSubrange(...newlineIndex)
 configuration.stderrLogHandler?(line)
 }
 }

 // Flush any trailing content without a trailing newline.
 if !accumulator.isEmpty {
 configuration.stderrLogHandler?(accumulator)
 }
 }
}

// MARK: - JSONDecoder Line Decoding

private extension JSONDecoder {
 /// Decodes a single NDJSON line into a `JSONValue`.
 ///
 /// Returns `nil` if the line isn't valid JSON, allowing the caller to
 /// decide how to handle malformed input.
 func decodeLine(_ line: String) -> JSONValue? {
 guard let data = line.data(using: .utf8) else { return nil }
 return try? decode(JSONValue.self, from: data)
 }
}

// MARK: - NSLock Convenience

private extension NSLock {
 /// Executes `work` while holding the lock, returning (or throwing) its result.
 func perform<T>(_ work: () throws -> T) rethrows -> T {
 lock()
 defer { unlock() }
 return try work()
 }
}
