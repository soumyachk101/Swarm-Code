import Foundation

/// A child process that exchanges JSON messages over stdio, one per line or
/// behind a `Content-Length` header.
///
/// Reading, parsing and writing happen on private queues. Parsed messages are
/// delivered through `messages`, which finishes once stdout closes or the
/// process exits.
final class StdioProcess: @unchecked Sendable {
    /// How messages are delimited on the pipes.
    enum Framing: Sendable {
        /// One JSON object per line: Codex, Claude, ACP agents and Antigravity.
        case lines
        /// LSP-style `Content-Length: N\r\n\r\n` headers before each body: the Copilot CLI.
        case contentLength
    }

    let messages: AsyncStream<JSONValue>

    private let continuation: AsyncStream<JSONValue>.Continuation
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let framing: Framing
    private let writeQueue = DispatchQueue(label: "swarmai.stdio.write")
    private let lock = NSLock()
    private var lineBuffer = Data()
    private var errorBuffer = Data()
    private var exitStatus: Int32?
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String], framing: Framing = .lines) {
        let stream = AsyncStream.makeStream(of: JSONValue.self)
        messages = stream.stream
        continuation = stream.continuation
        self.framing = framing
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    var isRunning: Bool { process.isRunning }

    /// The last few kilobytes written to stderr, used when a provider fails.
    var errorTail: String {
        lock.withLock { String(decoding: errorBuffer.suffix(4_000), as: UTF8.self) }
    }

    func start() throws {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else {
                handle.readabilityHandler = nil
                return
            }
            if data.isEmpty {
                handle.readabilityHandler = nil
                self.finishOutput()
            } else {
                self.consume(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.appendError(data)
        }
        process.terminationHandler = { [weak self] process in
            self?.didExit(process.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            throw error
        }
    }

    func send(_ message: JSONValue) {
        let body = message.data()
        let payload: Data
        switch framing {
        case .lines:
            payload = body + Data([0x0A])
        case .contentLength:
            payload = Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
        }
        let handle = stdin.fileHandleForWriting
        writeQueue.async {
            // A write to an exited process fails with EPIPE; the reader reports the exit.
            try? handle.write(contentsOf: payload)
        }
    }

    func terminate() {
        let handle = stdin.fileHandleForWriting
        writeQueue.async { try? handle.close() }
        guard process.isRunning else { return }
        process.terminate()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitStatus {
                lock.unlock()
                continuation.resume(returning: exitStatus)
            } else {
                exitWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func consume(_ data: Data) {
        switch framing {
        case .lines: consumeLines(data)
        case .contentLength: consumeFrames(data)
        }
    }

    private func consumeLines(_ data: Data) {
        let lines: [Data] = lock.withLock {
            lineBuffer.append(data)
            var lines: [Data] = []
            var start = lineBuffer.startIndex
            while let newline = lineBuffer[start...].firstIndex(of: 0x0A) {
                lines.append(Data(lineBuffer[start..<newline]))
                start = lineBuffer.index(after: newline)
            }
            if start != lineBuffer.startIndex {
                lineBuffer = Data(lineBuffer[start...])
            }
            return lines
        }
        for line in lines { deliver(line) }
    }

    /// Splits off every complete `Content-Length` frame. A header block without
    /// the length it promises is dropped, so a stray log line on stdout cannot
    /// wedge the stream.
    private func consumeFrames(_ data: Data) {
        let bodies: [Data] = lock.withLock {
            lineBuffer.append(data)
            var bodies: [Data] = []
            let separator = Data("\r\n\r\n".utf8)
            while let headerEnd = lineBuffer.range(of: separator) {
                let header = String(decoding: lineBuffer[lineBuffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
                guard let length = Self.contentLength(in: header) else {
                    lineBuffer = Data(lineBuffer[headerEnd.upperBound...])
                    continue
                }
                let bodyStart = headerEnd.upperBound
                guard lineBuffer.distance(from: bodyStart, to: lineBuffer.endIndex) >= length else { break }
                let bodyEnd = lineBuffer.index(bodyStart, offsetBy: length)
                bodies.append(Data(lineBuffer[bodyStart..<bodyEnd]))
                lineBuffer = Data(lineBuffer[bodyEnd...])
            }
            return bodies
        }
        for body in bodies { deliver(body) }
    }

    private static func contentLength(in header: String) -> Int? {
        for line in header.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func deliver(_ line: Data) {
        var line = line
        while let last = line.last, last == 0x0D || last == 0x20 { line.removeLast() }
        guard !line.isEmpty, let message = JSONValue.parse(line) else { return }
        continuation.yield(message)
    }

    private func finishOutput() {
        let remainder = lock.withLock {
            let remainder = lineBuffer
            lineBuffer = Data()
            return remainder
        }
        // A framed stream ends on a frame boundary; anything left is a torn header, not a message.
        if !remainder.isEmpty, framing == .lines { deliver(remainder) }
        continuation.finish()
    }

    private func appendError(_ data: Data) {
        lock.withLock {
            errorBuffer.append(data)
            if errorBuffer.count > 64_000 {
                errorBuffer = Data(errorBuffer.suffix(16_000))
            }
        }
    }

    private func didExit(_ status: Int32) {
        let waiters = lock.withLock {
            exitStatus = status
            let waiters = exitWaiters
            exitWaiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume(returning: status) }

        // A grandchild can inherit stdout and keep it open after the provider exits.
        let handle = stdout.fileHandleForReading
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            handle.readabilityHandler = nil
            self?.finishOutput()
        }
    }
}
