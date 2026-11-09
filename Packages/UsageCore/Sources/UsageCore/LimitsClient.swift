import Foundation
import Security

public enum LimitsError: Error, Equatable, LocalizedError {
    case noToken, unauthorized, http(Int), badResponse, timeout, keychainBusy, keychainLocked
    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Claude Code login found in Keychain"
        case .unauthorized: return "Login expired — run Claude Code to sign in again"
        case .http(let c): return "Usage API error (HTTP \(c))"
        case .badResponse: return "Unexpected usage API response"
        case .timeout: return "Timed out waiting for Keychain/usage API"
        case .keychainBusy: return "Waiting for Keychain access — approve the prompt"
        case .keychainLocked: return "Keychain is locked — unlock it to refresh"
        }
    }
}

public protocol LimitsProviding: Sendable { func fetch() async throws -> LimitsSnapshot }
public protocol TokenProviding: Sendable {
    func accessToken() throws -> String
    /// Called when the server rejects the token, so the next call may re-read it from its source.
    func invalidate()
}
public extension TokenProviding { func invalidate() {} }

public struct TokenCredentials: Equatable, Sendable {
    public var token: String
    public var expiresAt: Date?
    public init(token: String, expiresAt: Date?) { self.token = token; self.expiresAt = expiresAt }
}

/// Keeps the OAuth token in memory so the Keychain (which may show a permission prompt) is read only
/// when the token is about to expire or was rejected, not on every poll.
public final class CachingTokenProvider: TokenProviding, @unchecked Sendable {
    private struct Entry { var creds: TokenCredentials; var loadedAt: Date; var invalidated = false }
    private let source: @Sendable () throws -> TokenCredentials
    private let now: @Sendable () -> Date
    private let skew: TimeInterval
    private let minReload: TimeInterval
    private let lock = NSLock()
    private var entry: Entry?

    /// - skew: treat the token as expired this many seconds before `expiresAt`.
    /// - minReload: never re-read the source more often than this, even if the token looks expired/invalid.
    public init(source: @escaping @Sendable () throws -> TokenCredentials,
                now: @escaping @Sendable () -> Date = { Date() },
                skew: TimeInterval = 60, minReload: TimeInterval = 120) {
        self.source = source; self.now = now; self.skew = skew; self.minReload = minReload
    }

    public func accessToken() throws -> String {
        lock.lock()
        if let e = entry {
            let t = now()
            let fresh = e.creds.expiresAt.map { $0.timeIntervalSince(t) > skew } ?? true
            if (fresh && !e.invalidated) || t.timeIntervalSince(e.loadedAt) < minReload {
                lock.unlock(); return e.creds.token
            }
        }
        lock.unlock()
        let creds = try source()          // may block on a Keychain prompt; don't hold the lock
        lock.lock(); entry = Entry(creds: creds, loadedAt: now()); lock.unlock()
        return creds.token
    }

    public func invalidate() {
        lock.lock(); entry?.invalidated = true; lock.unlock()
    }
}

// Response shape (verified live 2026-11-07): top-level `five_hour` and `seven_day` are
// {"utilization": <percent 0-100>, "resets_at": "2026-11-07T18:00:00.134955+00:00" | null, "limit_dollars": null, ...}
// (6 fractional digits, +00:00 offset). Many other top-level keys (seven_day_opus, seven_day_sonnet, ...) are null
// and ignored. A top-level `limits` array holds items {"kind": "session"|"weekly_all"|"weekly_scoped", "percent": <0-100>,
// "resets_at": ..., "scope": {"model": {"display_name": "Fable"}}}. `weekly_scoped` items give per-model weekly windows
// (keyed by lowercased display_name); `session`/`weekly_all` duplicate five_hour/seven_day and are used only as a fallback.
// A `seven_day_<name>` dict with `utilization` is kept as a secondary source for per-model windows.
public enum LimitsDecoder {
    public static func decode(_ data: Data, now: Date = Date()) throws -> LimitsSnapshot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LimitsError.badResponse }
        var snap = LimitsSnapshot(fetchedAt: now)
        var legacy: [String: LimitWindow] = [:]
        for (key, value) in obj {
            guard let d = value as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { continue }
            let w = LimitWindow(utilization: u, resetsAt: (d["resets_at"] as? String).flatMap(ISODate.parse))
            if key == "five_hour" { snap.fiveHour = w }
            else if key == "seven_day" { snap.sevenDay = w }
            else if key.hasPrefix("seven_day_") { legacy[String(key.dropFirst("seven_day_".count))] = w }
        }
        var session: LimitWindow?, weeklyAll: LimitWindow?
        for item in (obj["limits"] as? [[String: Any]]) ?? [] {
            guard let p = (item["percent"] as? NSNumber)?.doubleValue else { continue }
            let w = LimitWindow(utilization: p, resetsAt: (item["resets_at"] as? String).flatMap(ISODate.parse))
            switch item["kind"] as? String {
            case "session": session = session ?? w
            case "weekly_all": weeklyAll = weeklyAll ?? w
            case "weekly_scoped":
                if let model = (item["scope"] as? [String: Any])?["model"] as? [String: Any],
                   let name = model["display_name"] as? String, !name.isEmpty {
                    snap.extra[name.lowercased()] = w
                }
            default: break
            }
        }
        if snap.fiveHour == nil { snap.fiveHour = session }
        if snap.sevenDay == nil { snap.sevenDay = weeklyAll }
        for (k, w) in legacy where snap.extra[k] == nil { snap.extra[k] = w }
        guard snap.fiveHour != nil || snap.sevenDay != nil else { throw LimitsError.badResponse }
        snap.extraUsage = parseSpend(obj["spend"])
        return snap
    }
}

