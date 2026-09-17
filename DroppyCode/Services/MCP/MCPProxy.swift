import Foundation
import Network

final class MCPProxy: @unchecked Sendable {
    static let shared = MCPProxy()

    static let port: UInt16 = {
        let file = MCPPaths.directory.appendingPathComponent("proxy-port")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved = UInt16(trimmed), saved != 0 {
                return saved
            }
        }
        let picked = MCPProxy.pickFreePort()
        try? "\(picked)".write(to: file, atomically: true, encoding: .utf8)
        return picked
    }()

    static func url(for serverID: String) -> String {
        "http://127.0.0.1:\(port)/mcp/\(serverID)"
    }

    private struct Route: Sendable {
        var upstream: String
        var headers: [String: String]
        var usesOAuth: Bool
    }

    private struct ConnectionBox: @unchecked Sendable {
        let connection: NWConnection
    }

    private static let headLimit = 65_536
    private static let bodyLimit = 32 * 1_024 * 1_024
    private static let divider = Data("\r\n\r\n".utf8)

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "MCPProxy")
    private var routes: [String: Route] = [:]
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var running = false

    private init() {}

    func register(serverID: String, upstream: String, headers: [String: String], usesOAuth: Bool) {
        lock.lock()
        routes[serverID] = Route(upstream: upstream, headers: headers, usesOAuth: usesOAuth)
        lock.unlock()
    }

    func unregister(serverID: String) {
        lock.lock()
        _ = routes.removeValue(forKey: serverID)
        lock.unlock()
    }

    func replaceAll(_ routes: [(serverID: String, upstream: String, headers: [String: String], usesOAuth: Bool)]) {
        lock.lock()
        self.routes = Dictionary(uniqueKeysWithValues: routes.map { entry in
            (entry.serverID, Route(upstream: entry.upstream, headers: entry.headers, usesOAuth: entry.usesOAuth))
        })
        lock.unlock()
    }

    func start() {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()
        let endpointPort = NWEndpoint.Port(rawValue: Self.port) ?? 0
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        guard let listener = try? NWListener(using: parameters, on: endpointPort) else {
            print("MCPProxy: could not listen on \(Self.port)")
            lock.lock()
            running = false
            lock.unlock()
            return
        }
        lock.lock()
        self.listener = listener
        lock.unlock()
        let port = Self.port
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                print("MCPProxy: listening on \(port)")
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        lock.lock()
        let listener = self.listener
        let open = Array(connections.values)
        self.listener = nil
        connections.removeAll()
        running = false
        lock.unlock()
        listener?.cancel()
        for connection in open {
            connection.cancel()
        }
    }

    private static func pickFreePort() -> UInt16 {
        guard let probe = try? NWListener(using: .tcp, on: 0) else { return 48123 }
        let done = DispatchSemaphore(value: 0)
        probe.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                done.signal()
            default:
                break
            }
        }
        probe.start(queue: .global())
        _ = done.wait(timeout: .now() + 5)
        let picked = probe.port?.rawValue ?? 0
        probe.cancel()
        if picked == 0 {
            return 48123
        }
        return picked
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections[ObjectIdentifier(connection)] = connection
        lock.unlock()
        connection.start(queue: queue)
        readHead(connection, Data())
    }

    private func forget(_ connection: NWConnection) {
        lock.lock()
        _ = connections.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
    }

    private func readHead(_ connection: NWConnection, _ prefix: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.headLimit) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = prefix
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            if let divider = buffer.range(of: Self.divider) {
                let head = buffer[buffer.startIndex..<divider.lowerBound]
                let rest = buffer[divider.upperBound..<buffer.endIndex]
                self.handleExchange(connection: connection, head: Data(head), rest: Data(rest))
                return
            }
            if buffer.count > Self.headLimit {
                self.respond(connection: connection, status: 413, body: Self.jsonError("request head too large"))
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                self.forget(connection)
                return
            }
            self.readHead(connection, buffer)
        }
    }

    private static func parseHead(_ head: Data) -> (method: String, path: String, headers: [String: String])? {
        guard let text = String(data: head, encoding: .isoLatin1) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                headers[name] = value
            }
        }
        return (String(parts[0]), String(parts[1]), headers)
    }

    private func handleExchange(connection: NWConnection, head: Data, rest: Data) {
        guard let (method, path, clientHeaders) = Self.parseHead(head) else {
            respond(connection: connection, status: 400, body: Self.jsonError("bad request"))
            return
        }
        if let transferEncoding = clientHeaders["transfer-encoding"],
           transferEncoding.lowercased().contains("chunked") {
            respond(connection: connection, status: 411, body: Self.jsonError("chunked request bodies are not supported"))
            return
        }
        let contentLength = max(0, clientHeaders["content-length"].flatMap(Int.init) ?? 0)
        if contentLength > Self.bodyLimit {
            respond(connection: connection, status: 413, body: Self.jsonError("request body too large"))
            return
        }
        if rest.count >= contentLength {
            routeRequest(connection: connection, method: method, path: path, clientHeaders: clientHeaders, body: Data(rest.prefix(contentLength)))
        } else {
            readBody(connection: connection, method: method, path: path, clientHeaders: clientHeaders, buffer: rest, need: contentLength)
        }
    }

    private func readBody(connection: NWConnection, method: String, path: String, clientHeaders: [String: String], buffer: Data, need: Int) {
        if buffer.count >= need {
            routeRequest(connection: connection, method: method, path: path, clientHeaders: clientHeaders, body: Data(buffer.prefix(need)))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(need - buffer.count, Self.headLimit)) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }
            if next.count >= need {
                self.routeRequest(connection: connection, method: method, path: path, clientHeaders: clientHeaders, body: Data(next.prefix(need)))
            } else if isComplete || error != nil {
                self.routeRequest(connection: connection, method: method, path: path, clientHeaders: clientHeaders, body: next)
            } else {
                self.readBody(connection: connection, method: method, path: path, clientHeaders: clientHeaders, buffer: next, need: need)
            }
        }
    }

    private func routeRequest(connection: NWConnection, method: String, path: String, clientHeaders: [String: String], body: Data) {
        let bare = String(path.prefix(upTo: path.firstIndex(of: "?") ?? path.endIndex))
        guard bare.hasPrefix("/mcp/") else {
            respond(connection: connection, status: 404, body: Self.jsonError("unknown server"))
            return
        }
        let serverID = String(bare.dropFirst("/mcp/".count))
        guard !serverID.isEmpty, !serverID.contains("/") else {
            respond(connection: connection, status: 404, body: Self.jsonError("unknown server"))
            return
        }
        lock.lock()
        let route = routes[serverID]
        lock.unlock()
        guard let route else {
            respond(connection: connection, status: 404, body: Self.jsonError("unknown server"))
            return
        }
        let box = ConnectionBox(connection: connection)
        Task { [weak self] in
            guard let self else {
                box.connection.cancel()
                return
            }
            do {
                try await self.sendUpstream(box: box, serverID: serverID, route: route, method: method, clientHeaders: clientHeaders, body: body)
            } catch {
                print("MCPProxy: request to '\(serverID)' failed: \(error.localizedDescription)")
                self.respond(connection: box.connection, status: 502, body: Self.jsonError("upstream request failed"))
            }
        }
    }

    private func sendUpstream(box: ConnectionBox, serverID: String, route: Route, method: String, clientHeaders: [String: String], body: Data) async throws {
        guard let upstreamURL = URL(string: route.upstream) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: upstreamURL)
        request.httpMethod = method
        request.timeoutInterval = 3_600
        let passthrough = [
            ("content-type", "Content-Type"),
            ("accept", "Accept"),
            ("mcp-session-id", "Mcp-Session-Id"),
            ("mcp-protocol-version", "MCP-Protocol-Version"),
            ("last-event-id", "Last-Event-ID"),
        ]
        for (clientName, canonicalName) in passthrough {
            if let value = clientHeaders[clientName] {
                request.setValue(value, forHTTPHeaderField: canonicalName)
            }
        }
        for (name, value) in route.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if route.usesOAuth {
            let token: String
            do {
                token = try await MCPOAuth.accessToken(serverID: serverID)
            } catch {
                respond(connection: box.connection, status: 401, body: Self.jsonError(error.localizedDescription))
                return
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if !body.isEmpty {
            request.httpBody = body
        }
        var (stream, response) = try await URLSession.shared.bytes(for: request)
        var http = response as? HTTPURLResponse
        if route.usesOAuth, http?.statusCode == 401 {
            if let refreshed = try? await MCPOAuth.accessToken(serverID: serverID) {
                request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                (stream, response) = try await URLSession.shared.bytes(for: request)
                http = response as? HTTPURLResponse
            }
        }
        guard let http else {
            throw URLError(.badServerResponse)
        }
        try await writeBack(box: box, response: http, stream: stream)
    }

    private func writeBack(box: ConnectionBox, response: HTTPURLResponse, stream: URLSession.AsyncBytes) async throws {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        var headers: [(String, String)] = []
        if let contentType {
            headers.append(("Content-Type", contentType))
        }
        if let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            headers.append(("Mcp-Session-Id", sessionID))
        }
        if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") {
            headers.append(("Cache-Control", cacheControl))
        }
        let connection = box.connection
        if contentType?.lowercased().contains("text/event-stream") == true {
            headers.append(("Transfer-Encoding", "chunked"))
            headers.append(("Connection", "close"))
            await send(connection, Data(Self.statusHead(status: response.statusCode, headers: headers).utf8))
            do {
                for try await byte in stream {
                    var frame = Data("1\r\n".utf8)
                    frame.append(byte)
                    frame.append(Data("\r\n".utf8))
                    await send(connection, frame)
                }
            } catch {
            }
            await send(connection, Data("0\r\n\r\n".utf8))
            connection.cancel()
            forget(connection)
        } else {
            var payload = Data()
            for try await byte in stream {
                payload.append(byte)
            }
            headers.append(("Content-Length", "\(payload.count)"))
            headers.append(("Connection", "close"))
            var out = Data(Self.statusHead(status: response.statusCode, headers: headers).utf8)
            out.append(payload)
            await send(connection, out)
            connection.cancel()
            forget(connection)
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private func respond(connection: NWConnection, status: Int, body: Data) {
        var out = Data(Self.statusHead(status: status, headers: [
            ("Content-Type", "application/json"),
            ("Content-Length", "\(body.count)"),
            ("Connection", "close"),
        ]).utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.forget(connection)
        })
    }

    private static func statusHead(status: Int, headers: [(String, String)]) -> String {
        var head = "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return head
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        default:
            if (200..<300).contains(status) { "OK" } else { "Error" }
        }
    }

    private static func jsonError(_ message: String) -> Data {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return Data("{\"error\":\"\(escaped)\"}".utf8)
    }
}
