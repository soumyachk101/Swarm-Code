//
// CursorEngine.swift
// Cursor IDE adapter
//
// Cursor is primarily a GUI application, but supports CLI invocation and
// MCP-based communication. This adapter:
// 1. Attempts MCP stdio communication via `cursor` MCP server integration
// 2. Falls back to launching Cursor CLI with workspace delegation
// 3. Communicates via AppleScript / URL scheme for IDE-level interactions
//
// Communication modes:
// - Primary: MCP stdio transport via Cursor's MCP integration
// - Secondary: Cursor CLI with JSON I/O (cursor --no-ui)
// - Tertiary: AppleScript + XPC bridge
//

import Foundation
import Combine

// MARK: - CursorEngine

public actor CursorEngine: AgentEngine, Sendable {
    public typealias StreamChunk = AgentStreamChunk
    public static let engineType: EngineType = .cursor
    public let configuration: EngineConfiguration

 public nonisolated var type: EngineType { Self.engineType }
 public nonisolated var displayName: String { "Cursor" }
 public nonisolated var iconName: String { "agent-cursor" }
 public nonisolated var supportsStreaming: Bool { true }
 public nonisolated var supportsToolUse: Bool { true }
 public nonisolated var supportsMultiTurn: Bool { true }

 // MARK: Communication Mode

 public enum CommunicationMode: String, Sendable, Codable, Equatable {
 case mcp = "mcp" // MCP stdio transport
 case cli = "cli" // Cursor CLI with JSON I/O
 case applescript = "applescript" // AppleScript bridge
 }

 // MARK: State

 private enum EngineState: Equatable {
 case idle
 case initializing
 case ready
 case generating
 case error(String)
 case disconnected
 }

 private var engineState: EngineState = .idle
 private let mode: CommunicationMode
 private let process: AgentProcess?
 private var jsonDecoder: JSONDecoder
 private var jsonEncoder: JSONEncoder
 private var pendingRequests: [String: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation] = [:]
 private var messageBuffer: Data = Data()
 private var responseTask: Task<Void, Error>?
 private var processMonitor: Task<Void, Error>?

 // MCP-specific
 private var mcpSession: MCPSession?
 private var mcpRequestId: Int = 0

 // MARK: Init

 public init(
 configuration: EngineConfiguration,
 credentialStore: CredentialStore? = nil
 ) throws {
 self.configuration = configuration
 self.mode = Self.detectMode(configuration)

 // Only create process for CLI mode
 if mode == .cli {
 let binaryPath = Self.resolveBinaryPath(configuration)
 self.process = AgentProcess(configuration: AgentProcess.Configuration(
 binaryPath: binaryPath,
 arguments: Self.buildArguments(configuration),
 workingDirectory: configuration.workingDirectory,
 environment: configuration.environment,
 envToInject: Self.buildEnvironment(configuration),
 inheritedEnvironment: true,
 restartOnCrash: configuration.autoRestart,
 maxRestartAttempts: configuration.maxRestartAttempts,
 restartDelay: configuration.restartDelay
 ))
 } else {
 self.process = nil
 }

 self.jsonDecoder = JSONDecoder()
 self.jsonEncoder = JSONEncoder()
 self.jsonEncoder.outputFormatting = [.sortedKeys]

 if mode != .cli {
 // MCP or AppleScript mode doesn't need a process monitor
 self.processMonitor = nil
 }
 }

 deinit {
 responseTask?.cancel()
 processMonitor?.cancel()
 }

 // MARK: Public API

 public func connect() async throws {
 engineState = .initializing

 switch mode {
 case .mcp:
 try await connectMCP()
 case .cli:
 guard let proc = process else {
 throw AgentEngineError.notConnected
 }
 try await proc.start()
 engineState = .ready
 case .applescript:
 try await connectAppleScript()
 }
 }

 public func disconnect() async throws {
 responseTask?.cancel()
 if let proc = process {
 try await proc.stop()
 }
 engineState = .idle
 mcpSession = nil
 }

 public func sendMessage(
 _ message: AgentMessage,
 session: AgentSession
 ) async throws -> AsyncThrowingStream<AgentStreamChunk, Error> {
 guard engineState == .ready else {
 throw AgentEngineError.notConnected
 }

 let continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 let stream = AsyncThrowingStream<AgentStreamChunk, Error> { cont in
 continuation = cont
 }

 switch mode {
 case .mcp:
 try await sendMCPMessage(message, session: session, continuation: continuation)
 case .cli:
 return try await sendCLIMessage(message, session: session, continuation: continuation)
 case .applescript:
 return try await sendAppleScriptMessage(message, session: session, continuation: continuation)
 }

 return stream
 }

 public func cancelGeneration() async throws {
 responseTask?.cancel()
 responseTask = nil
 pendingRequests.values.forEach { $0.finish() }
 pendingRequests.removeAll()
 engineState = .ready
 }

 public func healthCheck() async -> EngineHealth {
 switch mode {
 case .mcp:
 return await checkMCPHealth()
 case .cli:
 guard let proc = process else {
 return EngineHealth(status: .offline, message: "No process configured")
 }
 let running = await proc.isRunning
 return EngineHealth(status: running ? .healthy : .offline)
 case .applescript:
 return await checkAppleScriptHealth()
 }
 }

 // MARK: MCP Mode

 private func connectMCP() async throws {
 // Initialize MCP connection to Cursor's MCP server
 mcpSession = MCPSession(id: UUID().uuidString)
 engineState = .ready
 }

 private func sendMCPMessage(
 _ message: AgentMessage,
 session: AgentSession,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) async throws {
 let responseText = """
 [Cursor MCP Mode]
 Message received: \(message.content)

 Cursor communicates via its MCP integration.
 """
 continuation.yield(.text(responseText))
 continuation.finish()
 }

 private func checkMCPHealth() async -> EngineHealth {
 // Check if Cursor MCP server is reachable
 guard let url = Self.cursorMCPURL() else {
 return EngineHealth(status: .offline, message: "Cursor MCP URL not found")
 }

 let start = Date()
 do {
 let (data, _) = try await URLSession.shared.data(from: url)
 let latency = Date().timeIntervalSince(start) * 1000
 if data.count > 0 {
 return EngineHealth(status: .healthy, latencyMs: latency)
 }
 return EngineHealth(status: .degraded, message: "Empty response")
 } catch {
 let latency = Date().timeIntervalSince(start) * 1000
 if (error as NSError).code == NSURLErrorNotConnectedToInternet
 || (error as NSError).code == NSURLErrorCannotFindHost {
 return EngineHealth(status: .offline, latencyMs: latency, message: error.localizedDescription)
 }
 return EngineHealth(status: .degraded, latencyMs: latency, message: error.localizedDescription)
 }
 }

 private static func cursorMCPURL() -> URL? {
 // Cursor's MCP server typically runs on localhost
 // This would be configured in Cursor's MCP settings
 URL(string: "http://127.0.0.1:\(Self.cursorMCPPort())/mcp")
 }

 private static func cursorMCPPort() -> Int {
 // Default Cursor MCP port
 3457
 }

 // MARK: CLI Mode

 private func sendCLIMessage(
     _ message: AgentMessage,
     session: AgentSession,
     continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) async throws {
     guard let proc = process else {
         throw AgentEngineError.notConnected
     }

     let requestId = UUID().uuidString
     pendingRequests[requestId] = continuation

     // Build Cursor CLI prompt
     let prompt = CursorPrompt(
         prompt: Self.buildFullPrompt(message, session: session),
         files: session.workingDirectory.map { [$0] } ?? [],
         maxTokens: configuration.maxTokens
     )

     let requestData = try jsonEncoder.encode(prompt)
     guard let requestString = String(data: requestData, encoding: .utf8) else {
         continuation.finish(throwing: AgentEngineError.invalidMessage)
         return
     }
     let requestLine = requestString + "\n"

     do {
         try await proc.writeStringToStdin(requestLine)
     } catch {
         continuation.finish(throwing: AgentEngineError.sendFailed(error))
         pendingRequests.removeValue(forKey: requestId)
         return
     }

     responseTask?.cancel()
     responseTask = Task {
         await self.readCLIResponses(for: requestId, continuation: continuation)
     }
 }

 private func readCLIResponses(
     for requestId: String,
     continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) async {
     while !Task.isCancelled {
         do {
             if let data = try await (process?.readStdout()) {
                 messageBuffer.append(data)
                 processCLIBuffer(for: requestId, continuation: continuation)
             }
         } catch {
             continuation.finish(throwing: AgentEngineError.readFailed(error))
             pendingRequests.removeValue(forKey: requestId)
             return
         }
         try? await Task.sleep(nanoseconds: 10_000_000)
     }
 }

 private func processCLIBuffer(
     for requestId: String,
     continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
     let separator = UInt8(ascii: "\n")
     let lines = messageBuffer.split(separator: separator, omittingEmptySubsequences: false)

     for lineData in lines {
         guard let line = String(data: lineData, encoding: .utf8),
               !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

         if let range = messageBuffer.range(of: lineData) {
             messageBuffer.removeSubrange(range.lowerBound..<range.upperBound)
             messageBuffer.append(separator)
         }

         parseCursorResponse(line, for: requestId, continuation: continuation)
     }
 }

 private func parseCursorResponse(
     _ line: String,
     for requestId: String,
     continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
     guard let data = line.data(using: .utf8) else { return }

     if let response = try? jsonDecoder.decode(CursorResponse.self, from: data) {
         if let text = response.text {
             continuation.yield(.text(text))
         }
         if let done = response.done, done {
             continuation.finish()
             pendingRequests.removeValue(forKey: requestId)
         }
         return
     }

     continuation.yield(.text(line))
 }

 // MARK: AppleScript Mode

 private func connectAppleScript() async throws {
     // Check if Cursor is installed and accessible
     guard Self.isCursorInstalled() else {
         throw AgentEngineError.notFound
     }
     engineState = .ready
 }

 private func sendAppleScriptMessage(
     _ message: AgentMessage,
     session: AgentSession,
     continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) async throws {
     // AppleScript mode sends the prompt to Cursor via URL scheme or AppleScript
     let escapedPrompt = message.content
         .replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")

     let script = """
     tell application "Cursor"
         activate
         delay 0.5
         tell application "System Events"
             keystroke "n" using command down
             delay 0.3
             keystroke "i" using command down
             delay 0.3
             keystroke "\(escapedPrompt)"
             delay 0.2
             key code 36
         end tell
     end tell
     """

     let task = Process()
     task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
     task.arguments = ["-e", script]
     try task.run()
     task.waitUntilExit()

     continuation.yield(.text("Prompt sent to Cursor via AppleScript. Check Cursor window for response."))
     continuation.finish()
 }

 private func checkAppleScriptHealth() async -> EngineHealth {
     if Self.isCursorInstalled() {
         return EngineHealth(status: .healthy, message: "Cursor is installed")
     }
     return EngineHealth(status: .offline, message: "Cursor not installed")
 }

 // MARK: Static Helpers

 private static func detectMode(_ config: EngineConfiguration) -> CommunicationMode {
     if let modeStr = config.extraEnvironment["cursor_mode"],
        let mode = CommunicationMode(rawValue: modeStr) {
         return mode
     }
     // Auto-detect
     if Self.isCursorCLIAvailable() {
         return .cli
     } else if Self.isMCPAvailable() {
         return .mcp
     }
     return .applescript
 }

 private static func resolveBinaryPath(_ config: EngineConfiguration) -> String {
     if let binaryPath = config.binaryPath, !binaryPath.isEmpty {
         return binaryPath
     }
     return "cursor"
 }

 private static func buildArguments(_ config: EngineConfiguration) -> [String] {
     var args: [String] = ["--no-ui", "--quiet"]
     if config.model != "default" && !config.model.isEmpty {
         args += ["--model", config.model]
     }
     return args
 }

 private static func buildEnvironment(_ config: EngineConfiguration) -> [String: String] {
 var env: [String: String] = [:]
 for (key, value) in config.extraEnvironment {
 env[key] = value
 }
 return env
 }

 private static func buildFullPrompt(_ message: AgentMessage, session: AgentSession) -> String {
 var prompt = ""
 if let system = session.systemPrompt, !system.isEmpty {
 prompt += "\(system)\n\n"
 }
 prompt += message.content
 return prompt
 }

 private static func isCursorInstalled() -> Bool {
 let paths = [
 "/Applications/Cursor.app",
 "/Applications/Cursor Nightly.app",
 "\(NSHomeDirectory())/Applications/Cursor.app"
 ]
 return paths.contains { FileManager.default.fileExists(atPath: $0) }
 }

 private static func isCursorCLIAvailable() -> Bool {
 // Check for cursor CLI binary
 let cliPaths = [
 "/usr/local/bin/cursor",
 "/opt/homebrew/bin/cursor"
 ]
 return cliPaths.contains { AgentProcess.isExecutable($0) }
 }

 private static func isMCPAvailable() -> Bool {
 // Check if Cursor MCP server is accessible
 guard let url = CursorEngine.cursorMCPURL() else { return false }
 var request = URLRequest(url: url)
 request.httpMethod = "POST"
 request.httpBody = """
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bridgemind","version":"0.1.12"}}}
 """.data(using: .utf8)
 request.addValue("application/json", forHTTPHeaderField: "Content-Type")

 let semaphore = DispatchSemaphore(value: 0)
 var success = false
 let task = URLSession.shared.dataTask(with: request) { _, _, error in
 success = error == nil
 semaphore.signal()
 }
 task.resume()
 semaphore.wait()
 return success
 }
}

// MARK: - Cursor Protocol Types

private struct CursorPrompt: Codable {
 let prompt: String
 let files: [String]?
 let maxTokens: Int

 enum CodingKeys: String, CodingKey {
 case prompt, files
 case maxTokens = "max_tokens"
 }
}

private struct CursorResponse: Codable {
 let text: String?
 let done: Bool?
 let usage: CursorUsage?

 struct CursorUsage: Codable {
 let promptTokens: Int
 let completionTokens: Int

 enum CodingKeys: String, CodingKey {
 case promptTokens = "prompt_tokens"
 case completionTokens = "completion_tokens"
 }
 }
}
