import XCTest
@testable import UsageCore

final class LimitsClientTests: XCTestCase {
    let sample = """
    {"five_hour":{"utilization":43.0,"resets_at":"2026-11-07T18:00:00.134955+00:00","limit_dollars":null},
     "seven_day":{"utilization":21.0,"resets_at":"2026-11-12T14:00:00.134955+00:00","limit_dollars":null},
     "seven_day_opus":null,
     "seven_day_sonnet":null,
     "limits":[
       {"kind":"session","group":"session","percent":43,"severity":"normal","resets_at":"2026-11-07T18:00:00+00:00","scope":null,"is_active":true},
       {"kind":"weekly_all","group":"weekly","percent":21,"severity":"normal","resets_at":"2026-11-12T14:00:00+00:00","scope":null,"is_active":true},
       {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":"2026-11-12T14:00:00+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false},
       {"kind":"weekly_scoped","group":"weekly","percent":5,"severity":"normal","resets_at":null,"scope":{"model":{"id":null,"display_name":null},"surface":null},"is_active":false}
     ],
     "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null}}
    """

    func testDecode() throws {
        let now = Date()
        let s = try LimitsDecoder.decode(Data(sample.utf8), now: now)
        XCTAssertEqual(s.fiveHour?.utilization, 43)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertEqual(s.sevenDay?.utilization, 21)
        XCTAssertEqual(s.extra["fable"]?.utilization, 0)
        XCTAssertNotNil(s.extra["fable"]?.resetsAt)
        XCTAssertEqual(s.extra.count, 1)
        XCTAssertEqual(s.weeklyModel?.name, "fable")
        XCTAssertFalse(s.isEstimated)
    }
    func testDecodeFallsBackToLimitsArray() throws {
        let json = #"{"limits":[{"kind":"session","percent":10,"resets_at":"2026-11-07T18:00:00+00:00"},{"kind":"weekly_all","percent":20,"resets_at":null}]}"#
        let s = try LimitsDecoder.decode(Data(json.utf8))
        XCTAssertEqual(s.fiveHour?.utilization, 10)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertEqual(s.sevenDay?.utilization, 20)
    }
    func testDecodeLegacyPrefixKey() throws {
        let json = #"{"five_hour":{"utilization":1},"seven_day_fable":{"utilization":78,"resets_at":null}}"#
        let s = try LimitsDecoder.decode(Data(json.utf8))
        XCTAssertEqual(s.extra["fable"]?.utilization, 78)
    }
    func testISODateFormats() {
        XCTAssertNotNil(ISODate.parse("2026-11-07T18:00:00.134955+00:00"))
        XCTAssertNotNil(ISODate.parse("2026-11-07T18:00:00+00:00"))
        XCTAssertNotNil(ISODate.parse("2026-11-07T18:20:00.123Z"))
        XCTAssertNotNil(ISODate.parse("2026-11-11T18:00:00Z"))
        XCTAssertEqual(ISODate.parse("2026-11-07T18:00:00.134955+00:00")!.timeIntervalSince1970,
                       ISODate.parse("2026-11-07T18:00:00Z")!.timeIntervalSince1970, accuracy: 1)
    }
    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try LimitsDecoder.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try LimitsDecoder.decode(Data(#"{"foo":1}"#.utf8)))
    }
    func testExtractToken() throws {
        let blob = Data(#"{"claudeAiOauth":{"accessToken":"tok123","expiresAt":1}}"#.utf8)
        XCTAssertEqual(try KeychainTokenProvider.extractToken(from: blob), "tok123")
        XCTAssertThrowsError(try KeychainTokenProvider.extractToken(from: Data("{}".utf8)))
    }

    struct FakeTokens: TokenProviding { func accessToken() throws -> String { "T" } }
    func client(status: Int, body: String) -> OAuthLimitsClient {
        OAuthLimitsClient(tokens: FakeTokens()) { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer T")
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }
    }
    func testFetchOK() async throws {
        let s = try await client(status: 200, body: sample).fetch()
        XCTAssertEqual(s.fiveHour?.utilization, 43)
    }
    func testFetch401() async {
        do { _ = try await client(status: 401, body: "{}").fetch(); XCTFail() }
        catch { XCTAssertEqual(error as? LimitsError, .unauthorized) }
    }
    func testFetch500() async {
        do { _ = try await client(status: 500, body: "{}").fetch(); XCTFail() }
        catch { XCTAssertEqual(error as? LimitsError, .http(500)) }
    }
}

final class LimitsTimeoutTests: XCTestCase {
    struct BlockingTokens: TokenProviding {
        func accessToken() throws -> String { Thread.sleep(forTimeInterval: 5); return "t" }
    }
    func testFetchTimesOutWhileTokenReadBlocks() async {
        let c = OAuthLimitsClient(tokens: BlockingTokens(), transport: { _ in throw LimitsError.badResponse }, timeout: 0.3)
        let start = Date()
        do { _ = try await c.fetch(); XCTFail("expected timeout") }
        catch { XCTAssertEqual(error as? LimitsError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(LimitsError.timeout.errorDescription, "Timed out waiting for Keychain/usage API")
    }
}

final class KeychainGateTests: XCTestCase {
    func testOnlyOneEntrant() {
        let g = KeychainGate()
        XCTAssertTrue(g.tryEnter())
        XCTAssertFalse(g.tryEnter())
        g.leave()
        XCTAssertTrue(g.tryEnter())
    }
    func testSuccessDoesNotLeaveTimerFiring() async throws {
        struct T: TokenProviding { func accessToken() throws -> String { "T" } }
        let c = OAuthLimitsClient(tokens: T(), transport: { req in
            (Data(#"{"five_hour":{"utilization":1,"resets_at":null}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, timeout: 0.2)
        let s = try await c.fetch()
        XCTAssertEqual(s.fiveHour?.utilization, 1)
        try await Task.sleep(nanoseconds: 400_000_000)
    }
}
