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

/// A pay-as-you-go balance: what is left of the credit the API key is billed against, as one
/// settings row. The title and its note on the left, the amount and the dashboard's top-up
/// page on the right; a balance that is gone reads in the danger colour and says so in the
/// note. Shared by the usage popover and Settings, Providers.
struct CreditsView: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let registry = model.providers
        let credits = registry.credits[provider]
        let isLoading = registry.loadingCredits.contains(provider)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Remaining credits")
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.primaryText)
                if let note = note(for: credits, isLoading: isLoading) {
                    Text(verbatim: note)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                }
                if let credits {
                    Text(verbatim: credits.amountText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(credits.isDepleted ? Chrome.danger : Chrome.primaryText)
                        .lineLimit(1)
                }
                if let topUpURL = CreditsReader.topUpURL(provider) {
                    Link("Top up", destination: topUpURL)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: credits)
    }

    /// The line under the title: the top-up and grant split while there is credit, the
    /// consequence once there is none, and what happened when nothing came back.
    private func note(for credits: ProviderCredits?, isLoading: Bool) -> String? {
        guard let credits else {
            return isLoading ? nil : "\(provider.displayName) did not report a balance."
        }
        if credits.isDepleted {
            return "\(provider.displayName) declines turns until the balance is topped up."
        }
        return credits.breakdownText
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
            if let detail = window.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .lineLimit(1)
            }
            UsageBar(fraction: window.percent / 100, tint: Self.tint(for: window.percent), label: window.title)
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
    /// What the bar measures, for VoiceOver. The percentage on its own said nothing about
    /// which window or balance it belonged to.
    var label = "Used"

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
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: "\(Int((min(max(fraction, 0), 1) * 100).rounded()))% used"))
    }
}
