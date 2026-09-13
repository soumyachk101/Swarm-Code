import Foundation
import SwiftUI

/// Converts a cumulative token counter into per-event spend.
///
/// Providers report usage with different shapes: Claude hands over session
/// totals, Codex a thread total, ACP a session counter. All three only ever
/// grow within a session, so the spend behind one event is the positive
/// delta since the previous event. A drop (compaction, a fresh session on a
/// reused object) reseeds the baseline without recording: the growth after
/// it is new spend and gets counted from there.
struct TokenSpendTracker {
    private var lastTotal = 0

    mutating func spend(total: Int) -> Int {
        defer { lastTotal = max(0, total) }
        return max(0, total - lastTotal)
    }
}

/// Daily AI coding token spend across every provider, backing the Token
/// activity heatmap at the top of Settings, General.
///
/// Two feeds merge here. Live spend is recorded as sessions stream: each
/// provider adapter reports with the semantics it knows (per-response
/// totals for the native API sessions, tracker deltas for the cumulative
/// counters), so the ledger itself only ever adds. History comes from a
/// one-time background tail scan of local Codex rollouts: only the last
/// 128 KB of each file is read, looking for its final token_count event,
/// so thousands of transcripts cost one seek each. Per-file fingerprints
/// (mtime plus size) keep later scans incremental, and files written after
/// launch are skipped because live recording already owns them; counting
/// both would double every active session. Claude history is live-only for
/// now: its usage rows are scattered through gigabytes of JSONL, which is
/// not a Settings-open price worth paying.
@MainActor
@Observable
final class TokenLedger {
    static let shared = TokenLedger()

    /// Merged history plus live spend, keyed by local day.
    private(set) var dailyTotals: [String: Int] = [:]

    private static let liveDefaultsKey = "droppycode.tokenActivity.liveDaily"
    private static let codexDefaultsKey = "droppycode.tokenActivity.codexFiles"

    /// Live-recorded spend, kept apart from history so a rescan never drops
    /// usage that arrived after the scan.
    private var liveDaily: [String: Int] = [:]
    private var historyDaily: [String: Int] = [:]
    private var didStartLoad = false
    /// Live recording owns every session from this moment, so the history
    /// scan only takes files last written before it.
    private let launchDate = Date()

    private init() {
        if let cached = UserDefaults.standard.dictionary(forKey: Self.liveDefaultsKey) as? [String: Int] {
            liveDaily = cached
        }
        dailyTotals = liveDaily
    }

    /// Adds spend to a day. Every provider session runs on the main actor,
    /// so this needs no lock.
    func record(spend: Int, on date: Date = Date()) {
        guard spend > 0 else { return }
        let day = Self.dayKey(for: date)
        liveDaily[day, default: 0] += spend
        dailyTotals[day, default: 0] += spend
        UserDefaults.standard.set(liveDaily, forKey: Self.liveDefaultsKey)
    }

    /// Runs the Codex history scan once per process. Later calls are no-ops;
    /// live recording keeps the grid fresh after that.
    func refreshIfNeeded() async {
        guard !didStartLoad else { return }
        didStartLoad = true
        let cached = UserDefaults.standard.dictionary(forKey: Self.codexDefaultsKey) as? [String: [String: Any]] ?? [:]
        let fingerprints = cached.compactMapValues(CodexFileFingerprint.init(dict:))
        let liveCutoff = launchDate
        let history = await Task.detached(priority: .utility) {
            TokenHistoryScanner.scanCodexHistory(cached: fingerprints, liveCutoff: liveCutoff)
        }.value
        historyDaily = history.daily
        UserDefaults.standard.set(
            history.fingerprints.mapValues(\.dict),
            forKey: Self.codexDefaultsKey
        )
        dailyTotals = historyDaily.merging(liveDaily) { $0 + $1 }
    }

    /// Local day key for a date. Nonisolated so the background scan shares it.
    nonisolated static func dayKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// One Codex rollout's contribution: its session total attributed to the day
/// of its last token_count event. Cached by path so rescans only tail files
/// whose mtime or size moved.
private struct CodexFileFingerprint: Sendable {
    var mtime: Double
    var size: UInt64
    var tokens: Int
    var day: String

