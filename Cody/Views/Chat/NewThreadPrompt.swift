import AppKit
import SwiftUI

/// What a thread shows before its first message: the app icon and a question about the project.
struct NewThreadPrompt: View {
    let projectName: String?

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 26) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            question
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Chrome.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.97)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { isVisible = true }
        }
    }

    private var question: Text {
        guard let projectName, !projectName.isEmpty else {
            return Text("What should we build?")
        }
        let name = Text(verbatim: projectName)
            .underline(true, pattern: .dot, color: Chrome.secondaryText)
        return Text("What should we build in \(name)?")
    }
}