extension LimitsDecoder {
    static func parseSpend(_ value: Any?) -> ExtraUsage? {
        guard let spend = value as? [String: Any],
              let used = spend["used"] as? [String: Any],
              let usedMinor = (used["amount_minor"] as? NSNumber)?.intValue else { return nil }
        var limit: Int?
        if let n = spend["limit"] as? NSNumber { limit = n.intValue }
        else if let d = spend["limit"] as? [String: Any] { limit = (d["amount_minor"] as? NSNumber)?.intValue }
        return ExtraUsage(enabled: (spend["enabled"] as? Bool) ?? false, usedMinor: usedMinor, limitMinor: limit,
                          currency: (used["currency"] as? String) ?? "USD",
                          exponent: (used["exponent"] as? NSNumber)?.intValue ?? 2)
    }
}

/// Allows at most one blocking Keychain read at a time, so an unanswered prompt can't pile up threads.
final class KeychainGate: @unchecked Sendable {
    static let shared = KeychainGate()
    private let lock = NSLock()
    private var busy = false
    func tryEnter() -> Bool { lock.lock(); defer { lock.unlock() }; if busy { return false }; busy = true; return true }
    func leave() { lock.lock(); busy = false; lock.unlock() }
}

public struct KeychainTokenProvider: TokenProviding {
    public init() {}
    public func accessToken() throws -> String { try Self.credentials().token }

    /// Reads Claude Code's login. The Keychain item is owned by Claude Code, so a direct read from this app triggers a
    /// password prompt, and Claude Code resets the item's trusted-app list whenever it refreshes its login, which makes
    /// "Always Allow" short-lived. Apple's `security` tool is already trusted by that item (Claude Code writes it with
    /// that tool), so reading through it never prompts. The direct read is only a fallback.
    public static func credentials() throws -> TokenCredentials {
        try credentials(isLocked: defaultKeychainLocked, read: readCredentials)
    }

    private static let interactionLock = NSLock()
    private nonisolated(unsafe) static var _allowUserInteraction = false
    /// True only while a user-initiated refresh runs; background polls must never raise a Keychain dialog.
    public static var allowUserInteraction: Bool {
        get { interactionLock.lock(); defer { interactionLock.unlock() }; return _allowUserInteraction }
        set { interactionLock.lock(); _allowUserInteraction = newValue; interactionLock.unlock() }
    }

    /// Refuses to touch the Keychain (no `security`, no SecItem) when it is locked and interaction isn't allowed.
    static func credentials(isLocked: () -> Bool, allowInteraction: Bool = allowUserInteraction,
                            read: () throws -> TokenCredentials) throws -> TokenCredentials {
        if !allowInteraction && isLocked() { throw LimitsError.keychainLocked }
        return try read()
    }

    /// Whether the default (login) keychain is locked; assumed unlocked when the status can't be read.
    static func defaultKeychainLocked() -> Bool {
        var kc: SecKeychain?
        guard SecKeychainCopyDefault(&kc) == errSecSuccess, let kc else { return false }
        var status: SecKeychainStatus = 0
        guard SecKeychainGetStatus(kc, &status) == errSecSuccess else { return false }
        return status & SecKeychainStatus(kSecUnlockStateStatus) == 0
    }

