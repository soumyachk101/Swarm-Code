import SwiftUI

/// The first chat's Hydra intro, opened by the mark itself until it has been read.
/// Says what Hydra is, how a chat leads heads, what pairs are, and how to switch
/// Hydra off for a chat.
struct HydraIntroPopover: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: -6) {
                    ForEach(0..<5, id: \.self) { i in
                        HydraGlyph(persona: HydraRoster.persona(at: i), size: 30)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meet Hydra")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Hydra is on. Big jobs go out to a team of heads, so this chat leads instead of doing everything itself.")
                        .font(.system(size: 13))
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                introStep(
                    glyph: AnyView(HydraMarkImage().foregroundStyle(Chrome.primaryText).frame(width: 18, height: 18)),
                    title: "You ask, the chat leads",
                    line: "Ask as you always do. Small things it does itself; anything bigger it splits into briefs."
                )
                introStep(
                    glyph: AnyView(HStack(spacing: -8) {
                        HydraGlyph(persona: HydraRoster.persona(at: 0), size: 24)
                        HydraGlyph(persona: HydraRoster.persona(at: 1), size: 24)
                    }),
                    title: "Heads go out in parallel",
                    line: "Each head gets one brief and a panel of its own beside the chat. Hank, Walter, Ada and the rest work at the same time."
                )
                introStep(
                    glyph: AnyView(Image(systemName: "checkmark.circle").font(.system(size: 20)).foregroundStyle(Chrome.success)),
                    title: "Reports come back, the lead finishes",
                    line: "The lead checks their work, fixes what needs fixing and answers you. Their changes land as one merge."
                )
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pairs")
                    .font(.system(size: 13, weight: .semibold))
                Text("A pair says which model leads and which model, or which provider, runs the heads: Opus leading Sonnet, or Claude leading Gemini heads. Without one, the heads run on this chat's model at a working effort. Pairs live in the model picker and in Settings › Hydra.")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
            }
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "cursorarrow.click.2")
                Text("Right-click the mark to switch Hydra off or on per chat.")
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(Chrome.secondaryText)
            HStack(spacing: 8) {
                Spacer()
                Button("Set up in Settings") {
                    dismiss()
                    WindowManager.shared.showSettings(page: .hydra)
                }
                .buttonStyle(.glass)
                Button("Got it") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func introStep(glyph: AnyView, title: String, line: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            glyph.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: line)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
            }
        }
    }
}
