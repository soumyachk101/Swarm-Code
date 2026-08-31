//
// AgentProcess.swift
// Subprocess management for launching AI coding agents
//
// Bridges the bridgemind.one.agent-run / bridgemind.one.supervised-child
// internal service architecture into a Swift-native process launcher with
// working directory isolation, environment injection, signal handling,
// crash detection, and automatic restart support.
//

import Foundation
import Combine

// MARK: - AgentProcess

public actor AgentProcess: Sendable {
 // MARK: Configuration

 public struct Configuration: Sendable, Codable, Equatable {
 public let binaryPath: String
 public var arguments: [String]
 public var workingDirectory: String?
 public var environment: [String: String]
 public var envToInject: [String: String]
 public var inheritedEnvironment: Bool
 public var restartOnCrash: Bool
 public var maxRestartAttempts: Int
 public var restartDelay: Duration

 public init(
 binaryPath: String,
 arguments: [String] = [],
 workingDirectory: String? = nil,
 environment: [String: String] = [:],
 envToInject: [String: String] = [:],
 inheritedEnvironment: Bool = true,
 restartOnCrash: Bool = true,
 maxRestartAttempts: Int = 3,
 restartDelay: Duration = .seconds(2)
 ) {
 self.binaryPath = binaryPath
 self.arguments = arguments
 self.workingDirectory = workingDirectory
 self.environment = environment
 self.envToInject = envToInject
 self.inheritedEnvironment = inheritedEnvironment
 self.restartOnCrash = restartOnCrash
 self.maxRestartAttempts = maxRestartAttempts
 self.restartDelay = restartDelay
 }
 }

 // MARK: State

 public enum ProcessState: Equatable, Sendable {
 case idle
 case launching
 case running(pid: pid_t)
 case stopped(exitCode: Int32?)
 case crashed(exitCode: Int32, signal: Int32?)
 case error(String)
 }

 // MARK: Events

 public struct ProcessEvent: Sendable, Equatable {
 public let state: ProcessState
 public let timestamp: Date
 public let message: String?

 public init(state: ProcessState, message: String? = nil) {
 self.state = state
 self.timestamp = Date()
 self.message = message
 }
 }

 // MARK: Errors

 public enum ProcessError: LocalizedError, Equatable, Sendable {
 case binaryNotFound(path: String)
 case launchFailed(underlying: String)
 case pipeCreationFailed(String)
 case signalFailed(Int32)
 case invalidState(String)
 case alreadyRunning
 case maxRestartsExceeded(Int)

 public var errorDescription: String? {
 switch self {
 case .binaryNotFound(let path):
 return "Agent binary not found at path: \(path)"
 case .launchFailed(let underlying):
 return "Failed to launch agent process: \(underlying)"
 case .pipeCreationFailed(let reason):
 return "Failed to create communication pipe: \(reason)"
 case .signalFailed(let signal):
 return "Failed to send signal: \(signal)"
 case .invalidState(let message):
 return "Invalid process state: \(message)"
 case .alreadyRunning:
 return "Agent process is already running"
 case .maxRestartsExceeded(let attempts):
 return "Exceeded maximum restart attempts (\(attempts))"
 }
 }
 }

 // MARK: Properties

 private let configuration: Configuration
 private var process: Process?
 private var state: ProcessState = .idle
 private let stateSubject = PassthroughSubject<ProcessEvent, Never>()
 private var restartCount: Int = 0
 private var restartTimer: Task<Void, Error>?

 private var stdinPipe: Pipe?
 private var stdoutPipe: Pipe?
 private var stderrPipe: Pipe?
 private var stdinFileHandle: FileHandle?
 private var stdoutFileHandle: FileHandle?
 private var stderrFileHandle: FileHandle?

 // Log writer
 private let logDirectory: URL

 // MARK: Init

 public init(
 configuration: Configuration,
 logDirectory: URL = AppConfig.logsDirectory
 ) {
 self.configuration = configuration
 self.logDirectory = logDirectory
 }

 // MARK: Public API

 public var currentState: ProcessState { state }
 public var isRunning: Bool {
 if case .running = state { return true }
 return false
 }
 public var events: AnyPublisher<ProcessEvent, Never> {
 stateSubject.eraseToAnyPublisher()
 }

 public func pid() -> pid_t? {
 if case .running(let pid) = state { return pid }
 return nil
 }

 /// Start the agent process
 public func start() async throws {
 guard !isRunning else {
 if case .idle = state {
 // Can start from idle
 } else {
 throw ProcessError.alreadyRunning
 }
 }
 await doLaunch()
 }

 /// Stop the agent process gracefully (SIGTERM), falling back to SIGKILL
 public func stop(timeout: Duration = .seconds(5)) async throws {
 guard isRunning, let proc = process, let pid = proc.processIdentifier else {
 return
 }

 // Send SIGTERM
 let killResult = kill(pid, SIGTERM)
 guard killResult == 0 else {
 throw ProcessError.signalFailed(SIGTERM)
 }

 // Wait for graceful exit
 try await Task.sleep(nanoseconds: timeout.nanoseconds)

 // SIGKILL fallback if still running
 if isRunning {
 let killResult2 = kill(pid, SIGKILL)
 if killResult2 == 0 {
 // Wait briefly for SIGKILL to take effect
 try await Task.sleep(nanoseconds: 500_000_000)
 }
 }

 // Force terminate if process still exists
 if proc.isRunning {
 proc.terminate()
 }
 }

 /// Restart the process
 public func restart() async throws {
 if isRunning {
 try await stop(timeout: .seconds(2))
 }
 restartCount = 0
 await doLaunch()
 }

 /// Send data to the process stdin
 public func writeToStdin(_ data: Data) async throws {
 guard let handle = stdinFileHandle else {
 throw ProcessError.invalidState("stdin is not available")
 }
 try handle.write(contentsOf: data)
 }

 /// Send a string to the process stdin
 public func writeStringToStdin(_ string: String) async throws {
 guard let data = string.data(using: .utf8) else {
 throw ProcessError.invalidState("Failed to encode string")
 }
 try await writeToStdin(data)
 }

 /// Read from stdout (non-blocking data available)
 public func readStdout() async throws -> Data? {
 guard let handle = stdoutFileHandle else {
 throw ProcessError.invalidState("stdout is not available")
 }
 // Non-blocking read
 let available = handle.availableData
 if available.count == 0 { return nil }
 return available
 }

 /// Read from stderr
 public func readStderr() async throws -> Data? {
 guard let handle = stderrFileHandle else {
 throw ProcessError.invalidState("stderr is not available")
 }
 let available = handle.availableData
 if available.count == 0 { return nil }
 return available
 }

 // MARK: Private

 private func updateState(_ newState: ProcessState) {
 let previous = state
 state = newState
 let event = ProcessEvent(state: newState)
 stateSubject.send(event)

 // Crash detection
 if case .crashed = newState, configuration.restartOnCrash {
 handleCrash(newState)
 }
 }

 private func handleCrash(_ crashedState: ProcessState) {
 guard restartCount < configuration.maxRestartAttempts else {
 // Max restarts exceeded
 Task { @MainActor in
 stateSubject.send(ProcessEvent(
 state: .error("Max restart attempts exceeded"),
 message: "Agent crashed \(restartCount) times"
 ))
 }
 return
 }

 restartCount += 1

 let delayNs = configuration.restartDelay.nanoseconds
 restartTimer?.cancel()
 restartTimer = Task {
 try? await Task.sleep(nanoseconds: delayNs)
 await doLaunch()
 }
 }

 private func doLaunch() async {
 updateState(.launching)

 let proc = Process()
 let resolvedPath: String

 // Resolve binary path
 if configuration.binaryPath.contains("/") {
 // Absolute or relative path
 resolvedPath = (configuration.workingDirectory.map {
 URL(fileURLWithPath: $0).appendingPathComponent(configuration.binaryPath).path
 }) ?? configuration.binaryPath
 } else {
 // Search in PATH
 resolvedPath = await Self.findBinary(configuration.binaryPath) ?? configuration.binaryPath
 }

 guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
 let errorState: ProcessState = restartCount > 0
 ? .error("Binary not found after retry: \(resolvedPath)")
 : .stopped(exitCode: nil)
 updateState(errorState)
 return
 }

 proc.executableURL = URL(fileURLWithPath: resolvedPath)
 proc.arguments = configuration.arguments.isEmpty ? nil : configuration.arguments

 // Working directory isolation
 if let wd = configuration.workingDirectory {
 proc.currentDirectoryURL = URL(fileURLWithPath: wd)
 }

 // Environment setup
 var env: [String: String]
 if configuration.inheritedEnvironment {
 env = ProcessInfo.processInfo.environment
 } else {
 env = [:]
 }
 for (key, value) in configuration.environment {
 env[key] = value
 }
 for (key, value) in configuration.envToInject {
 env[key] = value
 }
 proc.environment = env

 // Pipe setup
 let inPipe = Pipe()
 let outPipe = Pipe()
 let errPipe = Pipe()
 proc.standardInput = inPipe
 proc.standardOutput = outPipe
 proc.standardError = errPipe

 // Termination handler
 let terminationHandler: @convention(block) () -> Void = { [weak self] in
 Task { @MainActor in
 guard let self else { return }
 let currentProc = self.process
 let pid = currentProc?.processIdentifier ?? 0
 let exitCode = currentProc?.terminationStatus ?? 0
 let termSignal = currentProc?.terminationReason == .uncaughtSignal
 ? currentProc?.terminationSignal
 : nil

 let finalState: ProcessState
 if termSignal != nil && exitCode != 0 {
 finalState = .crashed(exitCode: exitCode, signal: termSignal)
 } else {
 finalState = .stopped(exitCode: exitCode)
 }

 await self.updateState(finalState)
 }
 }

 proc.terminationHandler = terminationHandler
 self.process = proc
 self.stdinPipe = inPipe
 self.stdoutPipe = outPipe
 self.stderrPipe = errPipe
 self.stdinFileHandle = inPipe.fileHandleForWriting
 self.stdoutFileHandle = outPipe.fileHandleForReading
 self.stderrFileHandle = errPipe.fileHandleForReading

 do {
 try proc.run()
 let pid = proc.processIdentifier
 updateState(.running(pid: pid))

 // Begin stderr monitoring
 Task {
 await self.monitorStderr()
 }
 } catch {
 updateState(.error(error.localizedDescription))
 }
 }

 private func monitorStderr() async {
 guard let errHandle = stderrFileHandle else { return }
 let data = errHandle.readDataToEndOfFile()
 if data.count > 0, let logMessage = String(data: data, encoding: .utf8) {
 await writeLogFile(logMessage)
 }
 }

 private func writeLogFile(_ content: String) async {
 let fileName = "agent-\(configuration.binaryPath.replacingOccurrences(of: "/", with: "-"))-\(Date().timeIntervalSince1970).log"
 let logURL = logDirectory.appendingPathComponent(fileName)
 try? content.write(to: logURL, atomically: true, encoding: .utf8)
 }

 /// Locate a binary in the system PATH
 public static func findBinary(_ name: String) async -> String? {
 let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
 let paths = envPath.split(separator: ":")

 for dir in paths {
 let fullPath = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
 var isDir: ObjCBool = false
 if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
 !isDir.boolValue,
 isExecutable(fullPath) {
 return fullPath
 }
 }
 return nil
 }

 /// Check if a given path is executable
 public static func isExecutable(_ path: String) -> Bool {
 var isDir: ObjCBool = false
 guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
 !isDir.boolValue else { return false }

 let fileSystemRep = FileManager.default.fileSystemRepresentation(withPath: path)
 return access(fileSystemRep, X_OK) == 0
 }
}
