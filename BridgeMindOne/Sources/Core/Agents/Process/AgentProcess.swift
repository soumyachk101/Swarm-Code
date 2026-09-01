//
// AgentProcess.swift
// Low-level subprocess management for AI coding agent CLI binaries
//

import Foundation

public actor AgentProcess: Sendable {

    // MARK: - Process State

    public enum ProcessState: Equatable, Sendable {
        case idle
        case running(pid: Int32)
        case stopped(exitCode: Int32)
        case error(String)
    }

    private let engineType: EngineType
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let workingDirectory: URL
    private var isRunning = false

    public init(engineType: EngineType, workingDirectory: URL) {
        self.engineType = engineType
        self.workingDirectory = workingDirectory
    }

    public func launch() async throws {
        guard let binaryPath = findBinary() else {
            throw AgentError.binaryNotFound(engineType.rawValue)
        }

        let p = Process()
        p.executableURL = binaryPath
        p.currentDirectoryURL = workingDirectory
        p.environment = ProcessInfo.processInfo.environment

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        self.inputPipe = inPipe
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        self.process = p

        try p.run()
        self.isRunning = true
    }

    public func stop() async {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        self.isRunning = false
        self.process = nil
        self.inputPipe = nil
        self.outputPipe = nil
        self.errorPipe = nil
    }

    public func send(_ input: String) async throws -> String {
        guard let inPipe = inputPipe, let outPipe = outputPipe, isRunning else {
            throw AgentError.notRunning
        }

        let data = Data((input + "\n").utf8)
        try inPipe.fileHandleForWriting.write(contentsOf: data)

        let outputData = outPipe.fileHandleForReading.availableData
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    public func isAvailable() -> Bool {
        findBinary() != nil
    }

    // MARK: - Private

    private func findBinary() -> URL? {
        var candidatePaths: [String] = []

        switch engineType {
        case .claude:
            candidatePaths = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
        case .codex:
            candidatePaths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        case .cursor:
            candidatePaths = ["/usr/local/bin/cursor", "/opt/homebrew/bin/cursor"]
        case .aider:
            candidatePaths = ["/usr/local/bin/aider", "/opt/homebrew/bin/aider"]
        default:
            candidatePaths = ["/usr/local/bin/\(engineType.rawValue)", "/opt/homebrew/bin/\(engineType.rawValue)"]
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            let pathEntries = pathEnv.components(separatedBy: ":")
            for entry in pathEntries {
                candidatePaths.append("\(entry)/\(engineType.rawValue)")
            }
        }

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}

// MARK: - Errors

public enum AgentError: Error, Equatable, Sendable {
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

