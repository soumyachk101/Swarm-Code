import SwiftUI

/// The context window and, where the provider reports them, the plan's usage limits.
struct UsagePanel: View {
    @Environment(AppModel.self) private var model
    let usage: ContextUsage?
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let showsLimits = PlanLimitsReader.exposesLimits(provider)
        VStack(alignment: .leading, spacing: 0) {
            if let usage, let fraction = usage.fraction, let window = usage.windowTokens {
                HStack {
                    Text("Context window")
                        .foregroundStyle(Chrome.secondaryText)
                    Spacer(minLength: 12)
                    Text(verbatim: "\(Self.tokens(usage.usedTokens)) / \(Self.tokens(window)) (\(Int((fraction * 100).rounded()))%)")
                        .foregroundStyle(Chrome.secondaryText)
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                UsageBar(fraction: fraction, tint: Chrome.accent)
                    .padding(.top, 10)
                if showsLimits {
                    Divider().padding(.vertical, 14)
                }
            }

            if showsLimits {
                let limits = registry.planLimits[provider]
                let isLoading = registry.loadingLimits.contains(provider)
                HStack(spacing: 8) {
                    Text(verbatim: limits?.planName.map { "Plan usage limits · \($0)" } ?? "Plan usage limits")
                        .font(.system(size: 13))
                        .foregroundStyle(Chrome.secondaryText)
                    Spacer(minLength: 8)
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
                if let limits {
                    ForEach(limits.windows) { window in
                        LimitRow(window: window)
                            .padding(.top, 14)
                    }
                } else if !isLoading {
                    Text(verbatim: "\(provider.displayName) did not report plan limits.")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .animation(.easeOut(duration: 0.15), value: registry.planLimits[provider])
        .task { await registry.refreshPlanLimits(provider) }
    }

    static func tokens(_ count: Int) -> String {
        func compact(_ value: Double, _ suffix: String) -> String {
            let text = String(format: "%.1f", value)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
        }
        if count >= 1_000_000 { return compact(Double(count) / 1_000_000, "M") }
        if count >= 1_000 { return compact(Double(count) / 1_000, "k") }
        return "\(count)"
    }
}

private struct LimitRow: View {
    let window: PlanLimits.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(verbatim: window.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let resetsAt = window.resetsAt {
                    Text(verbatim: "Resets \(Self.resetText(resetsAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
                }
                Text(verbatim: "\(Int(window.percent.rounded()))%")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .monospacedDigit()
            }
            UsageBar(fraction: window.percent / 100, tint: Self.tint(for: window.percent))
        }
    }

    private static func tint(for percent: Double) -> Color {
        if percent >= 90 { return Color(red: 0.86, green: 0.33, blue: 0.31) }
        if percent >= 75 { return Chrome.orange }
        return Chrome.accent
    }

    /// "in 3 hr 34 min" within a day, a weekday and time within a week, and a date beyond that.
    private static func resetText(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 86_400 {
            let hours = Int(seconds) / 3_600
            let minutes = Int(seconds) % 3_600 / 60
            return hours > 0 ? "in \(hours) hr \(minutes) min" : "in \(max(1, minutes)) min"
        }
        if seconds < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Chrome.overlay(0.1))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(fraction > 0 ? 5 : 0, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}
