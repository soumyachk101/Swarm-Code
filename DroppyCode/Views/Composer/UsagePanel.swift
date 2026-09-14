import SwiftUI

/// The context window and, where the provider reports them, the plan's usage limits or,
/// for a pay-as-you-go API key, how much credit is left on it. The limits and credits are
/// the same views Settings, Providers shows for every signed-in provider at once.
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
                PlanLimitsView(provider: provider)
            }

            if showsCredits {
                if showsContext {
                    Divider().padding(.vertical, 14)
                }
                CreditsView(provider: provider)
            }
        }
        .padding(16)
        .frame(width: 360)
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
