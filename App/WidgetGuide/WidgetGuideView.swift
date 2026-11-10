import SwiftUI
import AppKit

enum WidgetGuideMode { case firstRun, settings }

enum DesktopSettingsLink {
    static let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    static func open() { NSWorkspace.shared.open(url) }
}

struct WidgetGuideView: View {
    let mode: WidgetGuideMode
    var close: () -> Void = {}
    @StateObject private var status = WidgetStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .firstRun {
                Text("Welcome to Claude Usage! Want desktop widgets? Here's how.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            Text("Add desktop widgets").font(.title2.bold())
            Text("Widgets show your 5-hour and weekly limits right on the desktop. macOS only lets you add widgets yourself, so here's how:")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "cursorarrow.click.2", "Right-click an empty spot on the desktop")
                    step(2, "square.grid.2x2", "Choose Edit Widgets…")
                    step(3, "magnifyingglass", "Search for Claude Usage and click a size (Small, Medium or Large), or drag it onto the desktop")
                    VStack(alignment: .leading, spacing: 6) {
                        step(4, "paintpalette", "Tip: for colour, System Settings → Desktop & Dock → Widgets → Widget style → Full-color")
                        Button("Open Desktop & Dock settings") { DesktopSettingsLink.open() }
                            .controlSize(.small).padding(.leading, 34)
                    }
                }
            }

            statusRow

            Spacer(minLength: 0)
            HStack {
                Spacer()
                switch mode {
                case .firstRun:
                    Button("Not now", action: close)
                    Button("Done", action: close).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .settings:
                    Button("Close", action: close)
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 520, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .onAppear { status.start() }
        .onDisappear { status.stop() }
    }

    private func step(_ n: Int, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 24).foregroundStyle(.orange)
            Text("\(n). \(text)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 8) {
            if let n = status.placedCount, n > 0 {
                Text("✓ \(n) widget\(n == 1 ? "" : "s") on your desktop").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for you to add a widget…").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}
