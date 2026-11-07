import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double
    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

public struct PriceTable: Codable, Equatable, Sendable {
    /// USD per million tokens, keyed by model family substring.
    public var byFamily: [String: ModelPrice]
    public init(byFamily: [String: ModelPrice]) { self.byFamily = byFamily }

    public static let defaults = PriceTable(byFamily: [
        "opus":   ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50),
        "sonnet": ModelPrice(input: 3,  output: 15, cacheWrite: 3.75,  cacheRead: 0.30),
        "haiku":  ModelPrice(input: 1,  output: 5,  cacheWrite: 1.25,  cacheRead: 0.10),
        "fable":  ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50),
    ])

    public func price(for model: String) -> ModelPrice? {
        let m = model.lowercased()
        for key in byFamily.keys.sorted() where m.contains(key) { return byFamily[key] }
        return nil
    }

    public func cost(model: String, tokens: TokenCounts) -> Double {
        guard let p = price(for: model) else { return 0 }
        return (Double(tokens.input) * p.input + Double(tokens.output) * p.output
              + Double(tokens.cacheWrite) * p.cacheWrite + Double(tokens.cacheRead) * p.cacheRead) / 1_000_000
    }

    public static func displayName(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
    }
}
