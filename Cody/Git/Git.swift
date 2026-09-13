import Foundation

struct GitStatus: Equatable, Sendable {
    var branch: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    var changedFiles = 0
}

struct GitBranch: Identifiable, Hashable, Sendable {
    var name: String
    var isCurrent: Bool
    var upstream: String?

    var id: String { name }
}

/// A thin wrapper around the git command line. Every call runs off the main actor.
struct Git: Sendable {
    let directory: URL

    init(_ path: String) {
        directory = URL(fileURLWithPath: path)
    }

    private static var executable: URL {
        LoginEnvironment.which("git") ?? URL(fileURLWithPath: "/usr/bin/git")
    }

    @discardableResult
    func run(
        _ arguments: [String],
        environment extra: [String: String] = [:],
        input: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        var environment = LoginEnvironment.current
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment.merge(extra) { _, new in new }
        return try await Shell.run(
            Self.executable,
            ["-c", "core.quotepath=false", "-c", "color.ui=false"] + arguments,
            in: directory,
            environment: environment,
            input: input,
            timeout: timeout
        )
    }

    func output(_ arguments: [String]) async throws -> String {
        let result = try await run(arguments)
        try Self.check(result)
        return result.output
    }

    static func check(_ result: ShellResult) throws {
        if !result.succeeded { throw ShellError(result.failureMessage) }
    }

    // MARK: - Repository

    func isRepository() async -> Bool {
        (try? await run(["rev-parse", "--is-inside-work-tree"]))?.trimmedOutput == "true"
    }

    func hasCommits() async -> Bool {
        (try? await run(["rev-parse", "--verify", "--quiet", "HEAD"]))?.succeeded ?? false
    }

