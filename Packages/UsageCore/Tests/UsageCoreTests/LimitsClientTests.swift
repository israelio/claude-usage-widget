import XCTest
@testable import UsageCore

final class LimitsClientTests: XCTestCase {
    let sample = """
    {"five_hour":{"utilization":42.0,"resets_at":"2026-11-07T18:20:00.123Z"},
     "seven_day":{"utilization":71.5,"resets_at":"2026-11-11T18:00:00Z"},
     "seven_day_fable":{"utilization":78,"resets_at":null},
     "extra_usage":{"is_enabled":false}}
    """

    func testDecode() throws {
        let now = Date()
        let s = try LimitsDecoder.decode(Data(sample.utf8), now: now)
        XCTAssertEqual(s.fiveHour?.utilization, 42)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertEqual(s.sevenDay?.utilization, 71.5)
        XCTAssertEqual(s.extra["fable"]?.utilization, 78)
        XCTAssertNil(s.extra["fable"]?.resetsAt)
        XCTAssertEqual(s.weeklyModel?.name, "fable")
        XCTAssertFalse(s.isEstimated)
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
        XCTAssertEqual(s.fiveHour?.utilization, 42)
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
