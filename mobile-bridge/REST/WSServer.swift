import Foundation
import Network

/// A lightweight WebSocket server built on Network.framework. The bridge owns it
/// and feeds it the `onEvent` handler so inbound client messages reach the app.
@MainActor
final class WSServer: NSObject {
    private let port: UInt16
    private var listener: NWListener?
    private var connections: [UUID: WSConnection] = [:]
    private weak var bridge: BridgeServer?
    private var authenticatedClients: Set<UUID> = []

    init(port: UInt16 = 8765, bridge: BridgeServer) {
        self.port = port
        self.bridge = bridge
        super.init()
    }

    func start() {
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            NSLog("Bridge WS: cannot bind port \(port): \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                NSLog("Bridge WS listening on :\(self?.port ?? 0)")
            }
        }
        listener?.start(queue: .global())
    }

    func stop() {
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    var clientCount: Int { connections.count }

    func broadcast(_ event: BridgeEvent) {
        for (_, conn) in connections {
            conn.send(event)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let sessionID = UUID()
        let wsConn = WSConnection(
            connection: connection,
            sessionID: sessionID,
            pairing: bridge?.pairing,
            onMessage: { [weak self] event in
                Task { @MainActor in
                    self?.bridge?.handleClientMessage(event)
                }
            },
            onDisconnect: { [weak self] in
                Task { @MainActor in
                    self?.connections.removeValue(forKey: sessionID)
                    self?.authenticatedClients.remove(sessionID)
                }
            }
        )
        connections[sessionID] = wsConn
        wsConn.start()
    }
}

// MARK: - Individual WS connection

private final class WSConnection {
    private let connection: NWConnection
    private let sessionID: UUID
    private let pairing: BridgePairingManager?
    private let onMessage: (BridgeEvent) -> Void
    private let onDisconnect: () -> Void
    private var isAuthenticated = false
    private var messageQueue: [BridgeEvent] = []

    init(
        connection: NWConnection,
        sessionID: UUID,
        pairing: BridgePairingManager?,
        onMessage: @escaping (BridgeEvent) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.connection = connection
        self.sessionID = sessionID
        self.pairing = pairing
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error), .cancelled(let error):
                NSLog("Bridge WS connection ended: \(error)")
                self?.onDisconnect()
            default: break
            }
        }
        connection.start(queue: .global())
        receiveLoop()
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ event: BridgeEvent) {
        if isAuthenticated {
            transmit(event)
        } else {
            messageQueue.append(event)
        }
    }

    private func transmit(_ event: BridgeEvent) {
        guard let data = event.jsonData() else { return }
        let message = NWProtocolWebSocket.Message.data(data)
        connection.send(content: message, completion: .contentProcessed { error in
            if let error { NSLog("Bridge WS send error: \(error)") }
        })
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                NSLog("Bridge WS receive error: \(error)")
                self.onDisconnect()
                return
            }
            guard let data, let event = BridgeEvent.fromJSON(data) else {
                self.receiveLoop()
                return
            }
            self.handleIncoming(event)
            self.receiveLoop()
        }
    }

    private func handleIncoming(_ event: BridgeEvent) {
        switch event {
        case .pair(let code):
            guard let pairing = pairing,
                  let token = pairing.validateAndIssueToken(code) else {
                transmit(BridgeEvent.pairFailed(reason: "Invalid or expired code"))
                return
            }
            isAuthenticated = true
            transmit(BridgeEvent.paired(sessionToken: token))
            drainQueue()
        default:
            guard isAuthenticated else {
                transmit(BridgeEvent.pairFailed(reason: "Not paired"))
                return
            }
            onMessage(event)
        }
    }

    private func drainQueue() {
        for event in messageQueue { transmit(event) }
        messageQueue.removeAll()
    }
}
