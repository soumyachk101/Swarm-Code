import SwiftUI

/// The context window and, where the provider reports them, the plan's usage limits or,
/// for a pay-as-you-go API key, how much credit is left on it.
struct UsagePanel: View {
    @Environment(AppModel.self) private var model
    let usage: ContextUsage?
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let showsLimits = PlanLimitsReader.exposesLimits(provider)
        let showsCredits = CreditsReader.exposesCredits(provider)
        let showsContext = usage?.fraction != nil && usage?.windowTokens != nil
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
            }

            if showsLimits {
                if showsContext {
                    Divider().padding(.vertical, 14)
                }
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

            if showsCredits {
                if showsContext {
                    Divider().padding(.vertical, 14)
                }
                CreditsSection(
                    providerName: provider.displayName,
                    credits: registry.credits[provider],
                    isLoading: registry.loadingCredits.contains(provider),
                    topUpURL: CreditsReader.topUpURL(provider)
                )
            }
        }
        .padding(16)
        .frame(width: 360)
        .animation(.easeOut(duration: 0.15), value: registry.planLimits[provider])
        .animation(.easeOut(duration: 0.15), value: registry.credits[provider])
        .onAppear {
            registry.refreshPlanLimits(provider)
            registry.refreshCredits(provider)
        }
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

/// A pay-as-you-go balance: what is left of the credit the API key is billed against.
/// The number sits large because it is the whole answer, with the top-up split and the
/// dashboard's own top-up page under it.
private struct CreditsSection: View {
    let providerName: String
    let credits: ProviderCredits?
    let isLoading: Bool
    let topUpURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: "Remaining credits")
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView().controlSize(.mini)
                }
            }
            if let credits {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: credits.amountText)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(credits.isDepleted ? Chrome.danger : Chrome.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let topUpURL {
                        Link(destination: topUpURL) {
                            Text(verbatim: "Top up")
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.top, 6)
                if let breakdown = credits.breakdownText {
                    Text(verbatim: breakdown)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.top, 5)
                }
                if credits.isDepleted {
                    Text(verbatim: "\(providerName) rejects turns until the balance is topped up.")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.danger)
                        .padding(.top, 6)
                }
            } else if !isLoading {
                Text(verbatim: "\(providerName) did not report a balance.")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.top, 8)
            }
        }
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
        if percent >= 90 { return Chrome.danger }
        if percent >= 75 { return Chrome.warning }
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