    init(mtime: Double, size: UInt64, tokens: Int, day: String) {
        self.mtime = mtime
        self.size = size
        self.tokens = tokens
        self.day = day
    }

    init?(dict: [String: Any]) {
        guard let mtime = dict["mtime"] as? Double,
              let day = dict["day"] as? String else { return nil }
        let size: UInt64
        if let number = dict["size"] as? NSNumber {
            size = number.uint64Value
        } else if let int = dict["size"] as? Int {
            size = UInt64(int)
        } else {
            return nil
        }
        let tokens = (dict["tokens"] as? NSNumber)?.intValue ?? (dict["tokens"] as? Int ?? 0)
        self.init(mtime: mtime, size: size, tokens: tokens, day: day)
    }

    var dict: [String: Any] {
        ["mtime": mtime, "size": NSNumber(value: size), "tokens": tokens, "day": day]
    }
}

/// Background Codex history scan. Static functions over value types only, so
/// the detached task stays Sendable.
private enum TokenHistoryScanner {
    struct Result: Sendable {
        var daily: [String: Int]
        var fingerprints: [String: CodexFileFingerprint]
    }

    /// How much of each rollout tail to read. token_count events repeat
    /// through a session, so the final one sits near the end.
    private static let tailBytes = 131_072
    private static let historyMonths = 12

    static func scanCodexHistory(cached: [String: CodexFileFingerprint], liveCutoff: Date) -> Result {
        var fingerprints = cached
        var seen: Set<String> = []
        var daily: [String: Int] = [:]
        let cutoff = Calendar.current.date(byAdding: .month, value: -historyMonths, to: Date()) ?? Date.distantPast
        let manager = FileManager()
        for directory in codexDirectories {
            guard let enumerator = manager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = values.contentModificationDate,
                      mtime >= cutoff,
                      // Sessions written after launch are live-tracked event
                      // by event; taking their session total here too would
                      // count every token twice.
                      mtime < liveCutoff else { continue }
                let size = UInt64(values.fileSize ?? 0)
                let path = url.path
                seen.insert(path)
                if let known = fingerprints[path], known.mtime == mtime.timeIntervalSince1970, known.size == size {
                    if known.tokens > 0 { daily[known.day, default: 0] += known.tokens }
                    continue
                }
                let parsed = tailContribution(at: url)
                let fingerprint = CodexFileFingerprint(
                    mtime: mtime.timeIntervalSince1970,
                    size: size,
                    tokens: parsed?.tokens ?? 0,
                    day: parsed?.day ?? ""
                )
                fingerprints[path] = fingerprint
                if let parsed, parsed.tokens > 0 { daily[parsed.day, default: 0] += parsed.tokens }
            }
        }
        // Files deleted since the last scan stop contributing instead of
        // lingering in the cache forever.
        fingerprints = fingerprints.filter { seen.contains($0.key) }
        return Result(daily: daily, fingerprints: fingerprints)
    }

    private static var codexDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
        ]
    }

    /// Reads the tail of one rollout and returns its session total with the
    /// event day, or nil when the tail holds no token_count event.
    private static func tailContribution(at url: URL) -> (tokens: Int, day: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        let offset = fileSize > UInt64(tailBytes) ? fileSize - UInt64(tailBytes) : 0
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        let data = (try? handle.readToEnd()) ?? Data()
        guard !data.isEmpty else { return nil }
        // Lossy on purpose: one stray byte must not throw away the whole
        // tail when the token_count line itself is intact.
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"token_count\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = event["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any],
                  let tokens = (total["total_tokens"] as? NSNumber)?.intValue ?? total["total_tokens"] as? Int,
                  tokens > 0 else { continue }
            let day: String
            if let stamp = event["timestamp"] as? String, let date = Self.eventDate(from: stamp) {
                day = TokenLedger.dayKey(for: date)
            } else {
                day = ""
            }
            guard !day.isEmpty else { continue }
            return (tokens, day)
        }
        return nil
    }

    /// Parses both fractional and whole-second event stamps. One formatter
    /// with fractional seconds required rejects the other shape, so both
    /// are tried rather than dropping events. Built per call because
    /// ISO8601DateFormatter is not Sendable; only token_count lines reach
    /// here, so the cost is negligible.
    private static func eventDate(from stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stamp) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: stamp)
    }
}

