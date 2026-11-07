import SwiftUI
import AppKit

/// Small "Star on GitHub" call-to-action (the app is staraware).
struct StarPill: View {
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(AboutView.repoURL) } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("Star on GitHub")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(hovering ? Color.white : Color.white.opacity(0.8))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.yellow.opacity(hovering ? 0.28 : 0.14)))
            .overlay(Capsule().strokeBorder(Color.yellow.opacity(hovering ? 0.6 : 0.35), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .help("Staraware: instead of paying, pay with a star. Click to open the GitHub repo.")
    }
}
