import Foundation
import Network

/// Publishes the SwarmAI Bridge on the local network via mDNS so mobile devices
/// can discover it automatically.
@MainActor
final class BridgeDiscovery: NSObject, NetServiceDelegate {
    private var netService: NetService?
    private let serviceType = "_swarmai-bridge._tcp"
    private var isPublishing = false

    private var onStatusChange: ((Bool) -> Void)?

    func start(
        port: UInt16 = 8765,
        onStatusChange: @escaping (Bool) -> Void
    ) {
        self.onStatusChange = onStatusChange
        guard !isPublishing else { return }
        isPublishing = true

        netService = NetService(
            domain: "local.",
            type: "\(serviceType).",
            name: Host.current().localizedName ?? "SwarmAI",
            port: Int32(port)
        )
        netService?.delegate = self
        netService?.publish()
    }

    func stop() {
        netService?.stop()
        netService?.delegate = nil
        netService = nil
        isPublishing = false
        onStatusChange?(false)
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        Task { @MainActor in
            self.isPublishing = true
            self.onStatusChange?(true)
        }
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Task { @MainActor in
            self.isPublishing = false
            self.onStatusChange?(false)
            NSLog("Bridge mDNS publish failed: \(errorDict)")
        }
    }

    nonisolated func netServiceDidStop(_ sender: NetService) {
        Task { @MainActor in
            self.isPublishing = false
            self.onStatusChange?(false)
        }
    }
}

// MARK: - Browser (for the mobile side / testing)

@MainActor
final class BridgeBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private let serviceType = "_swarmai-bridge._tcp"
    private var foundServices: [NetService] = []
    private var onFound: ([(name: String, host: String?, port: Int)]) -> Void = { _ in }

    func browse(onFound: @escaping ([(name: String, host: String?, port: Int)]) -> Void) {
        self.onFound = onFound
        browser.delegate = self
        browser.searchForServices(ofType: "\(serviceType).", inDomain: "local.")
    }

    func stopBrowsing() {
        browser.stop()
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            guard let host = sender.hostName else { return }
            let entry = (name: sender.name ?? "unknown", host: host, port: Int(sender.port))
            self.foundServices.append(sender)
            self.onFound(self.foundServices.map { (name: $0.name ?? "unknown", host: $0.hostName, port: Int($0.port)) })
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        NSLog("Failed to resolve bridge service: \(errorDict)")
    }
}
