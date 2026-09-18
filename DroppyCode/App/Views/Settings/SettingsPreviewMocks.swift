import SwiftUI

// Tiny mocks of the app's own interface for the tiles of `ChromeVisualPicker`: a zoomed-in
// corner of the surface a setting changes rather than an icon, drawn with flat shapes in the
// chrome's own colours so they follow the theme. Each fills the 100x48 or 72x48 tile it is
// handed.

private struct MockPalette {
    static func highlight(_ selected: Bool) -> Color { selected ? Chrome.accent : Chrome.primaryText.opacity(0.55) }
    static func highlightFill(_ selected: Bool) -> Color { selected ? Chrome.accent.opacity(0.28) : Chrome.overlay(0.26) }
}

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
    var color: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color ?? Chrome.primaryText.opacity(opacity))
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
    var toolbarButton: Bool = false
    @Environment(\.chromeTileIsSelected) private var isSelected
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    Circle().fill(Chrome.primaryText.opacity(0.22)).frame(width: 3, height: 3)
                    Circle().fill(Chrome.primaryText.opacity(0.22)).frame(width: 3, height: 3)
                    Circle().fill(Chrome.primaryText.opacity(0.22)).frame(width: 3, height: 3)
                }
                .padding(.leading, 4)
                if toolbarButton {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(MockPalette.highlight(isSelected))
                        .frame(width: 7, height: 5)
                        .padding(.leading, 4)
                }
                Spacer()
            }
            .frame(height: 11)
            .frame(maxWidth: .infinity)
            .background(Chrome.overlay(0.10))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A floating panel over a mock window.
private struct MockPanel<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    @Environment(\.chromeTileIsSelected) private var isSelected
    @ViewBuilder var content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(MockPalette.highlightFill(isSelected))
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) { content().padding(3) }
    }
}

