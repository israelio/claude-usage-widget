import Foundation
import Security

public enum LimitsError: Error, Equatable, LocalizedError {
    case noToken, unauthorized, http(Int), badResponse, timeout, keychainBusy
    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Claude Code login found in Keychain"
        case .unauthorized: return "Login expired — run Claude Code to sign in again"
        case .http(let c): return "Usage API error (HTTP \(c))"
        case .badResponse: return "Unexpected usage API response"
        case .timeout: return "Timed out waiting for Keychain/usage API"
        case .keychainBusy: return "Waiting for Keychain access — approve the prompt"
        }
    }
}

public protocol LimitsProviding: Sendable { func fetch() async throws -> LimitsSnapshot }
public protocol TokenProviding: Sendable { func accessToken() throws -> String }

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
        return snap
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
    public func accessToken() throws -> String {
        guard KeychainGate.shared.tryEnter() else { throw LimitsError.keychainBusy }
        defer { KeychainGate.shared.leave() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data
        else { throw LimitsError.noToken }
        return try Self.extractToken(from: data)
    }
    public static func extractToken(from data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LimitsError.noToken }
        return token
    }
}

public struct OAuthLimitsClient: LimitsProviding {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let tokens: TokenProviding
    private let transport: Transport
    private let timeout: TimeInterval

    public init(tokens: TokenProviding = KeychainTokenProvider(), transport: @escaping Transport = OAuthLimitsClient.live,
                timeout: TimeInterval = 60) {
        self.tokens = tokens; self.transport = transport; self.timeout = timeout
    }

    public static let live: Transport = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LimitsError.badResponse }
        return (data, http)
    }

    /// Fetches limits, giving up with `LimitsError.timeout` after `timeout` seconds. The token read (which can
    /// block on a Keychain permission dialog) runs on a global queue, and the race uses continuations so the
    /// timeout can return even while that blocking call is still pending.
    public func fetch() async throws -> LimitsSnapshot {
        let seconds = timeout
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LimitsSnapshot, Error>) in
            let once = OnceGate()
            let work = Task {
                do {
                    let snap = try await self.fetchUnbounded()
                    if once.claim() { cont.resume(returning: snap) }
                } catch {
                    if once.claim() { cont.resume(throwing: error) }
                }
            }
            let timer = Task {
                // A cancelled sleep must not be mistaken for a timeout.
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                if once.claim() { cont.resume(throwing: LimitsError.timeout) }
            }
            once.onClaim { work.cancel(); timer.cancel() }
        }
    }

    private func fetchUnbounded() async throws -> LimitsSnapshot {
        let tokens = self.tokens
        let token: String = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try tokens.accessToken() })
            }
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await transport(req)
        switch resp.statusCode {
        case 200: return try LimitsDecoder.decode(data)
        case 401, 403: throw LimitsError.unauthorized
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
