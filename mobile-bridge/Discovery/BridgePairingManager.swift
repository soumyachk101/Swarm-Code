import Foundation
import CryptoKit

/// Manages pairing codes used to authenticate mobile clients. A code is short-lived:
/// the Mac generates a fresh 6-digit code when pairing starts, the user reads it on
/// the Mac and types it on the phone, and a connected session is keyed by a token
/// the bridge issues in response.
@MainActor
final class BridgePairingManager {
    struct PendingCode {
        let code: String
        let issuedAt: Date
        let token: String?
    }

    private(set) var currentCode: PendingCode?
    /// Codes from before the user closed the pairing sheet: 5 minutes is plenty to
    /// type a 6-digit number; past that, a stale code becomes a confusing dead-end.
    private let codeTTL: TimeInterval = 5 * 60

    func generateCode() -> String {
        let code = String(format: "%06d", Int.random(in: 0..<1_000_000))
        currentCode = PendingCode(code: code, issuedAt: .now, token: nil)
        return code
    }

    func validateAndIssueToken(_ submitted: String) -> String? {
        guard let pending = currentCode else { return nil }
        guard Date().timeIntervalSince(pending.issuedAt) < codeTTL else {
            currentCode = nil
            return nil
        }
        guard pending.code == submitted else { return nil }
        let token = Self.makeToken()
        currentCode = PendingCode(code: pending.code, issuedAt: pending.issuedAt, token: token)
        return token
    }

    func validateSession(_ token: String) -> Bool {
        guard let pending = currentCode else { return false }
        return pending.token == token
    }

    func revoke() {
        currentCode = nil
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
