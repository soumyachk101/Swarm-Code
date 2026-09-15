import SwiftUI

/// A heads' report batch read as a digest: the intro, then one entry per head with
/// its outcome, its files and its report. The lead's closing instructions ride in
/// the last head's body and are dropped, since they are for the lead, not the user.
struct HydraReportDigest {
    let intro: String?
    let heads: [Head]

    struct Head: Identifiable {
        let id: String
        let name: String
        let task: String
        let outcome: Outcome
        let effort: String?
        let landing: Landing
        let body: String
    }

    enum Outcome {
        case done, failed, stopped
    }

    enum Landing {
        case landed([LandedFile])
        case notLanded([LandedFile], error: String?)
        case nothing
        case unfinished(copyPath: String?)
        case none
    }

    struct LandedFile: Identifiable {
        let path: String
        let additions: Int
        let deletions: Int
        let hasConflicts: Bool
        var id: String { path }
    }

    /// The report off the lead's `reportMessage`: everything before the first `## `
    /// is the intro, each header starts a head, and trailing `(...)` groups on the
    /// header are the outcome or the effort rather than the task.
    static func parse(_ text: String) -> HydraReportDigest {
        let lines = text.components(separatedBy: "\n")
        var introLines: [String] = []
        var sections: [(header: String, lines: [String])] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("## ") {
                sections.append((String(line.dropFirst(3)), []))
            } else if sections.isEmpty {
                introLines.append(line)
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        let intro = introLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var heads: [Head] = []
        for (index, section) in sections.enumerated() {
            let (name, task, outcome, effort) = parseHeader(section.header)
            var rest = section.lines
            while let first = rest.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rest.removeFirst()
            }
            var landing = Landing.none
            if let first = rest.first, Self.landingPrefix(first) {
                landing = parseLanding(first.trimmingCharacters(in: .whitespacesAndNewlines))
                rest.removeFirst()
            }
            var body = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if index == sections.count - 1 { body = withoutLeadInstructions(body) }
            heads.append(Head(id: name, name: name, task: task, outcome: outcome, effort: effort, landing: landing, body: body))
        }
        return HydraReportDigest(intro: intro.isEmpty ? nil : intro, heads: heads)
    }

