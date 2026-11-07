import SwiftUI

/// Flat, subtly filled button with a hover highlight and a tooltip.
struct FlatIconButton: View {
    let systemImage: String
    var title: String? = nil
    let help: String
    var hoverTint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                if let title { Text(title) }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hovering ? hoverTint : Color.secondary)
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(minWidth: 30, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? hoverTint.opacity(0.18) : Color.primary.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
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