/// Contribution grid over the last twelve months, Sunday rows. Columns are
/// week buckets starting on the Sunday on or before the first visible day;
/// every column keeps all seven rows so the grid never shears mid-month.
private struct TokenActivityGrid {
    /// One column of the grid: the day in each Sunday-first row, nil where
    /// the cell falls outside the visible range.
    var columns: [[Date?]]
    /// Display value per cell, already scaled for the mode.
    var values: [[Int]]
    var maxValue: Int
    var monthTicks: [(label: String, column: Int)]

    static let rows = 7
    static let months = 12

    static func build(daily: [String: Int], mode: TokenActivityMode, now: Date = Date()) -> TokenActivityGrid {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let startOfToday = calendar.startOfDay(for: now)
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfToday)) ?? startOfToday
        let rangeStart = calendar.date(byAdding: .month, value: -(months - 1), to: thisMonth) ?? startOfToday

        // First column starts on the Sunday on or before the range start.
        let leadingGap = (calendar.component(.weekday, from: rangeStart) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingGap, to: rangeStart) ?? rangeStart

        // Day totals inside the range, keyed by day start.
        var totalsByDay: [Date: Int] = [:]
        var cursor = rangeStart
        while cursor <= startOfToday {
            let key = TokenLedger.dayKey(for: cursor)
            if let total = daily[key] { totalsByDay[calendar.startOfDay(for: cursor)] = total }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // Pack days into Sunday-first columns, stopping after the week that
        // holds today so no future weeks stretch the grid.
        var columns: [[Date?]] = []
        var day = gridStart
        while true {
            var column: [Date?] = []
            for _ in 0..<rows {
                column.append(day < rangeStart || day > startOfToday ? nil : day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            columns.append(column)
            if day > startOfToday { break }
        }

        // Per-mode display values. The shape never changes, only the value
        // each cell is colored by.
        var values = Array(repeating: Array(repeating: 0, count: rows), count: columns.count)
        switch mode {
        case .daily:
            for c in columns.indices {
                for r in 0..<rows {
                    if let date = columns[c][r] { values[c][r] = totalsByDay[date] ?? 0 }
                }
            }
        case .weekly:
            for c in columns.indices {
                var week = 0
                for r in 0..<rows {
                    if let date = columns[c][r] { week += totalsByDay[date] ?? 0 }
                }
                for r in 0..<rows { values[c][r] = columns[c][r] == nil ? 0 : week }
            }
        case .cumulative:
            var running = 0
            for c in columns.indices {
                for r in 0..<rows {
                    if let date = columns[c][r] { running += totalsByDay[date] ?? 0 }
                    values[c][r] = running
                }
            }
        }
        let maxValue = values.flatMap { $0 }.max() ?? 0

        // One tick per month at the column holding its first day.
        let monthNames = calendar.shortMonthSymbols
        var monthTicks: [(label: String, column: Int)] = []
        for offset in 0..<months {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: rangeStart) else { continue }
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
            let clamped = max(monthStart, rangeStart)
            let daysOut = calendar.dateComponents([.day], from: gridStart, to: clamped).day ?? 0
            let column = daysOut / rows
            let label = monthNames[(calendar.component(.month, from: monthDate) - 1 + 12) % 12]
            if column < columns.count { monthTicks.append((label, column)) }
        }

        return TokenActivityGrid(columns: columns, values: values, maxValue: maxValue, monthTicks: monthTicks)
    }
}

/// Which scaling the heatmap colors use.
enum TokenActivityMode: String, Sendable, CaseIterable {
    case daily
    case weekly
    case cumulative

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .cumulative: "Cumulative"
        }
    }
}

private enum TokenActivityStyle {
    /// Gap between cells, both axes.
    static let cellGap: CGFloat = 4
    static let cellRadius: CGFloat = 2
    /// Height of the month label strip.
    static let labelHeight: CGFloat = 18
    /// Narrowest a month label may squeeze before its neighbors hide it.
    static let minLabelAdvance: CGFloat = 30

