import SwiftUI

/// Raised, keycap-style icon button: gradient face, lit top edge, drop shadow, and a pressed-in state.
struct RaisedIconButton: View {
    let systemImage: String
    var title: String? = nil
    let help: String
    var hoverTint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                if let title { Text(title) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hovering ? (hoverTint ?? Color.white) : Color.white.opacity(0.80))
            .padding(.horizontal, title == nil ? 0 : 10)
            .frame(minWidth: 32, minHeight: 28)
        }
        .buttonStyle(RaisedButtonStyle(hovering: hovering, tint: hoverTint))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .help(help)
    }
}

private struct RaisedButtonStyle: ButtonStyle {
    let hovering: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .background(
                ZStack {
                    shape.fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                    shape.fill(LinearGradient(
                        colors: pressed ? [.black.opacity(0.40), .white.opacity(0.02)]
                                        : [.white.opacity(hovering ? 0.20 : 0.11), .white.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom))
                    if hovering, let tint { shape.fill(tint.opacity(0.28)) }
                }
            )
            .overlay(shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(pressed ? 0.08 : 0.38), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(pressed ? 0.15 : 0.45), radius: pressed ? 1 : 2.5, y: pressed ? 0.5 : 2)
            .offset(y: pressed ? 1 : 0)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Small floating readout used by chart hover annotations.
struct ChartTip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}