struct WorkspacePreview: View {
    let mode: WorkspaceMode
    @Environment(\.chromeTileIsSelected) private var isSelected
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
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(MockPalette.highlight(isSelected))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkingLinePreview: View {
    let isCard: Bool
    @Environment(\.chromeTileIsSelected) private var isSelected
    var body: some View {
        Group {
            if isCard {
                VStack(alignment: .leading, spacing: 6) {
                    MockLine(width: 48, opacity: 0.26)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Chrome.overlay(0.12))
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 5) { MockDot(color: MockPalette.highlight(isSelected)); MockLine(width: 34, opacity: 0.55) }
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Chrome.overlay(0.18)).frame(height: 3)
                                    Capsule().fill(MockPalette.highlight(isSelected)).frame(width: 36, height: 3)
                                }
                            }
                            .padding(6)
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MockLine(width: 56, opacity: 0.26)
                    MockLine(width: 44, opacity: 0.26)
                    HStack(spacing: 5) { MockDot(color: MockPalette.highlight(isSelected)); MockLine(width: 40, opacity: 0.55) }
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
    @Environment(\.chromeTileIsSelected) private var isSelected
    var body: some View {
        MockWindow(toolbarButton: style != .panelOnly) {
            switch style {
            case .column:
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        MockRow(width: 13, color: MockPalette.highlight(isSelected))
                        MockRow(width: 9, color: MockPalette.highlight(isSelected))
                        MockRow(width: 12, color: MockPalette.highlight(isSelected))
                    }
                    .padding(4)
                    .frame(width: 22)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(MockPalette.highlightFill(isSelected))
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 24, opacity: 0.30)
                        MockLine(width: 16, opacity: 0.30)
                        MockLine(width: 20, opacity: 0.30)
                    }
                    .padding(5)
                }
            case .floating:
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 40, opacity: 0.30)
                        MockLine(width: 28, opacity: 0.30)
                        MockLine(width: 34, opacity: 0.30)
                    }
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MockPanel(width: 26, height: 30) {
                        VStack(alignment: .leading, spacing: 3) {
                            MockRow(width: 13, color: MockPalette.highlight(isSelected))
                            MockRow(width: 9, color: MockPalette.highlight(isSelected))
                            MockRow(width: 12, color: MockPalette.highlight(isSelected))
                        }
                    }
                    .offset(x: 4, y: 3)
                }
            case .panelOnly:
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 28, opacity: 0.30)
                        MockLine(width: 18, opacity: 0.30)
                        MockLine(width: 24, opacity: 0.30)
                    }
                    .padding(.top, 5)
                    .padding(.trailing, 5)
                    .padding(.leading, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MockPanel(width: 30, height: 30) {
                        VStack(alignment: .leading, spacing: 3) {
                            MockRow(width: 13, color: MockPalette.highlight(isSelected))
                            MockRow(width: 9, color: MockPalette.highlight(isSelected))
                            MockRow(width: 12, color: MockPalette.highlight(isSelected))
                        }
                    }
                    .offset(x: 3, y: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeadCheckoutPreview: View {
    let isolated: Bool
    @Environment(\.chromeTileIsSelected) private var isSelected
    var body: some View {
        Group {
            if isolated {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(Chrome.primaryText.opacity(0.45))
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Chrome.secondaryText)
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(MockPalette.highlight(isSelected))
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill").font(.system(size: 20)).foregroundStyle(Chrome.primaryText.opacity(0.7))
                    HStack(spacing: 2) { MockDot(size: 5, color: MockPalette.highlight(isSelected)); MockDot(size: 5, color: MockPalette.highlight(isSelected)) }
                        .offset(x: 4, y: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeadPanelPreview: View {
    let showsSteps: Bool
    @Environment(\.chromeTileIsSelected) private var isSelected
    var body: some View {
        // The steps or the bar sit inside the panel, so the overlay goes on before the inset.
        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Chrome.overlay(0.12))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { MockDot(color: MockPalette.highlight(isSelected)); MockLine(width: 24, opacity: 0.55) }
                    if showsSteps {
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 40, opacity: 0.3) }
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 32, opacity: 0.3) }
                        HStack(spacing: 3) { MockDot(size: 3, color: Chrome.secondaryText); MockLine(width: 36, opacity: 0.3) }
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Chrome.overlay(0.18)).frame(height: 3)
                            Capsule().fill(MockPalette.highlight(isSelected)).frame(width: 30, height: 3)
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
    @Environment(\.chromeTileIsSelected) private var isSelected
    var body: some View {
        MockWindow(toolbarButton: false) {
            if !popped {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 34, opacity: 0.28)
                        MockLine(width: 26, opacity: 0.28)
                        MockLine(width: 30, opacity: 0.28)
                    }
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MockPanel(width: 28, height: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); MockRow(width: 12, opacity: 0.45) }
                            HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); MockRow(width: 12, opacity: 0.45) }
                            HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); MockRow(width: 12, opacity: 0.45) }
                        }
                    }
                    .offset(x: -3, y: 2)
                }
            } else {
                ZStack {
                    VStack(alignment: .leading, spacing: 4) {
                        MockLine(width: 26, opacity: 0.28)
                        MockLine(width: 20, opacity: 0.28)
                        MockLine(width: 24, opacity: 0.28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    MockPanel(width: 24, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); MockDot(size: 3, color: MockPalette.highlight(isSelected)); MockDot(size: 3, color: MockPalette.highlight(isSelected)) }
                    }
                    .offset(x: -3, y: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    MockPanel(width: 24, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); Capsule().fill(MockPalette.highlight(isSelected)).frame(width: 10, height: 2) }
                    }
                    .offset(x: -3, y: -3)
                }
                .overlay(alignment: .topLeading) {
                    MockPanel(width: 24, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); Capsule().fill(MockPalette.highlight(isSelected)).frame(width: 10, height: 2) }
                    }
                    .offset(x: 3, y: 3)
                }
                .overlay(alignment: .bottomLeading) {
                    MockPanel(width: 24, height: 12) {
                        HStack(spacing: 2) { MockDot(size: 3, color: MockPalette.highlight(isSelected)); Capsule().fill(MockPalette.highlight(isSelected)).frame(width: 10, height: 2) }
                    }
                    .offset(x: 3, y: -3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The activity list's rows in either style: the project's emoji before the thread's name
/// on one line, or the project's name, with a folder mark, on a line under the title.
struct ActivityThreadStylePreview: View {
    let style: ActivityThreadStyle
    @Environment(\.chromeTileIsSelected) private var isSelected

    var body: some View {
        MockWindow {
            VStack(alignment: .leading, spacing: 4) {
                row(mark: "🚀", width: 24)
                row(mark: "🛠️", width: 18)
                // A second line per row needs the room the third row would take.
                if style == .icon {
                    row(mark: "🎨", width: 21)
                }
            }
            .padding(.horizontal, 5)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private func row(mark: String, width: CGFloat) -> some View {
        switch style {
        case .icon:
            HStack(spacing: 3) {
                Text(verbatim: mark)
                    .font(.system(size: 7))
                MockRow(width: width, color: MockPalette.highlight(isSelected))
            }
        case .projectName:
            VStack(alignment: .leading, spacing: 2) {
                MockRow(width: width, color: MockPalette.highlight(isSelected))
                HStack(spacing: 2) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Chrome.secondaryText)
                    MockLine(width: width * 0.8, opacity: 0.5)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