    /// The name off the colon, then trailing `(...)` groups stripped from the task:
    /// `failed` or `stopped...` is the outcome, anything else the effort.
    private static func parseHeader(_ header: String) -> (name: String, task: String, outcome: Outcome, effort: String?) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        let name: String
        var rest: String
        if let colon = trimmed.firstIndex(of: ":") {
            name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = trimmed
            rest = ""
        }
        var outcome = Outcome.done
        var efforts: [String] = []
        while rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
            let group = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
            rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            let lower = group.lowercased()
            if lower == "failed" {
                outcome = .failed
            } else if lower.hasPrefix("stopped") {
                outcome = .stopped
            } else if !group.isEmpty {
                efforts.insert(group.replacingOccurrences(of: ", ", with: " · "), at: 0)
            }
        }
        return (name, rest, outcome, efforts.isEmpty ? nil : efforts.joined(separator: " · "))
    }

    private static func landingPrefix(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("Landed in your checkout:")
            || trimmed.hasPrefix("Did not land")
            || trimmed.hasPrefix("Changed nothing.")
            || trimmed.hasPrefix("Nothing landed")
    }

    /// The landing line off its prefix: the files part is comma-separated
    /// `path (+A −D)` items, before any `, and N more` or build-output tail.
    private static func parseLanding(_ line: String) -> Landing {
        if line.hasPrefix("Changed nothing.") { return .nothing }
        if line.hasPrefix("Nothing landed") {
            if let range = line.range(of: "in its copy at ") {
                var path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasSuffix(".") { path = String(path.dropLast()) }
                return .unfinished(copyPath: path.isEmpty ? nil : path)
            }
            return .unfinished(copyPath: nil)
        }
        if line.hasPrefix("Landed in your checkout:") {
            return .landed(parseFiles(String(line.dropFirst("Landed in your checkout:".count))))
        }
        if line.hasPrefix("Did not land") {
            var rest = String(line.dropFirst("Did not land".count))
            var error: String?
            if rest.hasPrefix(" ("), let close = rest.firstIndex(of: ")") {
                error = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<close]).trimmingCharacters(in: .whitespaces)
                rest = String(rest[rest.index(after: close)...])
            }
            if rest.hasPrefix(":") { rest = String(rest.dropFirst()) }
            return .notLanded(parseFiles(rest), error: error.flatMap { $0.isEmpty ? nil : $0 })
        }
        return .none
    }

    private static let filePattern: NSRegularExpression = {
        // The minus the lead writes is U+2212; a hyphen still matches for safety.
        try! NSRegularExpression(pattern: #"^(\S+) \(\+(\d+) [−\-](\d+)\)( with conflicts)?$"#)
    }()

    private static func parseFiles(_ raw: String) -> [LandedFile] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".") { text = String(text.dropLast()) }
        // The tails the lead appends after the files, longest first.
        for suffix in [#"; \d+ build-output files? (was|were) left out$"#, #", and \d+ more$"#] {
            if let range = text.range(of: suffix, options: .regularExpression) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text.components(separatedBy: ", ").compactMap { item in
            matchFile(item.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func matchFile(_ item: String) -> LandedFile? {
        let range = NSRange(item.startIndex..., in: item)
        guard let match = filePattern.firstMatch(in: item, range: range), match.range == range else { return nil }
        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let sr = Range(r, in: item) else { return nil }
            return String(item[sr])
        }
        guard let path = group(1), let a = group(2).flatMap(Int.init), let d = group(3).flatMap(Int.init) else { return nil }
        return LandedFile(path: path, additions: a, deletions: d, hasConflicts: group(4) != nil)
    }

    /// The closing paragraph the lead appends for itself is not the heads' report;
    /// it leaves with the last head's final paragraph when it reads like instructions.
    private static let leadPrefixes = [
        "The changes listed above", "The heads worked in your checkout", "A file listed with conflicts",
        "Do not check any of this", "Do not wait for", "A head that failed", "A head the user stopped",
        "The user queued", "The user sent",
    ]

    private static func withoutLeadInstructions(_ body: String) -> String {
        guard let range = body.range(of: "\n\n", options: .backwards) else { return body }
        let tail = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard leadPrefixes.contains(where: { tail.hasPrefix($0) }) else { return body }
        return String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The digest of a heads' report batch in the popover its pill opens: one flat card
/// per head with its outcome, its files and its collapsible report. The blocks parse
/// off the main thread as the popover opens, so opening costs the blocks on screen.
struct HydraReportsPopover: View {
    let title: String
    let text: String
    let personas: [HydraPersona]

    @State private var digest: HydraReportDigest?
    @State private var expanded: Set<String> = []
    @State private var blocks: [String: [MarkdownBlock]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let digest {
                    ForEach(Array(digest.heads.enumerated()), id: \.element.id) { index, head in
                        headCard(head, index: index)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 480)
        .frame(idealHeight: 380, maxHeight: 560)
        .task(id: text) {
            let parsed = HydraReportDigest.parse(text)
            digest = parsed
            await MarkdownView.warm(parsed.heads.map(\.body))
            guard !Task.isCancelled else { return }
            var warmed: [String: [MarkdownBlock]] = [:]
            for head in parsed.heads {
                warmed[head.name] = MarkdownView.blocks(for: head.body)
            }
            blocks = warmed
            // One head's report reads whole; several start collapsed to their files.
            expanded = parsed.heads.count == 1 ? Set(parsed.heads.map(\.name)) : []
        }
    }

    /// Who reported, and the one sentence saying who is still at work, if anyone is.
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(personas, id: \.self) { persona in
                    HydraGlyph(persona: persona, size: 28)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                if let intro = digest?.intro, let sentence = Self.stillAtWorkSentence(in: intro) {
                    Text(sentence)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
        }
    }

    /// The sentence holding 'still at work', from its start to the intro's end.
    private static func stillAtWorkSentence(in intro: String) -> String? {
        guard let match = intro.range(of: "still at work") else { return nil }
        let start: String.Index
        if let stop = intro[..<match.lowerBound].lastIndex(of: ".") {
            start = intro.index(after: stop)
        } else {
            start = intro.startIndex
        }
        let sentence = intro[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }

    private func headCard(_ head: HydraReportDigest.Head, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                HydraGlyph(persona: personas.first(where: { $0.name == head.name }) ?? HydraRoster.persona(at: index), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(head.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Chrome.primaryText)
                    Text(head.task)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    outcomeChip(head.outcome)
                    if let effort = head.effort {
                        Text(effort)
                            .font(.system(size: 10))
                            .foregroundStyle(Chrome.secondaryText)
                            .monospacedDigit()
                    }
                }
            }
            landingRow(head.landing)
            reportBody(head)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Chrome.overlay(0.06)))
    }

    /// The outcome as a tinted capsule: green done, red failed, amber stopped.
    private func outcomeChip(_ outcome: HydraReportDigest.Outcome) -> some View {
        let (label, color): (String, Color) = switch outcome {
        case .done: ("Done", Chrome.success)
        case .failed: ("Failed", Chrome.danger)
        case .stopped: ("Stopped", Chrome.warning)
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    /// Where the head's work went: its files as chips, or one line saying otherwise.
    @ViewBuilder
    private func landingRow(_ landing: HydraReportDigest.Landing) -> some View {
        switch landing {
        case .landed(let files):
            VStack(alignment: .leading, spacing: 6) {
                Text("Landed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Chrome.secondaryText)
                fileChips(files)
            }
        case .notLanded(let files, let error):
            VStack(alignment: .leading, spacing: 6) {
                Text("Did not land")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Chrome.warning)
                if let error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
                fileChips(files)
            }
        case .nothing:
            Text("Changed nothing.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
        case .unfinished(let copyPath):
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing landed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Chrome.warning)
                if let copyPath {
                    Text(copyPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .none:
            EmptyView()
        }
    }

    /// Each file as a capsule: its name, its additions and deletions, amber when
    /// it still carries conflict markers. The full path waits in the tooltip.
    private func fileChips(_ files: [HydraReportDigest.LandedFile]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(files) { file in
                    HStack(spacing: 5) {
                        Text(String(file.path.split(separator: "/").last ?? Substring(file.path)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Chrome.primaryText.opacity(0.9))
                        Text("+\(file.additions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Chrome.success)
                        Text("−\(file.deletions)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Chrome.danger)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(file.hasConflicts ? Chrome.warning.opacity(0.14) : Chrome.overlay(0.1)))
                    .help(file.path)
                }
            }
        }
    }

    /// The head's own report, collapsed behind a toggle; a missing report says so
    /// with no toggle to open.
    @ViewBuilder
    private func reportBody(_ head: HydraReportDigest.Head) -> some View {
        if head.body.isEmpty || head.body == "No report." {
            Text("No report.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(Chrome.panelSlide) {
                        if expanded.contains(head.name) {
                            expanded.remove(head.name)
                        } else {
                            expanded.insert(head.name)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded.contains(head.name) ? 90 : 0))
                        Text("Report")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Chrome.secondaryText)
                }
                .buttonStyle(.plain)
                if expanded.contains(head.name) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array((blocks[head.name] ?? []).enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block)
                                .equatable()
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }
}
