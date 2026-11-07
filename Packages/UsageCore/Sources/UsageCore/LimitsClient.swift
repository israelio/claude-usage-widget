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

// Response shape (verified in Task 6 Step 1): top-level keys five_hour, seven_day, seven_day_<model>,
// each {"utilization": <percent>, "resets_at": <ISO8601|null>}. Other keys are ignored.
public enum LimitsDecoder {
    public static func decode(_ data: Data, now: Date = Date()) throws -> LimitsSnapshot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LimitsError.badResponse }
        var snap = LimitsSnapshot(fetchedAt: now)
        for (key, value) in obj {
            guard let d = value as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { continue }
            let w = LimitWindow(utilization: u, resetsAt: (d["resets_at"] as? String).flatMap(ISODate.parse))
            if key == "five_hour" { snap.fiveHour = w }
            else if key == "seven_day" { snap.sevenDay = w }
            else if key.hasPrefix("seven_day_") { snap.extra[String(key.dropFirst("seven_day_".count))] = w }
        }
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
