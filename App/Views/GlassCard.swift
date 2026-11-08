import SwiftUI

struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.compact) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            if let title {
                HStack {
                    if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(compact ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                if scheme == .dark { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
