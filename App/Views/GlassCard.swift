import SwiftUI

struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
