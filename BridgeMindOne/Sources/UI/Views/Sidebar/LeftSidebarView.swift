//
// LeftSidebarView.swift
// BridgeMind One — Exact Left Sidebar matching original app UI
//

import SwiftUI

public struct LeftSidebarView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            // App Title & Traffic Lights padding
            HStack(spacing: 8) {
                // BridgeMind burst icon
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .yellow, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HStack(spacing: 4) {
                    Text("BridgeMind")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("One")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BMColors.accentBlue)
                }

                Spacer()

                Button {} label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundStyle(BMColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)

            // Top Menu Items
            VStack(spacing: 4) {
                SidebarNavItem(
                    title: "Dashboard",
                    badge: "1",
                    isSelected: appState.selectedLeftSection == .dashboard
                ) {
                    appState.selectedLeftSection = .dashboard
                }

                SidebarNavItem(
                    title: "Routines",
                    isSelected: appState.selectedLeftSection == .routines
                ) {
                    appState.selectedLeftSection = .routines
                }

                SidebarNavItem(
                    title: "Plugins",
                    isSelected: appState.selectedLeftSection == .plugins
                ) {
                    appState.selectedLeftSection = .plugins
                }

                SidebarNavItem(
                    title: "Skills",
                    isSelected: appState.selectedLeftSection == .skills
                ) {
                    appState.selectedLeftSection = .skills
                }
            }
            .padding(.horizontal, 12)

            // Agents Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Agents")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BMColors.textMuted)

                    Spacer()

                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BMColors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 4)

                ForEach(appState.agents) { agent in
                    Button {
                        appState.selectedLeftSection = nil
                        appState.selectedAgentId = agent.id
                    } label: {
                        HStack {
                            Text(agent.name)
                                .font(.system(size: 13, weight: agent.id == appState.selectedAgentId ? .semibold : .regular))
                                .foregroundStyle(agent.id == appState.selectedAgentId ? .white : BMColors.textSecondary)

                            Spacer()

                            if agent.isOnline {
                                Circle()
                                    .fill(BMColors.statusGreen)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            agent.id == appState.selectedAgentId ?
                            Color(red: 0.16, green: 0.16, blue: 0.18) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            Divider()
                .background(BMColors.borderSubtle)

            // Bottom Footer
            VStack(spacing: 12) {
                HStack {
                    Text("Notch")
                        .font(.system(size: 12))
                        .foregroundStyle(BMColors.textSecondary)

                    Spacer()

                    Text(appState.notchEnabled ? "On" : "Off")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BMColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                HStack {
                    Text("Credits")
                        .font(.system(size: 12))
                        .foregroundStyle(BMColors.textSecondary)

                    Spacer()

                    Text(appState.credits)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    // Avatar B
                    ZStack {
                        Circle()
                            .fill(BMColors.accentBlue)
                            .frame(width: 22, height: 22)
                        Text("B")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(appState.username)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BMColors.accentBlue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(BMColors.accentBlue.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    Image(systemName: "moon")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)

                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .frame(width: 210)
        .background(BMColors.sidebar)
    }
}

private struct SidebarNavItem: View {
    let title: String
    var badge: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : BMColors.textSecondary)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