    private static func readCredentials() throws -> TokenCredentials {
        guard KeychainGate.shared.tryEnter() else { throw LimitsError.keychainBusy }
        defer { KeychainGate.shared.leave() }
        do {
            return try credentialsViaCommand(executable: "/usr/bin/security",
                                             arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 10)
        } catch LimitsError.timeout {
            throw LimitsError.timeout   // a dialog may be showing; a direct read would stack a second one
        } catch {}
        // Test/diagnostic switch: never fall back to the direct (prompting) read.
        if ProcessInfo.processInfo.environment["CLAUDEUSAGE_KEYCHAIN_MODE"] == "tool-only" { throw LimitsError.noToken }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data
        else { throw LimitsError.noToken }
        return try extractCredentials(from: data)
    }

    /// Runs a command that prints the credentials JSON and parses it. Arguments go straight to the process (no shell).
    static func credentialsViaCommand(executable: String, arguments: [String], timeout: TimeInterval) throws -> TokenCredentials {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { throw LimitsError.noToken }
        var data = Data()
        let reader = DispatchQueue(label: "claudeusage.keychain.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); readDone.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            throw LimitsError.timeout
        }
        _ = readDone.wait(timeout: .now() + 2)
        guard p.terminationStatus == 0 else { throw LimitsError.noToken }
        return try extractCredentials(from: data)
    }

    public static func extractCredentials(from data: Data) throws -> TokenCredentials {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LimitsError.noToken }
        let exp = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return TokenCredentials(token: token, expiresAt: exp)
    }
    public static func extractToken(from data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LimitsError.noToken }
        return token
    }
}

public protocol PlanProviding: Sendable { func fetchPlan() async throws -> PlanInfo }

public struct OAuthLimitsClient: LimitsProviding, PlanProviding {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let tokens: TokenProviding
    private let transport: Transport
    private let timeout: TimeInterval

    public init(tokens: TokenProviding = CachingTokenProvider(source: { try KeychainTokenProvider.credentials() }), transport: @escaping Transport = OAuthLimitsClient.live,
                timeout: TimeInterval = 60) {
        self.tokens = tokens; self.transport = transport; self.timeout = timeout
    }

    public static let live: Transport = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LimitsError.badResponse }
        return (data, http)
    }

    public func fetch() async throws -> LimitsSnapshot {
        try await bounded { try await self.get("usage") { try LimitsDecoder.decode($0) } }
    }

    public func fetchPlan() async throws -> PlanInfo {
        try await bounded { try await self.get("profile") { try ProfileDecoder.decode($0, now: Date()) } }
    }

    /// Runs `work`, giving up with `LimitsError.timeout` after `timeout` seconds. The token read (which can
    /// block on a Keychain permission dialog) runs on a global queue, and the race uses continuations so the
    /// timeout can return even while that blocking call is still pending.
    private func bounded<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let seconds = timeout
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = OnceGate()
            let job = Task {
                do {
                    let v = try await work()
                    if once.claim() { cont.resume(returning: v) }
                } catch {
                    if once.claim() { cont.resume(throwing: error) }
                }
            }
            let timer = Task {
                // A cancelled sleep must not be mistaken for a timeout.
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                if once.claim() { cont.resume(throwing: LimitsError.timeout) }
            }
            once.onClaim { job.cancel(); timer.cancel() }
        }
    }

    private func get<T>(_ endpoint: String, decode: (Data) throws -> T) async throws -> T {
        let tokens = self.tokens
        let token: String = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try tokens.accessToken() })
            }
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/\(endpoint)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await transport(req)
        switch resp.statusCode {
        case 200: return try decode(data)
        case 401, 403: tokens.invalidate(); throw LimitsError.unauthorized
        default: throw LimitsError.http(resp.statusCode)
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var cleanup: (@Sendable () -> Void)?
    func claim() -> Bool {
        lock.lock()
        if done { lock.unlock(); return false }
        done = true
        let c = cleanup
        lock.unlock()
        c?()
        return true
    }
    /// Runs `block` when the gate is claimed (immediately if it already was).
    func onClaim(_ block: @escaping @Sendable () -> Void) {
        lock.lock()
        if done { lock.unlock(); block(); return }
        cleanup = block
        lock.unlock()
    }
}
