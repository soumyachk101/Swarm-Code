//
// AgentEngine.swift
// Agent engine base types and process management
//

import Foundation

public protocol AgentEngine: Sendable {
 associatedtype ProcessType

 var identity: AgentIdentity { get }
 var isRunning: Bool { get }
 var process: ProcessType? { get }

 func launch(workingDirectory: URL) async throws
 func stop() async throws
 func send(_ input: String) async throws -> String
 func isAvailable() async -> Bool
}

// MARK: - Process-based Agent

public actor AgentProcess: Sendable {

 // MARK: - Process State

 public enum ProcessState: Equatable, Sendable {
 case idle
 case running(pid: Int32)
 case stopped(exitCode: Int32)
 case error(String)
 }

 private let engine: AgentEngineType
 private var process: Process?
 private let workingDirectory: URL
 private var isRunning = false

 public init(engine: AgentEngineType, workingDirectory: URL) {
 self.engine = engine
 self.workingDirectory = workingDirectory
 }

 public func launch() async throws {
 guard let binaryPath = try await findBinary() else {
 throw AgentError.binaryNotFound(engine.rawValue)
 }

 process = Process()
 process?.executableURL = binaryPath
 process?.currentDirectoryURL = workingDirectory
 process?.environment = ProcessInfo.processInfo.environment

 let inputPipe = Pipe()
 let outputPipe = Pipe()
 let errorPipe = Pipe()

 process?.standardInput = inputPipe
 process?.standardOutput = outputPipe
 process?.standardError = errorPipe

 try process?.run()
 isRunning = true
 }

 public func stop() async {
 process?.terminate()
 process?.waitUntilExit()
 isRunning = false
 process = nil
 }

 public func send(_ input: String) async throws -> String {
 guard let process, isRunning else {
 throw AgentError.notRunning
 }

 let pipe = process.standardOutput!
 let inputPipe = process.standardInput!

 let data = (input + "\n").data(using: .utf8)!
 try inputPipe.fileHandleForWriting.write(contentsOf: data)

 let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
 return String(data: outputData, encoding: .utf8) ?? ""
 }

 public func isAvailable() async -> Bool {
 (try? await findBinary()) != nil
 }

 // MARK: - Private

 private func findBinary() async throws -> URL? {
 let paths: [String]

 switch engine {
 case .claude:
 paths = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", ProcessInfo.processInfo.environment["PATH"]?.components(separatedBy: ":").flatMap { $0 }.map { "\($0)/claude" } ?? []]
 case .codex:
 paths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
 case .cursor:
 paths = ["/usr/local/bin/cursor", "/opt/homebrew/bin/cursor"]
 default:
 paths = ["/usr/local/bin/\(engine.rawValue)"]
 }

 for path in paths {
 if FileManager.default.isExecutableFile(atPath: path) {
 return URL(fileURLWithPath: path)
 }
 }

 return nil
 }
}

// MARK: - Agent Manager

public actor AgentManager {
 private var agents: [String: AgentProcess] = [:]
 private let workingDirectory: URL

 public init(workingDirectory: URL) {
 self.workingDirectory = workingDirectory
 }

 public func startAgent(engine: AgentEngineType) async throws -> String {
 let id = UUID().uuidString
 let agent = AgentProcess(engine: engine, workingDirectory: workingDirectory)
 try await agent.launch()
 agents[id] = agent
 return id
 }

 public func stopAgent(id: String) async {
 agents[id]?.stop()
 agents.removeValue(forKey: id)
 }

 public func stopAll() async {
 for (id, _) in agents {
 await stopAgent(id: id)
 }
 }
}

// MARK: - Errors

public enum AgentError: Error, Equatable {
 case binaryNotFound(String)
 case notRunning
 case processFailed(Int32)
 case launchFailed(String)

 public var localizedDescription: String {
 switch self {
 case .binaryNotFound(let engine): return "\(engine) binary not found in PATH"
 case .notRunning: return "Agent is not running"
 case .processFailed(let code): return "Agent process failed with exit code \(code)"
 case .launchFailed(let msg): return "Agent launch failed: \(msg)"
 }
 }
}
