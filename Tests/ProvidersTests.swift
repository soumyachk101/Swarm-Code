import Foundation
import Testing

/// Characterization tests for the native API providers (DeepSeek, Meta, Z.ai) and
/// the file tools they share. Written before the providers dedupe refactor, so the
/// triplicated session logic keeps behaving identically as it is extracted into a
/// shared base. Suites run via `scripts/test_providers.sh` (Swift Testing throughout).

// MARK: - NativeFileTools.resolveURL (path containment)

@Suite struct NativeFileToolsContainmentTests {

    private func tools() -> NativeFileTools {
        NativeFileTools(workingDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("droppy-providers-tests-root").path)
    }

    @Test func relativePathsResolveInsideTheRoot() throws {
        let tools = tools()
        #expect(try tools.resolveURL("file.txt").lastPathComponent == "file.txt")
        #expect(try tools.resolveURL("a/b.txt").lastPathComponent == "b.txt")
    }

    @Test func absolutePathInsideTheRootIsAllowed() throws {
        let tools = tools()
        let inside = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-providers-tests-root/sub/file.txt")
        #expect(try tools.resolveURL(inside.path).path == inside.path)
    }

    @Test func emptyPathIsRefused() {
        let tools = tools()
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("") }
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("   ") }
    }

    @Test func pathsOutsideTheRootAreRefused() {
        let tools = tools()
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("~/.ssh/id_ed25519") }
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("/etc/passwd") }
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("../outside.txt") }
        #expect(throws: ProviderError.self) { _ = try tools.resolveURL("sub/../../outside.txt") }
    }

    @Test func dotDotThatStaysInsideTheRootIsAllowed() throws {
        let tools = tools()
        let url = try tools.resolveURL("sub/../file.txt")
        #expect(url.path == URL(fileURLWithPath: tools.workingDirectory).appendingPathComponent("file.txt").standardizedFileURL.path)
    }
}

// MARK: - Reasoning effort mapping (per provider)

@Suite @MainActor struct ReasoningEffortMappingTests {

    @Test func deepSeekMapsMediumAndUpToHigh() {
        #expect(DeepSeekSession.reasoningEffort(nil) == nil)
        #expect(DeepSeekSession.reasoningEffort("") == nil)
        #expect(DeepSeekSession.reasoningEffort("low") == "low")
        #expect(DeepSeekSession.reasoningEffort("high") == "high")
        #expect(DeepSeekSession.reasoningEffort("max") == "max")
        #expect(DeepSeekSession.reasoningEffort("medium") == "high")
        #expect(DeepSeekSession.reasoningEffort("xhigh") == "high")
        #expect(DeepSeekSession.reasoningEffort("extra-high") == "high")
        #expect(DeepSeekSession.reasoningEffort("ultra") == nil)
    }

    @Test func zaiMapsEveryHighEffortToMax() {
        #expect(ZaiSession.reasoningEffort(nil) == nil)
        #expect(ZaiSession.reasoningEffort("") == nil)
        #expect(ZaiSession.reasoningEffort("low") == "low")
        #expect(ZaiSession.reasoningEffort("medium") == "high")
        #expect(ZaiSession.reasoningEffort("high") == "high")
        #expect(ZaiSession.reasoningEffort("xhigh") == "max")
        #expect(ZaiSession.reasoningEffort("extra-high") == "max")
        #expect(ZaiSession.reasoningEffort("max") == "max")
        #expect(ZaiSession.reasoningEffort("ultra") == nil)
    }

    @Test func metaPassesKnownEffortsThrough() {
        #expect(MetaSession.reasoningEffort(nil) == nil)
        #expect(MetaSession.reasoningEffort("") == nil)
        #expect(MetaSession.reasoningEffort("minimal") == "minimal")
        #expect(MetaSession.reasoningEffort("low") == "low")
        #expect(MetaSession.reasoningEffort("medium") == "medium")
        #expect(MetaSession.reasoningEffort("high") == "high")
        #expect(MetaSession.reasoningEffort("xhigh") == "xhigh")
        #expect(MetaSession.reasoningEffort("extra-high") == "xhigh")
        #expect(MetaSession.reasoningEffort("ultra") == nil)
    }

    @Test func metaOnlySendsMaxToTheModelThatAcceptsIt() {
        #expect(MetaSession.reasoningEffort("max", model: "muse-spark-1.3") == "max")
        // A thread saved at max that moves to any other model must not send it.
        #expect(MetaSession.reasoningEffort("max", model: "muse-spark-1.2") == "xhigh")
        #expect(MetaSession.reasoningEffort("max", model: "muse-spark-1.3-contributor") == "xhigh")
        #expect(MetaSession.reasoningEffort("max", model: nil) == "max")
    }
}

// MARK: - API constants

@Suite struct NativeAPIEndpointTests {

    @Test func deepSeekEndpointsAndContextWindow() {
        #expect(DeepSeekAPI.chatURL.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(DeepSeekAPI.contextWindow == 1_048_576)
    }

    @Test func metaEndpointsAndContextWindow() {
        #expect(MetaAPI.chatURL.absoluteString == "https://api.meta.ai/v1/chat/completions")
        #expect(MetaAPI.contextWindow == 1_048_576)
    }

    @Test func zaiEndpointsAndContextWindow() {
        #expect(ZaiAPI.chatURL.absoluteString == "https://api.z.ai/api/coding/paas/v4/chat/completions")
        #expect(ZaiAPI.contextWindow == 1_000_000)
    }
}

// MARK: - Keychain storage (value preserved and restored)

@Suite(.serialized) struct NativeProviderKeychainTests {

    /// Reads the stored key if any, runs the assertions, then restores the original
    /// state (empty string deletes the item, so a user with no stored key keeps none).
    private func withStoredKey(_ key: String, _ body: () -> Void) {
        let original = DeepSeekKeychain.apiKey(fallback: "")
        defer { _ = DeepSeekKeychain.setAPIKey(original) }
        _ = DeepSeekKeychain.setAPIKey(key)
        body()
    }

    @Test func roundTripsThroughTheKeychain() {
        withStoredKey("sk-test-roundtrip-key") {
            #expect(DeepSeekKeychain.apiKey(fallback: "sk-fallback") == "sk-test-roundtrip-key")
        }
    }

    @Test func emptyValueDeletesAndFallsBack() {
        withStoredKey("sk-test-roundtrip-key") {
            _ = DeepSeekKeychain.setAPIKey("")
            #expect(DeepSeekKeychain.apiKey(fallback: "sk-fallback") == "sk-fallback")
        }
    }

    @Test func trimsWhitespaceBeforeStoring() {
        withStoredKey("  sk-test-trimmed-key  ") {
            #expect(DeepSeekKeychain.apiKey(fallback: "") == "sk-test-trimmed-key")
        }
    }
}
