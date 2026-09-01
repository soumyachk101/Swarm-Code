//
// OrbView.swift
// Animated status orb
//

import SwiftUI

public enum OrbState: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    case error
    case disconnected
}

public struct OrbView: View {
    @Binding var state: OrbState

    public init(state: Binding<OrbState>) {
        self._state = state
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: orbColors),
                        center: .center
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 28, height: 28)
                )
                .shadow(color: (orbColors.first ?? .blue).opacity(0.5), radius: 8, x: 0, y: 0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: state)
        }
    }

    private var orbColors: [Color] {
        switch state {
        case .idle:
            return [.blue, .cyan]
        case .listening:
            return [.green, .mint]
        case .thinking:
            return [.purple, .pink]
        case .speaking:
            return [.orange, .yellow]
        case .error:
            return [.red, .orange]
        case .disconnected:
            return [.gray, .secondary]
        }
    }
}
