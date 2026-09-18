import Foundation
import Network

/// Minimal HTTP server over Network.framework that serves the Bridge REST API.
@MainActor
final class RESTServer: NSObject {
    private var listener: NWListener?
    private let port: UInt16
    private weak var bridge: BridgeServer?

    init(port: UInt16 = 8766, bridge: BridgeServer) {
        self.port = port
        self.bridge = bridge
        super.init()
    }

    func start() {
        let params = NWParameters.tcp
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            NSLog("Bridge REST: cannot bind port \(port): \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                NSLog("Bridge REST listening on :\(self?.port ?? 0)")
            }
        }
        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        var buffer = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let error {
                    connection.cancel()
                    return
                }
                if let data { buffer.append(data) }

                if buffer.utf8String?.contains("\r\n\r\n") == true {
                    self.routeRequest(buffer.utf8String ?? "", connection: connection)
                    return
                } else if !isComplete {
                    receiveMore()
                } else {
                    connection.cancel()
                }
            }
        }
        receiveMore()
    }

    private func routeRequest(_ request: String, connection: NWConnection) {
        // Gate all REST endpoints on a valid bearer token issued by the bridge pairing flow.
        guard extractBearerToken(from: request).flatMap({ bridge?.pairing.validateSession($0) }) ?? false else {
            sendHTTPResponse(connection, body: jsonResponse(["error": "unauthorized"], status: 401), status: 401)
            return
        }

        guard let path = extractPath(from: request) else {
            sendHTTPResponse(connection, body: jsonResponse(["error": "bad request"]), status: 400)
            return
        }

        let body: Data?
        switch path {
        case "/api/v1/status":
            body = bridge?.serveStatus()
        case "/api/v1/threads":
            body = bridge?.serveThreadList()
        case let p where p.hasPrefix("/api/v1/threads/"):
            let idString = String(p.dropFirst("/api/v1/threads/".count))
            let uuid = UUID(uuidString: idString)
            body = uuid.flatMap { bridge?.serveThreadDetail($0) }
        case "/api/v1/models":
            body = bridge?.serveModels()
        default:
            body = jsonResponse(["error": "not found"])
        }

        sendHTTPResponse(connection, body: body ?? jsonResponse(["error": "not found"], status: 404), status: body == nil ? 404 : 200)
    }

    private func sendHTTPResponse(_ connection: NWConnection, body: Data, status: Int = 200) {
        let header = """
        HTTP/1.1 \(status == 200 ? "OK" : "Not Found")\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func jsonResponse(_ value: Any, status: Int = 200) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data(#"{"error":"encoding failed"}"#.utf8)
    }

    private func extractPath(from request: String) -> String? {
        request.firstLine?
            .split(separator: " ")
            .dropFirst()
            .first.map(String.init)?
            .split(separator: " ")
            .first.map(String.init)
    }

    private func extractBearerToken(from request: String) -> String? {
        for line in request.split(separator: "\n") {
            if line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("authorization: bearer ") {
                return String(line.split(separator: " ", maxSplits: 2).last ?? "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

private extension String {
    var firstLine: Substring? { split(separator: "\n").first }
}

private extension Data {
    var utf8String: String? { String(data: self, encoding: .utf8) }
}
