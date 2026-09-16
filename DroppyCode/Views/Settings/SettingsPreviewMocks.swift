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
    private var chatLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            MockLine(width: 30, opacity: 0.28)
            MockLine(width: 22, opacity: 0.28)
            MockLine(width: 26, opacity: 0.28)
        }
    }
    var body: some View {
        Group {
            switch style {
            case .column:
                HStack(spacing: 0) {
                    Chrome.overlay(0.10)
                        .frame(width: 34)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                MockRow(width: 20)
                                MockRow(width: 16)
                                MockRow(width: 18)
                            }
                            .padding(6)
                        }
                    chatLines
                        .padding(.leading, 8)
                }
            case .floating, .panelOnly:
                ZStack(alignment: .topLeading) {
                    chatLines
                        .padding(.leading, 14).padding(.top, 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Chrome.overlay(0.18))
                        .frame(width: 30, height: 30)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                MockRow(width: 18)
                                MockRow(width: 14)
                                MockRow(width: 16)
                            }
                            .padding(5)
                        }
                        .offset(x: 6, y: style == .floating ? 13 : 9)
                    if style == .floating {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Chrome.primaryText.opacity(0.35))
                            .frame(width: 9, height: 6)
                            .offset(x: 6, y: 4)
                    }
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
        Group {
            if !popped {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Chrome.overlay(0.10))
                    .frame(width: 60, height: 36)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            MockLine(width: 40, opacity: 0.28)
                            MockLine(width: 30, opacity: 0.28)
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Chrome.overlay(0.18))
                                .frame(width: 44, height: 9)
                                .overlay(alignment: .leading) {
                                    MockDot(size: 3).padding(.leading, 3)
                                }
                        }
                        .padding(5)
                    }
            } else {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Chrome.overlay(0.18))
                        .frame(width: 16, height: 36)
                        .overlay(alignment: .top) {
                            MockDot(size: 3).padding(.top, 4)
                        }
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Chrome.overlay(0.10))
                        .frame(width: 40, height: 36)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                MockLine(width: 28, opacity: 0.28)
                                MockLine(width: 20, opacity: 0.28)
                            }
                            .padding(5)
                        }
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Chrome.overlay(0.18))
                        .frame(width: 16, height: 36)
                        .overlay(alignment: .top) {
                            MockDot(size: 3).padding(.top, 4)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
