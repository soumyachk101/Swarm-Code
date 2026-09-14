import Foundation

/// A merge request (GitLab) or pull request (GitHub) that a link in the chat points at, for
/// the "Merge" item on the link's menu and the helper it spawns.
struct MergeRequestLink: Equatable, Sendable {
    enum Forge: Sendable {
        case gitlab
        case github
    }

    var url: URL
    var forge: Forge
    var number: Int

    /// How each forge writes its own: "!95" on GitLab, "#95" on GitHub.
    var label: String { forge == .gitlab ? "!\(number)" : "#\(number)" }

    /// `…/group/project/-/merge_requests/95` (any GitLab host, `diffs` or another page after
    /// the number included) or `github.com/owner/repo/pull/95`.
    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        if let index = parts.firstIndex(of: "merge_requests"), index >= 1, index + 1 < parts.count,
           let number = Int(parts[index + 1]), number > 0 {
            forge = .gitlab
            self.number = number
        } else if url.host?.lowercased().hasSuffix("github.com") == true,
                  let index = parts.firstIndex(of: "pull"), index >= 2, index + 1 < parts.count,
                  let number = Int(parts[index + 1]), number > 0 {
            forge = .github
            self.number = number
        } else {
            return nil
        }
        self.url = url
    }

    /// The helper's title: the same words as the menu item.
    var title: String { "Merge \(label)" }

    /// What the helper is asked to do: land the request with the forge's own CLI, then leave
    /// the checkout on the merged main. Complete on its own, since a native provider reads
    /// no AGENTS.md before it starts.
    var prompt: String {
        let land = switch forge {
        case .gitlab:
            "Use glab from this directory: `glab mr merge \(number) --yes`. If GitLab answers that the request is still being checked (a 405), wait a few seconds and try again; if it reports conflicts, stop and say so instead of resolving them."
        case .github:
            "Use gh from this directory: `gh pr merge \(number) --merge`. If GitHub reports the pull request is not mergeable, stop and say so instead of resolving it."
        }
        return """
        Merge \(label) now: \(url.absoluteString)

        \(land) Once it is merged, sync the checkout: if this directory is on main with a clean working tree, run `git pull --ff-only`; otherwise leave the working tree alone and say so. Do not rebuild, install or relaunch anything. Reply in a few lines with the merged commit and the request's link.
        """
    }
}
