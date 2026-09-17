import SwiftUI

// Tiny mocks of the app's own interface for the tiles of `ChromeVisualPicker`: a zoomed-in
// corner of the surface a setting changes rather than an icon, drawn with flat shapes in the
// chrome's own colours so they follow the theme. Each fills the 100x48 or 72x48 tile it is
// handed.

/// A line of text.
private struct MockLine: View {
    var width: CGFloat
    var opacity: Double = 0.35

    var body: some View {
        Capsule(style: .continuous)
            .fill(Chrome.primaryText.opacity(opacity))
            .frame(width: width, height: 3)
    }
}

/// A thread row in the sidebar.
private struct MockRow: View {
    var width: CGFloat = 20
    var opacity: Double = 0.35

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Chrome.primaryText.opacity(opacity))
            .frame(width: width, height: 5)
    }
}

/// A working dot or a head's mark.
private struct MockDot: View {
    var size: CGFloat = 5
    var color: Color = Chrome.accent

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// A tiny app window.
private struct MockWindow<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var toolbarButton: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Chrome.overlay(0.08))
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Chrome.overlay(0.10)).frame(height: 8)
                        .overlay(alignment: .leading) {
                            if toolbarButton {
                                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Chrome.primaryText.opacity(0.45))
                                    .frame(width: 7, height: 4).padding(.leading, 4)
                            }
                        }
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// A floating panel over a mock window.
private struct MockPanel<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Chrome.overlay(0.24))
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) { content().padding(4) }
    }
}

struct WorkspacePreview: View {
    let mode: WorkspaceMode
    var body: some View {
        Group {
            switch mode {
            case .local:
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(Chrome.primaryText.opacity(0.7))
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 26)
                        MockLine(width: 20)
                        MockLine(width: 24)
                    }
                }
            case .worktree:
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(Chrome.primaryText.opacity(0.45))
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold)).foregroundStyle(Chrome.secondaryText)
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(Chrome.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkingLinePreview: View {
    let isCard: Bool
    var body: some View {
        Group {
            if isCard {
                VStack(alignment: .leading, spacing: 6) {
                    MockLine(width: 48, opacity: 0.18)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Chrome.overlay(0.12))
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) { MockDot(); MockLine(width: 34, opacity: 0.55) }
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Chrome.overlay(0.18)).frame(height: 3)
                                    Capsule().fill(Chrome.accent).frame(width: 36, height: 3)
                                }
                            }
                            .padding(6)
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MockLine(width: 56, opacity: 0.18)
                    MockLine(width: 44, opacity: 0.18)
                    HStack(spacing: 5) { MockDot(); MockLine(width: 40, opacity: 0.55) }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ThreadFinishPreview: View {
    let action: ThreadFinishAction
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MockRow(width: 52, opacity: 0.35)
            MockRow(width: 46, opacity: 0.35)
            switch action {
            case .settle:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark").font(.system(size: 6, weight: .bold)).foregroundStyle(Chrome.secondaryText.opacity(0.6))
                    MockRow(width: 36, opacity: 0.12)
                }
            case .archive:
                HStack(spacing: 4) {
                    Image(systemName: "archivebox.fill").font(.system(size: 9)).foregroundStyle(Chrome.secondaryText)
                    Image(systemName: "arrow.right").font(.system(size: 7, weight: .bold)).foregroundStyle(Chrome.secondaryText.opacity(0.7))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SidebarModePreview: View {
    enum Style { case column, floating, panelOnly }
    let style: Style
    var body: some View {
        MockWindow(width: 62, height: 40, toolbarButton: style != .panelOnly) {
            switch style {
            case .column:
                HStack(spacing: 0) {
                    Rectangle().fill(Chrome.overlay(0.14)).frame(width: 20)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 3) {
                                MockRow(width: 12)
                                MockRow(width: 9)
                                MockRow(width: 11)
                            }
                            .padding(4)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 26, opacity: 0.28)
                        MockLine(width: 18, opacity: 0.28)
                        MockLine(width: 22, opacity: 0.28)
                    }
                    .padding(5)
                }
            case .floating, .panelOnly:
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 40, opacity: 0.28)
                        MockLine(width: 30, opacity: 0.28)
                        MockLine(width: 36, opacity: 0.28)
                    }
                    .padding(5)
                    // Three 5pt rows and the panel's padding: 27pt, so the panel is 28 tall
                    // and sits 2pt under the strip to stay inside the 32pt content area.
                    MockPanel(width: 24, height: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            MockRow(width: 11)
                            MockRow(width: 8)
                            MockRow(width: 10)
                        }
                    }
                    .offset(x: 3, y: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeadCheckoutPreview: View {
    let isolated: Bool
    var body: some View {
        Group {
            if isolated {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(Chrome.primaryText.opacity(0.45))
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Chrome.secondaryText)
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(Chrome.accent)
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill").font(.system(size: 20)).foregroundStyle(Chrome.primaryText.opacity(0.7))
                    HStack(spacing: 2) { MockDot(size: 5); MockDot(size: 5) }
                        .offset(x: 4, y: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeadPanelPreview: View {
    let showsSteps: Bool
    var body: some View {
        // The steps or the bar sit inside the panel, so the overlay goes on before the inset.
        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Chrome.overlay(0.12))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { MockDot(); MockLine(width: 24, opacity: 0.55) }
                    if showsSteps {
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 40, opacity: 0.3) }
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 32, opacity: 0.3) }
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 36, opacity: 0.3) }
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Chrome.overlay(0.18)).frame(height: 3)
                            Capsule().fill(Chrome.accent).frame(width: 30, height: 3)
                        }
                    }
                }
                .padding(6)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeadsPlacementPreview: View {
    let popped: Bool
    var body: some View {
        MockWindow(width: 88, height: 40) {
            if !popped {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 34, opacity: 0.28)
                        MockLine(width: 26, opacity: 0.28)
                        MockLine(width: 30, opacity: 0.28)
                    }
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Three 5pt rows and the padding come to 27pt: 28 tall, 2pt under the strip.
                    MockPanel(width: 28, height: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) { MockDot(size: 3); MockRow(width: 12, opacity: 0.45) }
                            HStack(spacing: 2) { MockDot(size: 3); MockRow(width: 12, opacity: 0.45) }
                            HStack(spacing: 2) { MockDot(size: 3); MockRow(width: 12, opacity: 0.45) }
                        }
                    }
                    .offset(x: -3, y: 2)
                }
            } else {
                // The team's panel (its heads' marks) top right, a head's own panel (its mark
                // and bar) in each other corner, the chat between them. The panels hang off the
                // whole content area, so the stack fills it; two 12pt panels and their 3pt
                // margins share the 32pt under the strip.
                ZStack {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 26, opacity: 0.28)
                        MockLine(width: 20, opacity: 0.28)
                        MockLine(width: 24, opacity: 0.28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    MockPanel(width: 22, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3); MockDot(size: 3); MockDot(size: 3) }
                    }
                    .offset(x: -3, y: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    MockPanel(width: 22, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3); Capsule().fill(Chrome.accent).frame(width: 10, height: 2) }
                    }
                    .offset(x: -3, y: -3)
                }
                .overlay(alignment: .topLeading) {
                    MockPanel(width: 22, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3); Capsule().fill(Chrome.accent).frame(width: 10, height: 2) }
                    }
                    .offset(x: 3, y: 3)
                }
                .overlay(alignment: .bottomLeading) {
                    MockPanel(width: 22, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3); Capsule().fill(Chrome.accent).frame(width: 10, height: 2) }
                    }
                    .offset(x: 3, y: -3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
