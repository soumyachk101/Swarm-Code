//
// TopNavHeaderView.swift
// BridgeMind One — Top Navigation Header
//

import SwiftUI

public struct TopNavHeaderView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        HStack {
            Spacer()

            // Segmented Mode Switcher [ Agent | Code | Chat ]
            HStack(spacing: 2) {
                ForEach(TopNavMode.allCases) { mode in
                    Button {
                        appState.topMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: appState.topMode == mode ? .semibold : .regular))
                            .foregroundStyle(appState.topMode == mode ? .white : BMColors.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                appState.topMode == mode ?
                                Color(red: 0.22, green: 0.22, blue: 0.25) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Bell notification icon with dot
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 13))
                    .foregroundStyle(BMColors.textSecondary)

                Circle()
                    .fill(BMColors.accentBlue)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: -2)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 38)
        .background(BMColors.sidebar)
        .overlay(
            Divider().background(BMColors.borderSubtle),
            alignment: .bottom
        )
    }
}