    func status() async -> GitStatus? {
        guard let result = try? await run(["status", "--porcelain=v2", "--branch"]), result.succeeded else { return nil }
        var status = GitStatus()
        for line in result.output.split(separator: "\n") {
            if let head = line.value(after: "# branch.head ") {
                status.branch = head == "(detached)" ? nil : head
            } else if let upstream = line.value(after: "# branch.upstream ") {
                status.upstream = upstream
            } else if let counts = line.value(after: "# branch.ab ") {
                for token in counts.split(separator: " ") {
                    if token.hasPrefix("+") { status.ahead = Int(token.dropFirst()) ?? 0 }
                    if token.hasPrefix("-") { status.behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if !line.hasPrefix("#") {
                status.changedFiles += 1
            }
        }
        return status
    }

    func branches() async -> [GitBranch] {
        let format = "%(HEAD)%09%(refname:short)%09%(upstream:short)"
        guard let text = try? await output(["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"]) else {
            return []
        }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            let upstream = parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
            return GitBranch(name: String(parts[1]), isCurrent: parts[0] == "*", upstream: upstream)
        }
    }

    func switchBranch(_ name: String) async throws {
        try Self.check(await run(["switch", name]))
    }

    func createBranch(_ name: String) async throws {
        try Self.check(await run(["switch", "-c", name]))
    }

    func addWorktree(at path: String, branch: String, base: String?) async throws {
        var arguments = ["worktree", "add", "-b", branch, path]
        if let base { arguments.append(base) }
        try Self.check(await run(arguments))
    }

    func removeWorktree(at path: String) async throws {
        try Self.check(await run(["worktree", "remove", "--force", path]))
    }

    func remoteURL() async -> String? {
        guard let text = try? await output(["remote", "get-url", "origin"]) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// The https page for the origin remote, when it is a hosted repository.
    func remoteWebURL() async -> URL? {
        guard var remote = await remoteURL() else { return nil }
        if remote.hasSuffix(".git") { remote.removeLast(4) }
        if remote.hasPrefix("git@"), let colon = remote.firstIndex(of: ":") {
            let host = remote[remote.index(remote.startIndex, offsetBy: 4)..<colon]
            remote = "https://\(host)/\(remote[remote.index(after: colon)...])"
        } else if remote.hasPrefix("ssh://git@") {
            remote = "https://" + remote.dropFirst("ssh://git@".count)
        }
        return remote.hasPrefix("http") ? URL(string: remote) : nil
    }

    func listFiles() async -> [String] {
        guard let text = try? await output(["ls-files", "--cached", "--others", "--exclude-standard"]) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    // MARK: - Commit and publish

    func workingChanges() async -> (summary: String, patch: String) {
        let summary = (try? await output(["status", "--short"])) ?? ""
        var patch = (try? await output(["diff", "HEAD", "--no-ext-diff"])) ?? ""
        if patch.utf8.count > 40_000 { patch = String(patch.prefix(40_000)) }
        return (summary, patch)
    }

    func commitAll(message: String) async throws {
        try Self.check(await run(["add", "-A"]))
        try Self.check(await run(["commit", "-F", "-"], input: Data(message.utf8)))
    }

    func push() async throws {
        try Self.check(await run(["push", "-u", "origin", "HEAD"], timeout: 300))
    }

    /// Opens a pull request (GitHub) or merge request (GitLab) for the current branch.
    func createPullRequest(title: String, body: String) async throws -> URL? {
        let remote = await remoteURL() ?? ""
        let result: ShellResult
        if remote.contains("gitlab") {
            result = try await Shell.run(tool: "glab", ["mr", "create", "--title", title, "--description", body, "--yes"], in: directory, timeout: 300)
        } else {
            result = try await Shell.run(tool: "gh", ["pr", "create", "--title", title, "--body", body], in: directory, timeout: 300)
        }
        try Self.check(result)
        let text = result.output + "\n" + result.errorOutput
        let match = text.firstMatch(of: #/https://\S+/#)
        return match.flatMap { URL(string: String($0.output)) }
    }

    // MARK: - Checkpoints

    static func checkpointRef(thread: UUID, turn: Int, phase: String) -> String {
        "refs/cody/checkpoints/\(thread.uuidString.lowercased())/\(turn)-\(phase)"
    }

    /// Snapshots the working tree into a hidden ref without touching the user's index or branch.
    func captureCheckpoint(_ ref: String) async throws {
        let fileManager = FileManager.default
        let index = fileManager.temporaryDirectory.appendingPathComponent("cody-index-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: index) }
        let environment = ["GIT_INDEX_FILE": index.path]

        // Starting from the real index keeps git's stat cache, so unchanged files are not re-hashed.
        if let indexPath = try? await output(["rev-parse", "--path-format=absolute", "--git-path", "index"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
            fileManager.fileExists(atPath: indexPath) {
            try? fileManager.copyItem(atPath: indexPath, toPath: index.path)
        } else if await hasCommits() {
            try Self.check(await run(["read-tree", "HEAD"], environment: environment))
        }
        try Self.check(await run(["add", "-A", "--", "."], environment: environment, timeout: 300))
        let tree = try await run(["write-tree"], environment: environment)
        try Self.check(tree)
        let identity = [
            "GIT_AUTHOR_NAME": "Cody", "GIT_AUTHOR_EMAIL": "cody@localhost",
            "GIT_COMMITTER_NAME": "Cody", "GIT_COMMITTER_EMAIL": "cody@localhost",
        ]
        let commit = try await run(["commit-tree", tree.trimmedOutput, "-m", "Cody checkpoint"], environment: identity)
        try Self.check(commit)
        try Self.check(await run(["update-ref", ref, commit.trimmedOutput]))
    }

    func diff(from: String, to: String) async throws -> String {
        let result = try await run(["diff", "--no-ext-diff", "-M", from, to])
        try Self.check(result)
        return result.output
    }

    func restoreCheckpoint(_ ref: String) async throws {
        try Self.check(await run(["restore", "--source", ref, "--worktree", "--staged", "--", "."]))
        _ = try? await run(["clean", "-fd", "--", "."])
    }

    func deleteCheckpoints(thread: UUID) async {
        let prefix = "refs/cody/checkpoints/\(thread.uuidString.lowercased())/"
        guard let refs = try? await output(["for-each-ref", "--format=%(refname)", prefix]) else { return }
        for ref in refs.split(separator: "\n") {
            _ = try? await run(["update-ref", "-d", String(ref)])
        }
    }
}

private extension Substring {
    func value(after prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
