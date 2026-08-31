//
// OrbView.swift
// Animated status orb using Metal shaders
//

import SwiftUI
import MetalKit

public enum OrbState: String, CaseIterable {
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
 .frame(width: 40, height: 40)
 .overlay(
 Circle()
 .fill(.ultraThinMaterial)
 .frame(width: 32, height: 32)
 )
 .shadow(color: orbColors.first.opacity(0.5), radius: 8, x: 0, y: 0)
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

// MARK: - Metal Orb (Production)

#if canImport(Metal)
import Metal

public struct MetalOrbView: View {
 @Binding var state: OrbState
 @State private var rotation: CGFloat = 0
 private let metalView = MTKView()

 public init(state: Binding<OrbState>) {
 self._state = state
 }

 public var body: some View {
 ZStack {
 MetalOrbRenderer(state: state)
 .frame(width: 40, height: 40)
 }
 }
}

// Production Metal orb renderer would use custom shaders here
// The simplified SwiftUI version above is used for now
#endif