    /// Five-step intensity ladder, empty plus four blues. The filled steps
    /// are fixed hues rather than theme overlays so a heavy day reads the
    /// same in light and dark mode; empty stays a quiet overlay that
    /// follows the appearance.
    static func color(for value: Int, maxValue: Int) -> Color {
        guard value > 0, maxValue > 0 else { return Chrome.overlay(0.07) }
        let fraction = Double(value) / Double(maxValue)
        switch fraction {
        case ..<0.25:
            return Color(red: 0.16, green: 0.32, blue: 0.62).opacity(0.45)
        case ..<0.5:
            return Color(red: 0.16, green: 0.32, blue: 0.62).opacity(0.70)
        case ..<0.75:
            return Color(red: 0.20, green: 0.40, blue: 0.80).opacity(0.90)
        default:
            return Color(red: 0.53, green: 0.72, blue: 1.0)
        }
    }
}

/// The heatmap section at the top of Settings, General. Plain page content,
/// not a ChromeCard: the grid needs the full column width, and a card would
/// inset it into a padded strip the mockup does not have. The mode is
/// view-local and the totals publish from the shared ledger, so switching
/// modes never touches the rest of General.
struct TokenActivitySection: View {
    @State private var mode: TokenActivityMode = .daily
    @State private var ledger = TokenLedger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "Token activity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                ForEach(TokenActivityMode.allCases, id: \.self) { option in
                    Button {
                        mode = option
                    } label: {
                        Text(verbatim: option.title)
                            .font(.system(size: 13, weight: mode == option ? .medium : .regular))
                            .foregroundStyle(mode == option ? Chrome.primaryText : Chrome.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
                }
            }

            let grid = TokenActivityGrid.build(daily: ledger.dailyTotals, mode: mode)
            heatmap(grid: grid)
            monthStrip(grid: grid)
        }
        .task {
            await ledger.refreshIfNeeded()
        }
    }

    /// Equal-width week columns of square cells. Each column takes an equal
    /// share of the width and each cell aspect-fits its column, so the grid
    /// fills any Settings width without clipping or scrolling.
    private func heatmap(grid: TokenActivityGrid) -> some View {
        HStack(alignment: .top, spacing: TokenActivityStyle.cellGap) {
            ForEach(grid.columns.indices, id: \.self) { c in
                VStack(spacing: TokenActivityStyle.cellGap) {
                    ForEach(0..<TokenActivityGrid.rows, id: \.self) { r in
                        if grid.columns[c][r] == nil {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else {
                            RoundedRectangle(cornerRadius: TokenActivityStyle.cellRadius, style: .continuous)
                                .fill(TokenActivityStyle.color(for: grid.values[c][r], maxValue: grid.maxValue))
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Month names pinned to the column holding each month's first day.
    /// Labels that would land closer than a readable advance are dropped,
    /// so a narrow window shows fewer months instead of overlapping them.
    private func monthStrip(grid: TokenActivityGrid) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: TokenActivityStyle.labelHeight)
            GeometryReader { proxy in
                let columnCount = max(grid.columns.count, 1)
                let stride = (proxy.size.width + TokenActivityStyle.cellGap) / CGFloat(columnCount)
                let placed = placedTicks(grid.monthTicks, stride: stride)
                ForEach(placed.indices, id: \.self) { index in
                    Text(verbatim: placed[index].label)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                        .fixedSize()
                        .position(
                            x: min(
                                max(CGFloat(placed[index].column) * stride, 12),
                                proxy.size.width - 12
                            ),
                            y: TokenActivityStyle.labelHeight / 2
                        )
                }
            }
        }
    }

    private func placedTicks(_ ticks: [(label: String, column: Int)], stride: CGFloat) -> [(label: String, column: Int)] {
        var placed: [(label: String, column: Int)] = []
        var lastX = -TokenActivityStyle.minLabelAdvance
        for tick in ticks {
            let x = CGFloat(tick.column) * stride
            guard x - lastX >= TokenActivityStyle.minLabelAdvance else { continue }
            placed.append(tick)
            lastX = x
        }
        return placed
    }
}
