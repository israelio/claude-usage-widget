import Foundation
import Security

public enum LimitsError: Error, Equatable, LocalizedError {
    case noToken, unauthorized, http(Int), badResponse
    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Claude Code login found in Keychain"
        case .unauthorized: return "Login expired — run Claude Code to sign in again"
        case .http(let c): return "Usage API error (HTTP \(c))"
        case .badResponse: return "Unexpected usage API response"
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

public struct KeychainTokenProvider: TokenProviding {
    public init() {}
    public func accessToken() throws -> String {
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

    public init(tokens: TokenProviding = KeychainTokenProvider(), transport: @escaping Transport = OAuthLimitsClient.live) {
        self.tokens = tokens; self.transport = transport
    }

    public static let live: Transport = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LimitsError.badResponse }
        return (data, http)
    }

    public func fetch() async throws -> LimitsSnapshot {
        let token = try tokens.accessToken()
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
