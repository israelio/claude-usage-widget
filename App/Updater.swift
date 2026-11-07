import Foundation
import AppKit
import UsageCore

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate(Date), available(UpdateInfo), downloading, installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    private var settings: AppSettings?
    private var started = false
    private var timer: Timer?
    private static let notifiedKey = "update.lastNotifiedVersion"

    var busy: Bool {
        switch state { case .checking, .downloading, .installing: return true; default: return false }
    }

    func configure(settings: AppSettings) { self.settings = settings }

    func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            self?.checkNow(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow(userInitiated: false) }
        }
    }

    // MARK: capability

    private var teamID: String {
        (Bundle.main.object(forInfoDictionaryKey: "UpdateTeamID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    var canSelfInstall: Bool {
        let url = Bundle.main.bundleURL
        let path = url.path
        guard path.hasSuffix(".app"), !path.contains("/DerivedData/"), !path.contains("/Build/Products/") else { return false }
        guard FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else { return false }
        let t = teamID
        return !t.isEmpty && !t.hasPrefix("$(")
    }

    // MARK: check

    func checkNow(userInitiated: Bool) {
        if busy { return }
        if case .available = state, !userInitiated { return }
        state = .checking
        let checker = UpdateChecker(currentVersion: AppInfo.version)
        Task { [weak self] in
            do {
                let info = try await checker.check()
                guard let self else { return }
                guard let info else { self.state = .upToDate(Date()); return }
                if (self.settings?.prefs.autoUpdate ?? false) && self.canSelfInstall {
                    self.install(info)
                } else {
                    self.state = .available(info)
                    if !userInitiated { self.notifyOnce(info) }
                }
            } catch {
                guard let self else { return }
                self.state = userInitiated ? .failed(Self.message(error)) : .idle
            }
        }
    }

    private func notifyOnce(_ info: UpdateInfo) {
        let d = UserDefaults.standard
        guard d.string(forKey: Self.notifiedKey) != info.version else { return }
        d.set(info.version, forKey: Self.notifiedKey)
        Notifier.post(AlertMessage(id: "update", title: "Claude Usage \(info.version) is available",
                                   body: "Open the menu bar panel > About to install."))
    }

    private static func message(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if let u = error as? URLError { return u.localizedDescription }
        return "Update failed: \(error.localizedDescription)"
    }

    // MARK: install

    func install(_ info: UpdateInfo) {
        guard canSelfInstall else { return }
        if state == .downloading || state == .installing { return }
        state = .downloading
        let team = teamID
        let current = AppInfo.version
        let dest = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        Task { [weak self] in
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ClaudeUsageUpdate-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let dmg = try await Self.download(info, into: tmp)
                await MainActor.run { self?.state = .installing }
                let script = try await Task.detached {
                    try Self.stageAndVerify(dmg: dmg, tmp: tmp, team: team, version: info.version, current: current, dest: dest, pid: pid)
                }.value
                await MainActor.run {
                    Notifier.post(AlertMessage(id: "update-run", title: "Updating Claude Usage to \(info.version)…", body: ""))
                    do {
                        try Self.launchDetached(script)
                        NSApp.terminate(nil)
                    } catch {
                        self?.state = .failed(Self.message(error))
                        try? FileManager.default.removeItem(at: tmp)
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                await MainActor.run { self?.state = .failed(Self.message(error)) }
            }
        }
    }

    private struct InstallError: LocalizedError { let errorDescription: String? ; init(_ m: String) { errorDescription = m } }

    nonisolated private static func download(_ info: UpdateInfo, into tmp: URL) async throws -> URL {
        guard let shaURL = info.sha256URL else { throw InstallError("Release has no checksum file") }
        var shaReq = URLRequest(url: shaURL, timeoutInterval: 30)
        shaReq.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (shaData, shaResp) = try await URLSession.shared.data(for: shaReq)
        guard (shaResp as? HTTPURLResponse)?.statusCode == 200,
              let expected = Checksum.parse(String(decoding: shaData, as: UTF8.self))
        else { throw InstallError("Checksum file is invalid") }

        let (file, resp) = try await URLSession.shared.download(from: info.dmgURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("Download failed") }
        let dmg = tmp.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: file, to: dmg)
        guard try Checksum.sha256(of: dmg) == expected else { throw InstallError("Checksum mismatch; update discarded") }
        return dmg
    }

    nonisolated private static func stageAndVerify(dmg: URL, tmp: URL, team: String, version: String,
                                                   current: String, dest: String, pid: Int32) throws -> URL {
        let fm = FileManager.default
        let mnt = tmp.appendingPathComponent("mnt"), stage = tmp.appendingPathComponent("stage")
        try fm.createDirectory(at: mnt, withIntermediateDirectories: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let r = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mnt.path, dmg.path])
        guard r.status == 0 else { throw InstallError("Could not open the update image") }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mnt.path]) }

        let staged = stage.appendingPathComponent("Claude Usage.app")
        let c = try run("/usr/bin/ditto", [mnt.appendingPathComponent("Claude Usage.app").path, staged.path])
        guard c.status == 0 else { throw InstallError("Could not extract the new app") }

        guard try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]).status == 0 else {
            throw InstallError("Signature check failed")
        }
        guard try run("/usr/sbin/spctl", ["-a", "-t", "exec", "-vv", staged.path]).status == 0 else {
            throw InstallError("Gatekeeper rejected the new app")
        }
        let d = try run("/usr/bin/codesign", ["-dv", "--verbose=2", staged.path])
        guard d.output.split(separator: "\n").contains(where: { $0 == "TeamIdentifier=\(team)" }) else {
            throw InstallError("New app is signed by a different team")
        }
        guard let plist = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist")),
              let v = plist["CFBundleShortVersionString"] as? String, v == version,
              let nv = AppVersion(v), let cv = AppVersion(current), nv > cv
        else { throw InstallError("New app version does not match the release") }

        let script = tmp.appendingPathComponent("update.sh")
        try UpdateScript.make(pid: pid, newApp: staged.path, destApp: dest).write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    nonisolated private static func launchDetached(_ script: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    /// Single Process helper; arguments are passed as an array, never through a shell.
    nonisolated private static func run(_ launchPath: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
