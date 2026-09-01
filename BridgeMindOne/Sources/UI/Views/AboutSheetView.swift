//
// AboutSheetView.swift
// About dialog
//

import SwiftUI

public struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appVersion: String = "0.1.12"
    @State private var buildNumber: String = "88ada94"

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Logo
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("BridgeMind One")
                    .font(.title.bold())

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Copyright © BridgeMind LLC. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Built with:")
                    .font(.caption.bold())
                Text("SwiftUI, Metal, GRDB, PostHog, Sparkle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Website") {
                    if let url = URL(string: "https://bridgemind.ai") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Documentation") {
                    if let url = URL(string: "https://docs.bridgemind.ai") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
