import SwiftUI

/// A provider's plan usage limits as the registry last read them: a header naming the plan,
/// a row per rolling window, and a spinner or a note while they load or when none came back.
/// The composer's usage popover and Settings, Providers both show limits through this view,
/// so the two can never disagree. Refreshing is the caller's call: this only renders.
struct PlanLimitsView: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let limits = registry.planLimits[provider]
        let isLoading = registry.loadingLimits.contains(provider)
        VStack(alignment: .leading, spacing: 0) {
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
        .animation(.easeOut(duration: 0.15), value: limits)
    }
}

/// A pay-as-you-go balance: what is left of the credit the API key is billed against.
/// The number sits large because it is the whole answer, with the top-up split and the
/// dashboard's own top-up page under it. Shared by the usage popover and Settings, Providers.
struct CreditsView: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let credits = registry.credits[provider]
        let isLoading = registry.loadingCredits.contains(provider)
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
                    if let topUpURL = CreditsReader.topUpURL(provider) {
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
                    Text(verbatim: "\(provider.displayName) rejects turns until the balance is topped up.")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.danger)
                        .padding(.top, 6)
                }
            } else if !isLoading {
                Text(verbatim: "\(provider.displayName) did not report a balance.")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.top, 8)
            }
        }
        .animation(.easeOut(duration: 0.15), value: credits)
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

/// A thin capsule filled to a fraction, the bar under every limit and the context window.
struct UsageBar: View {
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
