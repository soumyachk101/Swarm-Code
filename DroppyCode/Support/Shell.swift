import Foundation
import Synchronization

struct ShellResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var succeeded: Bool { status == 0 }
    var output: String { String(decoding: stdout, as: UTF8.self) }
    var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
    var trimmedOutput: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The most useful text to show when a command fails.
    var failureMessage: String {
        let error = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = error.isEmpty ? trimmedOutput : error
        return message.isEmpty ? "The command failed with exit code \(status)." : message
    }
}

struct ShellError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

enum Shell {
    /// Runs a process to completion off the main actor and collects its output.
    @concurrent
    static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.environment = environment ?? LoginEnvironment.current

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin: Pipe? = input == nil ? nil : Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin ?? FileHandle.nullDevice

        let collector = OutputCollector()
        stdout.fileHandleForReading.readabilityHandler = collector.reader(for: .stdout)
        stderr.fileHandleForReading.readabilityHandler = collector.reader(for: .stderr)

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceContinuation(continuation)
            process.terminationHandler = { process in
                once.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                once.resume(throwing: error)
                return
            }
            if let input, let stdin {
                DispatchQueue.global(qos: .userInitiated).async {
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
        let output = await collector.finished(within: 3)
        return ShellResult(status: status, stdout: output.stdout, stderr: output.stderr)
    }

    /// Runs a named tool found on the login PATH.
    static func run(
        tool name: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        guard let executable = LoginEnvironment.which(name) else {
            throw ShellError("\(name) was not found on your PATH.")
        }
        return try await run(executable, arguments, in: directory, environment: environment, input: input, timeout: timeout)
    }
}

/// Resumes a continuation exactly once, however many callbacks race to finish it.
final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    enum Stream: Hashable {
        case stdout
        case stderr
    }

    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var closed: Set<Stream> = []
    private var waiters: [OnceContinuation<Void>] = []

    func reader(for stream: Stream) -> @Sendable (FileHandle) -> Void {
        { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                close(stream)
            } else {
                lock.withLock {
                    switch stream {
                    case .stdout: stdout.append(data)
                    case .stderr: stderr.append(data)
                    }
                }
            }
        }
    }

    func finished(within timeout: TimeInterval) async -> (stdout: Data, stderr: Data) {
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OnceContinuation(continuation)
            let isDone = lock.withLock {
                if closed.count == 2 { return true }
                waiters.append(once)
                return false
            }
            if isDone { once.resume(returning: ()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.resume(returning: ())
            }
        }
        return lock.withLock { (stdout, stderr) }
    }

    private func close(_ stream: Stream) {
        let ready: [OnceContinuation<Void>] = lock.withLock {
            guard closed.insert(stream).inserted, closed.count == 2 else { return [] }
            let ready = waiters
            waiters.removeAll()
            return ready
        }
        for waiter in ready { waiter.resume(returning: ()) }
    }
}

/// The user's login shell environment. Apps launched from Finder inherit a
/// minimal PATH that cannot find provider CLIs, so this is captured once at launch.
enum LoginEnvironment {
    private static let cached = Mutex<[String: String]?>(nil)

    private static let excludedKeys: Set<String> = [
        "_", "SHLVL", "PWD", "OLDPWD", "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION",
        "TERM_SESSION_ID", "COLORTERM", "ITERM_SESSION_ID", "XPC_SERVICE_NAME",
        "__CFBundleIdentifier", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT",
    ]

    static var current: [String: String] {
        cached.withLock { $0 } ?? fallback()
    }

    static var isLoaded: Bool {
        cached.withLock { $0 != nil }
    }

    static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    @concurrent
    static func load() async {
        let marker = "__DROPPY_CODE_ENVIRONMENT__"
        let script = "printf '\(marker)'; /usr/bin/env -0; printf '\(marker)'"
        var environment = fallback()
        let shell = URL(fileURLWithPath: userShell())
        if let result = try? await Shell.run(shell, ["-l", "-i", "-c", script], environment: environment, timeout: 8) {
            let text = result.output
            if let start = text.range(of: marker),
               let end = text.range(of: marker, options: .backwards),
               start.upperBound < end.lowerBound {
                for entry in text[start.upperBound..<end.lowerBound].split(separator: "\0") {
                    guard let equals = entry.firstIndex(of: "=") else { continue }
                    let key = String(entry[..<equals])
                    guard !key.isEmpty, !excludedKeys.contains(key) else { continue }
                    environment[key] = String(entry[entry.index(after: equals)...])
                }
            }
        }
        environment["PATH"] = augmentedPath(environment["PATH"])
        let resolved = environment
        cached.withLock { $0 = resolved }
    }

    static func which(_ name: String, in environment: [String: String]? = nil) -> URL? {
        let fileManager = FileManager.default
        if name.contains("/") {
            let path = (name as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let path = (environment ?? current)["PATH"] ?? augmentedPath(nil)
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func userShell() -> String {
        let fileManager = FileManager.default
        if let shell = ProcessInfo.processInfo.environment["SHELL"], fileManager.isExecutableFile(atPath: shell) {
            return shell
        }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if fileManager.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    static func augmentedPath(_ path: String?) -> String {
        let home = homeDirectory
        var entries = (path ?? "").split(separator: ":").map(String.init)
        let common = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(home)/.local/bin",
            "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        for directory in common where !entries.contains(directory) {
            entries.append(directory)
        }
        return entries.joined(separator: ":")
    }

    private static func fallback() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in excludedKeys { environment.removeValue(forKey: key) }
        environment["PATH"] = augmentedPath(environment["PATH"])
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        return environment
    }
}
