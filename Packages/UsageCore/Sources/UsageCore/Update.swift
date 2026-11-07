import Foundation
import CryptoKit

public struct AppVersion: Comparable, Equatable, Sendable {
    public let major: Int, minor: Int, patch: Int
    public let prerelease: String?

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        var pre: String?
        if let dash = s.firstIndex(of: "-") {
            pre = String(s[s.index(after: dash)...])
            s = String(s[..<dash])
            if pre?.isEmpty == true { return nil }
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            nums.append(n)
        }
        while nums.count < 3 { nums.append(0) }
        major = nums[0]; minor = nums[1]; patch = nums[2]; prerelease = pre
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let x = [a.major, a.minor, a.patch], y = [b.major, b.minor, b.patch]
        if x != y { return x.lexicographicallyPrecedes(y) }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_?, nil): return true
        case let (p?, q?): return p.compare(q, options: .numeric) == .orderedAscending
        }
    }
}

public struct UpdateInfo: Equatable, Sendable {
    public let version: String
    public let notes: String
    public let pageURL: URL
    public let dmgURL: URL
    public let sha256URL: URL?
    public init(version: String, notes: String, pageURL: URL, dmgURL: URL, sha256URL: URL?) {
        self.version = version; self.notes = notes; self.pageURL = pageURL
        self.dmgURL = dmgURL; self.sha256URL = sha256URL
    }
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case http(Int)
    case noDMGAsset
    case badResponse
    public var errorDescription: String? {
        switch self {
        case .http(let c): return (c == 403 || c == 429) ? "GitHub rate limit reached (HTTP \(c))" : "GitHub returned HTTP \(c)"
        case .noDMGAsset: return "The latest release has no DMG"
        case .badResponse: return "Unexpected response from GitHub"
        }
    }
}

public struct UpdateChecker: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let latestURL = URL(string: "https://api.github.com/repos/israelio/claude-usage-widget/releases/latest")!

    let currentVersion: String
    let transport: Transport

    public init(currentVersion: String, transport: @escaping Transport = UpdateChecker.liveTransport) {
        self.currentVersion = currentVersion; self.transport = transport
    }

    public static let liveTransport: Transport = { req in
        var r = req; r.timeoutInterval = 15
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard let h = resp as? HTTPURLResponse else { throw UpdateError.badResponse }
        return (d, h)
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    public func check() async throws -> UpdateInfo? {
        var req = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await transport(req)
        guard resp.statusCode == 200 else { throw UpdateError.http(resp.statusCode) }
        guard let rel = try? JSONDecoder().decode(Release.self, from: data) else { throw UpdateError.badResponse }
        if rel.draft == true || rel.prerelease == true { return nil }
        guard let latest = AppVersion(rel.tag_name) else { throw UpdateError.badResponse }
        guard let cur = AppVersion(currentVersion), latest > cur else { return nil }
        let assets = rel.assets ?? []
        guard let dmg = assets.first(where: { $0.name.hasSuffix(".dmg") }) else { throw UpdateError.noDMGAsset }
        let sha = assets.first(where: { $0.name.hasSuffix(".dmg.sha256") })
        var v = rel.tag_name
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return UpdateInfo(version: v, notes: rel.body ?? "", pageURL: rel.html_url,
                          dmgURL: dmg.browser_download_url, sha256URL: sha?.browser_download_url)
    }
}

public enum Checksum {
    public static func parse(_ text: String) -> String? {
        guard let tok = text.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let s = String(tok).lowercased()
        guard s.count == 64, s.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return s
    }

    public static func sha256(of fileURL: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: fileURL)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum UpdateScript {
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public static func make(pid: Int32, newApp: String, destApp: String) -> String {
        """
        #!/bin/bash
        PID=\(pid)
        NEW=\(q(newApp))
        DEST=\(q(destApp))
        OLD="$DEST.old"
        # wait (max ~60s) for the running app to exit
        for _ in $(seq 1 120); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.5
        done
        if kill -0 "$PID" 2>/dev/null; then exit 1; fi
        rm -rf "$OLD"
        if ! mv "$DEST" "$OLD"; then open "$DEST"; exit 1; fi
        if ! ditto "$NEW" "$DEST"; then
          rm -rf "$DEST"
          mv "$OLD" "$DEST"
          open "$DEST"
          exit 1
        fi
        rm -rf "$OLD"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"

        """
    }
}
