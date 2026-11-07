import XCTest
@testable import UsageCore

final class PlanTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func date(_ s: String) -> Date { ISODate.parse(s)! }

    func testRenewalNextMonth() {
        let r = Billing.nextRenewal(start: date("2026-03-07T11:43:58Z"), now: date("2026-11-08T10:00:00Z"), calendar: cal)
        XCTAssertEqual(r, date("2026-12-07T11:43:58Z"))
    }
    func testRenewalOnAnniversaryBeforeTime() {
        let r = Billing.nextRenewal(start: date("2026-03-07T11:43:58Z"), now: date("2026-11-07T09:00:00Z"), calendar: cal)
        XCTAssertEqual(r, date("2026-11-07T11:43:58Z"))
    }
    func testRenewalAfterTimeOnAnniversaryRollsOver() {
        let r = Billing.nextRenewal(start: date("2026-03-07T11:43:58Z"), now: date("2026-11-07T12:00:00Z"), calendar: cal)
        XCTAssertEqual(r, date("2026-12-07T11:43:58Z"))
    }
    func testRenewalClampsShortMonths() {
        let start = date("2026-01-31T08:00:00Z")
        XCTAssertEqual(Billing.nextRenewal(start: start, now: date("2026-02-01T00:00:00Z"), calendar: cal), date("2026-02-28T08:00:00Z"))
        XCTAssertEqual(Billing.nextRenewal(start: start, now: date("2026-03-01T00:00:00Z"), calendar: cal), date("2026-03-31T08:00:00Z"))
    }
    func testRenewalFutureStart() {
        let start = date("2027-01-10T00:00:00Z")
        XCTAssertEqual(Billing.nextRenewal(start: start, now: date("2026-11-08T00:00:00Z"), calendar: cal), date("2027-02-10T00:00:00Z"))
    }

    func profile(type: String, tier: String = "default", status: String = "active", billing: String = "stripe_subscription") -> Data {
        Data(#"{"account":{"has_claude_max":true},"organization":{"organization_type":"\#(type)","billing_type":"\#(billing)","rate_limit_tier":"\#(tier)","seat_tier":null,"has_extra_usage_enabled":false,"subscription_status":"\#(status)","subscription_created_at":"2026-03-07T11:43:58.126791Z"}}"#.utf8)
    }
    func testMax5x() throws {
        let p = try ProfileDecoder.decode(profile(type: "claude_max", tier: "default_claude_max_5x"), now: date("2026-11-08T10:00:00Z"))
        XCTAssertEqual(p.planName, "Max 5x")
        XCTAssertEqual(p.status, "Active")
        XCTAssertEqual(p.billingType, "stripe_subscription")
        XCTAssertNotNil(p.subscriptionStart)
        XCTAssertNotNil(p.nextRenewal)
        XCTAssertTrue(p.isRenewalEstimated)
    }
    func testMax20xAndPlainMax() throws {
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_max", tier: "default_claude_max_20x")).planName, "Max 20x")
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_max")).planName, "Max")
    }
    func testOtherTypes() throws {
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_pro")).planName, "Pro")
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_team")).planName, "Team")
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_enterprise")).planName, "Enterprise")
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_edu_plus")).planName, "Edu plus")
    }
    func testStatusPrettified() throws {
        XCTAssertEqual(try ProfileDecoder.decode(profile(type: "claude_pro", status: "past_due")).status, "Past due")
    }
    func testNonStripeHasNoRenewal() throws {
        let p = try ProfileDecoder.decode(profile(type: "claude_pro", billing: "apple_subscription"))
        XCTAssertNil(p.nextRenewal)
        XCTAssertNotNil(p.subscriptionStart)
    }
    func testNoOrganizationThrows() {
        XCTAssertThrowsError(try ProfileDecoder.decode(Data(#"{"account":{}}"#.utf8))) { XCTAssertEqual($0 as? LimitsError, .badResponse) }
    }

    func testPlanClient() async throws {
        struct T: TokenProviding { func accessToken() throws -> String { "T" } }
        let body = profile(type: "claude_max", tier: "default_claude_max_5x")
        let c = OAuthLimitsClient(tokens: T()) { req in
            XCTAssertEqual(req.url?.path, "/api/oauth/profile")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer T")
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            return (body, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let p = try await c.fetchPlan()
        XCTAssertEqual(p.planName, "Max 5x")
    }
    func testPlanClient401InvalidatesToken() async {
        final class T: TokenProviding, @unchecked Sendable {
            var invalidated = false
            func accessToken() throws -> String { "T" }
            func invalidate() { invalidated = true }
        }
        let t = T()
        let c = OAuthLimitsClient(tokens: t) { req in
            (Data(), HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await c.fetchPlan(); XCTFail() } catch { XCTAssertEqual(error as? LimitsError, .unauthorized) }
        XCTAssertTrue(t.invalidated)
    }
    func testPlanClientTimeout() async {
        struct B: TokenProviding { func accessToken() throws -> String { Thread.sleep(forTimeInterval: 3); return "t" } }
        let c = OAuthLimitsClient(tokens: B(), transport: { _ in throw LimitsError.badResponse }, timeout: 0.2)
        do { _ = try await c.fetchPlan(); XCTFail() } catch { XCTAssertEqual(error as? LimitsError, .timeout) }
    }

    // Spend parsing
    func decodeSpend(_ spend: String) throws -> LimitsSnapshot {
        try LimitsDecoder.decode(Data(#"{"five_hour":{"utilization":1},"spend":\#(spend)}"#.utf8))
    }
    func testSpendReal() throws {
        let s = try decodeSpend(#"{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":false}"#)
        XCTAssertEqual(s.extraUsage, ExtraUsage(enabled: false, usedMinor: 0, limitMinor: nil, currency: "USD", exponent: 2))
    }
    func testSpendWithLimits() throws {
        var s = try decodeSpend(#"{"used":{"amount_minor":1234,"currency":"USD","exponent":2},"limit":5000,"enabled":true}"#)
        XCTAssertEqual(s.extraUsage?.usedAmount ?? 0, 12.34, accuracy: 0.0001)
        XCTAssertEqual(s.extraUsage?.limitMinor, 5000)
        s = try decodeSpend(#"{"used":{"amount_minor":1234,"currency":"USD","exponent":2},"limit":{"amount_minor":7500,"currency":"USD","exponent":2},"enabled":true}"#)
        XCTAssertEqual(s.extraUsage?.limitMinor, 7500)
        XCTAssertEqual(s.extraUsage?.limitAmount ?? 0, 75, accuracy: 0.0001)
    }
    func testNoSpendAndOldSnapshotDecode() throws {
        XCTAssertNil(try LimitsDecoder.decode(Data(#"{"five_hour":{"utilization":1}}"#.utf8)).extraUsage)
        let old = #"{"fetchedAt":0,"extra":{},"isEstimated":false}"#
        let s = try JSONDecoder().decode(LimitsSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(s.extraUsage)
    }
}
