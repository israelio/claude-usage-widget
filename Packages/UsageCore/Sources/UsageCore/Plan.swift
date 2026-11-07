import Foundation

public struct PlanInfo: Codable, Equatable, Sendable {
    public var planName: String
    public var status: String
    public var billingType: String
    public var subscriptionStart: Date?
    public var nextRenewal: Date?
    /// Renewal is inferred from the subscription start, never reported by the API.
    public var isRenewalEstimated: Bool
    public init(planName: String, status: String, billingType: String, subscriptionStart: Date? = nil,
                nextRenewal: Date? = nil, isRenewalEstimated: Bool = true) {
        self.planName = planName; self.status = status; self.billingType = billingType
        self.subscriptionStart = subscriptionStart; self.nextRenewal = nextRenewal
        self.isRenewalEstimated = isRenewalEstimated
    }
}

public enum Billing {
    /// First monthly anniversary of `start` that is strictly after `now` (day-of-month kept, clamped for short months).
    public static func nextRenewal(start: Date, now: Date, calendar: Calendar = .current) -> Date? {
        for n in 1...2400 {
            // Always offset from `start` so a clamped month (Feb 28) doesn't drag later months down.
            guard let d = calendar.date(byAdding: .month, value: n, to: start) else { return nil }
            if d > now { return d }
        }
        return nil
    }
}

public enum ProfileDecoder {
    public static func decode(_ data: Data, now: Date = Date()) throws -> PlanInfo {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let org = obj["organization"] as? [String: Any] else { throw LimitsError.badResponse }
        let type = (org["organization_type"] as? String) ?? ""
        let tier = (org["rate_limit_tier"] as? String) ?? ""
        let name: String
        switch type {
        case "claude_max":
            name = tier.contains("max_20x") ? "Max 20x" : tier.contains("max_5x") ? "Max 5x" : "Max"
        case "claude_pro": name = "Pro"
        case "claude_team": name = "Team"
        case "claude_enterprise": name = "Enterprise"
        default:
            let t = type.hasPrefix("claude_") ? String(type.dropFirst("claude_".count)) : type
            name = t.isEmpty ? "Unknown" : pretty(t)
        }
        let rawStatus = (org["subscription_status"] as? String) ?? ""
        let status = rawStatus == "active" ? "Active" : (rawStatus.isEmpty ? "Unknown" : pretty(rawStatus))
        let billing = (org["billing_type"] as? String) ?? ""
        let start = (org["subscription_created_at"] as? String).flatMap(ISODate.parse)
        var renewal: Date?
        if billing == "stripe_subscription", let s = start {
            renewal = Billing.nextRenewal(start: s, now: now, calendar: .current)
        }
        return PlanInfo(planName: name, status: status, billingType: billing, subscriptionStart: start, nextRenewal: renewal)
    }

    private static func pretty(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "_", with: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

public struct ExtraUsage: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var usedMinor: Int
    public var limitMinor: Int?
    public var currency: String
    public var exponent: Int
    public init(enabled: Bool, usedMinor: Int, limitMinor: Int? = nil, currency: String = "USD", exponent: Int = 2) {
        self.enabled = enabled; self.usedMinor = usedMinor; self.limitMinor = limitMinor
        self.currency = currency; self.exponent = exponent
    }
    private func scale(_ m: Int) -> Double { Double(m) / pow(10, Double(exponent)) }
    public var usedAmount: Double { scale(usedMinor) }
    public var limitAmount: Double? { limitMinor.map(scale) }
}
