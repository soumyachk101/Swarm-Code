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
        case stopped
        case crashed
        case error(String)
    }

    public struct ProcessEvent: Sendable {
        public let state: ProcessState

        public init(state: ProcessState) {
            self.state = state
        }
    }

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public var binaryPath: String
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
            restartOnCrash: Bool = false,
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

    // MARK: - Properties

    private let config: Configuration
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var eventContinuation: AsyncStream<ProcessEvent>.Continuation?
    public let events: AsyncStream<ProcessEvent>
    public private(set) var isRunning: Bool = false

    // MARK: - Init

    public init(configuration: Configuration) {
        self.config = configuration
        var continuation: AsyncStream<ProcessEvent>.Continuation?
        self.events = AsyncStream<ProcessEvent> { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    // MARK: - Process Control

    public func start() async throws {
        guard !isRunning else { return }
        guard Self.isExecutable(config.binaryPath) else {
            throw AgentError.binaryNotFound(config.binaryPath)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: config.binaryPath)
        p.arguments = config.arguments

        if let wd = config.workingDirectory {
            p.currentDirectoryURL = URL(fileURLWithPath: wd)
        }

        var env = config.inheritedEnvironment ? ProcessInfo.processInfo.environment : [:]
        for (k, v) in config.environment { env[k] = v }
        for (k, v) in config.envToInject { env[k] = v }
        p.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
        self.process = p

        p.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleTermination(status: proc.terminationStatus)
            }
        }

        try p.run()
        self.isRunning = true
        self.eventContinuation?.yield(ProcessEvent(state: .running(pid: p.processIdentifier)))
    }

    public func stop() async throws {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        self.isRunning = false
        self.process = nil
        self.stdinPipe = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil
        self.eventContinuation?.yield(ProcessEvent(state: .stopped))
    }

    public func writeStringToStdin(_ string: String) async throws {
        guard let stdinPipe, isRunning else {
            throw AgentError.notRunning
        }
        let data = Data(string.utf8)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    public func readStdout() async throws -> Data? {
        guard let stdoutPipe, isRunning else { return nil }
        let handle = stdoutPipe.fileHandleForReading
        let data = handle.availableData
        return data.isEmpty ? nil : data
    }

    private func handleTermination(status: Int32) {
        self.isRunning = false
        if status == 0 {
            self.eventContinuation?.yield(ProcessEvent(state: .stopped))
        } else {
            self.eventContinuation?.yield(ProcessEvent(state: .crashed))
        }
    }

    public static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
