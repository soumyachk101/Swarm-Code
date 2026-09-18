import AppKit
import SwiftUI

// A project's mark: the emoji or the SF Symbol it wears in the activity list's icon style,
// and the picker that chooses it. Core owns the value (`ProjectIcon`); this file draws it,
// keeps the shortlist a popover can show, and presents that popover.

/// A project's mark as the rows draw it: the emoji or symbol the reader picked, or the
/// folder mark until one has been picked.
struct ProjectIconMark: View {
    let icon: ProjectIcon?
    var size: CGFloat = 13

    var body: some View {
        Group {
            if let emoji = icon?.emoji {
                Text(verbatim: emoji)
                    .font(.system(size: size))
            } else {
                Image(systemName: icon?.symbolName ?? "folder.fill")
                    .font(.system(size: size))
            }
        }
        .foregroundStyle(Chrome.primaryText.opacity(0.9))
    }
}

/// A project's mark as a button: clicking it opens the picker over it.
struct ProjectIconButton: View {
    @Binding var icon: ProjectIcon?
    var size: CGFloat = 13

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ProjectIconMark(icon: icon, size: size)
                .frame(width: size + 9, height: size + 9)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Choose this project's icon")
        .accessibilityLabel(Text("Project icon"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ProjectIconPicker(icon: $icon)
        }
    }
}

/// Chooses a project's mark: an emoji grid, a search over the SF Symbols the app offers,
/// and a Folder tile that clears the mark back to its default.
struct ProjectIconPicker: View {
    @Binding var icon: ProjectIcon?

    @State private var query = ""

    private static let emojis = [
        "🚀", "🛠️", "📦", "🎨", "🧪", "🌱", "🔥", "🧩",
        "📊", "🕹️", "🎯", "🧠", "⚙️", "💎", "🪄", "🍿",
        "🛰️", "🧭", "📚", "🔮", "🐙", "🦀", "🐝", "🦊",
        "🌊", "🌙", "⚡️", "🍀", "🧵", "🏗️", "🔧", "🧰",
    ]

    /// The symbols the picker names, each checked against this Mac's own catalogue as the
    /// list is first read, so a name the system does not have is never offered.
    private static let symbols: [String] = candidates.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

    private static let candidates = [
        "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "terminal.fill",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "shippingbox.fill", "paintbrush.fill",
        "flask.fill", "leaf.fill", "flame.fill", "puzzlepiece.fill",
        "chart.bar.fill", "gamecontroller.fill", "target", "brain.head.profile",
        "diamond.fill", "wand.and.stars", "popcorn.fill", "antenna.radiowaves.left.and.right",
        "globe", "cursorarrow.rays", "point.3.connected.trianglepath.dotted", "bolt.fill",
        "bolt.horizontal.fill", "sparkles", "star.fill", "heart.fill",
        "book.fill", "cloud.fill", "moon.stars.fill", "cup.and.saucer.fill",
        "cpu", "externaldrive.fill", "camera.fill", "music.note",
    ]

    private static let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 8)

    /// The symbols the query names, with the one the reader typed in front when the
    /// catalogue knows a symbol by that name the shortlist does not hold.
    private var matchingSymbols: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var names = Self.symbols.filter { $0.localizedCaseInsensitiveContains(needle) }
        if !names.contains(needle), NSImage(systemSymbolName: needle, accessibilityDescription: nil) != nil {
            names.insert(needle, at: 0)
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Project icon")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if matchingSymbols.isEmpty {
                        emojiGrid
                        symbolGrid(Self.symbols)
                    } else {
                        symbolGrid(matchingSymbols)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            Divider()
                .overlay(Chrome.overlay(0.12))
            HStack(spacing: 8) {
                IconTile(isSelected: icon == nil, action: { icon = nil }) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                }
                Text(verbatim: "Folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: 272, height: 330)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
            TextField("Search symbols", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Chrome.overlay(0.10))
        }
    }

    private var emojiGrid: some View {
        section("Emoji") {
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    IconTile(isSelected: icon?.emoji == emoji, action: { icon = .emoji(emoji) }) {
                        Text(verbatim: emoji)
                            .font(.system(size: 15))
                    }
                }
            }
        }
    }

    private func symbolGrid(_ names: [String]) -> some View {
        section("Symbols") {
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(names, id: \.self) { name in
                    IconTile(isSelected: icon?.symbolName == name, action: { icon = .symbol(name) }) {
                        Image(systemName: name)
                            .font(.system(size: 12))
                            .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Chrome.secondaryText)
            content()
        }
    }
}

/// One mark in the picker's grid: a tile that fills as the pointer crosses it and wears the
/// accent ring when it is the project's mark.
private struct IconTile<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Chrome.overlay(isHovering || isSelected ? 0.14 : 0))
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Chrome.accent, lineWidth: 1.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
    }
}
