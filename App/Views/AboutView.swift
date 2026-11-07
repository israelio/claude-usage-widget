import SwiftUI
import AppKit

struct AboutView: View {
    static let repoURL = URL(string: "https://github.com/israelio/claude-usage-widget")!

    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("Claude Usage").font(.title3.bold())
            Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            updateRow

            Divider().padding(.vertical, 2)

            Text("Made by Ohad Israeli").font(.system(size: 13, weight: .semibold))

            VStack(spacing: 4) {
                Label("Staraware software", systemImage: "star.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow)
                Text("Instead of paying, pay with stars ⭐️\nIf you like this app, please add a star to the repo.")
                    .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }

            Button { NSWorkspace.shared.open(Self.repoURL) } label: {
                Label("Star on GitHub", systemImage: "star")
            }
            .buttonStyle(.borderedProminent).tint(.orange)

            Link(Self.repoURL.absoluteString, destination: Self.repoURL)
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 280)
    }

    @ViewBuilder private var updateRow: some View {
        HStack(spacing: 6) {
            Button("Check for updates") { updater.checkNow(userInitiated: true) }
                .controlSize(.small).disabled(updater.busy)
            if updater.busy { ProgressView().controlSize(.small) }
        }
        switch updater.state {
        case .upToDate:
            Text("You're up to date").font(.caption).foregroundStyle(.secondary)
        case .available(let info):
            Text("Version \(info.version) available").font(.caption).foregroundStyle(.secondary)
            if updater.canSelfInstall {
                Button("Install & restart") { updater.install(info) }.controlSize(.small)
            } else {
                Button("Download") { NSWorkspace.shared.open(info.pageURL) }.controlSize(.small)
            }
        case .failed(let msg):
            Text(msg).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        default: EmptyView()
        }
    }
}
