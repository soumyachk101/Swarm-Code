import AppKit
import SwiftUI

struct TerminalPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let runtime: ThreadRuntime
    let directory: String

    @State private var dragOrigin: Double?

    var body: some View {
        let terminals = model.terminals
        let sessions = terminals.sessions(for: runtime.threadID)
        let selected = terminals.selected(for: runtime.threadID)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sessions) { session in
                            TerminalTab(
                                session: session,
                                isSelected: session.id == selected?.id,
                                select: { terminals.selection[runtime.threadID] = session.id },
                                close: { terminals.close(session) }
                            )
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    terminals.open(threadID: runtime.threadID, directory: directory)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.chip)
                .help("New terminal")
                Spacer(minLength: 0)
                Button {
                    runtime.isTerminalVisible = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.chip)
                .help("Hide terminal (⌘J)")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(.rect)
            .gesture(resize)

            if let selected {
                TerminalHost(session: selected, isDark: colorScheme == .dark)
                    .id(selected.id)
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            } else {
                Spacer()
            }
        }
        .frame(height: model.settings.terminalHeight)
        // Rounded top corners, so the panel reads as a sheet rising into the conversation.
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Chrome.sheetCornerRadius,
                topTrailingRadius: Chrome.sheetCornerRadius,
                style: .continuous
            )
            .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.985))
        )
        .onAppear { terminals.ensureTerminal(threadID: runtime.threadID, directory: directory) }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let origin = dragOrigin ?? model.settings.terminalHeight
                if dragOrigin == nil { dragOrigin = origin }
                model.settings.terminalHeight = min(760, max(140, origin - value.translation.height))
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

private struct TerminalTab: View {
    let session: TerminalSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption)
            Text(session.title)
                .lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(isSelected ? AnyShapeStyle(.primary.opacity(0.08)) : AnyShapeStyle(Color.clear), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .opacity(session.isRunning ? 1 : 0.55)
    }
}

/// Hosts a long-lived terminal view, moving it between containers as threads change.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        session.applyAppearance(isDark: isDark)
        if session.view.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        let view = session.view
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        session.applyAppearance(isDark: isDark)
    }
}
