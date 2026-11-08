import XCTest
@testable import UsageCore

final class CachingTokenProviderTests: XCTestCase {
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000_000) }
    final class Source: @unchecked Sendable {
        var reads = 0
        var expiresIn: TimeInterval? = 8 * 3600
        let clock: Clock
        init(_ c: Clock) { clock = c }
        func read() throws -> TokenCredentials {
            reads += 1
            return TokenCredentials(token: "tok\(reads)", expiresAt: expiresIn.map { clock.now.addingTimeInterval($0) })
        }
    }
    func make(_ s: Source, _ c: Clock) -> CachingTokenProvider {
        CachingTokenProvider(source: { try s.read() }, now: { c.now }, skew: 60, minReload: 120)
    }

    func testReadsKeychainOnceAcrossManyCalls() throws {
        let c = Clock(), s = Source(c), p = make(s, c)
        for _ in 0..<20 { XCTAssertEqual(try p.accessToken(), "tok1"); c.now += 300 }
        XCTAssertEqual(s.reads, 1)
    }
    func testReloadsAfterExpiry() throws {
        let c = Clock(), s = Source(c), p = make(s, c)
        _ = try p.accessToken()
        c.now += 8 * 3600 - 30            // inside the 60s skew
        XCTAssertEqual(try p.accessToken(), "tok2")
        XCTAssertEqual(s.reads, 2)
    }
    func testInvalidateReloadsButThrottled() throws {
        let c = Clock(), s = Source(c), p = make(s, c)
        _ = try p.accessToken()
        p.invalidate()
        c.now += 30
        XCTAssertEqual(try p.accessToken(), "tok1")   // within minReload: no keychain read
        XCTAssertEqual(s.reads, 1)
        c.now += 200
        XCTAssertEqual(try p.accessToken(), "tok2")
        XCTAssertEqual(s.reads, 2)
    }
    func testAlreadyExpiredTokenDoesNotHammerKeychain() throws {
        let c = Clock(), s = Source(c); s.expiresIn = -10
        let p = make(s, c)
        _ = try p.accessToken()
        for _ in 0..<5 { c.now += 20; _ = try p.accessToken() }
        XCTAssertEqual(s.reads, 1)
    }
    func testNoExpiryCachedUntilInvalidated() throws {
        let c = Clock(), s = Source(c); s.expiresIn = nil
        let p = make(s, c)
        _ = try p.accessToken(); c.now += 86_400
        XCTAssertEqual(try p.accessToken(), "tok1")
        XCTAssertEqual(s.reads, 1)
    }
    func testExtractCredentialsParsesExpiryMillis() throws {
        let blob = Data(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":1800000000000}}"#.utf8)
        let cred = try KeychainTokenProvider.extractCredentials(from: blob)
        XCTAssertEqual(cred.token, "t")
        XCTAssertEqual(cred.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
    }
    func testClientInvalidatesTokenOn401() async {
        final class Tokens: TokenProviding, @unchecked Sendable {
            var invalidated = 0
            func accessToken() throws -> String { "T" }
            func invalidate() { invalidated += 1 }
        }
        let t = Tokens()
        let client = OAuthLimitsClient(tokens: t) { req in
            (Data("{}".utf8), HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await client.fetch(); XCTFail() } catch { XCTAssertEqual(error as? LimitsError, .unauthorized) }
        XCTAssertEqual(t.invalidated, 1)
    }
}

final class SecurityToolReaderTests: XCTestCase {
    let json = #"{"claudeAiOauth":{"accessToken":"tokCLI","expiresAt":1800000000000}}"#

    func testParsesCredentialsFromCommandOutput() throws {
        let c = try KeychainTokenProvider.credentialsViaCommand(executable: "/bin/echo", arguments: [json], timeout: 5)
        XCTAssertEqual(c.token, "tokCLI")
        XCTAssertEqual(c.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
    }
    func testNonZeroExitIsNoToken() {
        XCTAssertThrowsError(try KeychainTokenProvider.credentialsViaCommand(executable: "/usr/bin/false", arguments: [], timeout: 5)) {
            XCTAssertEqual($0 as? LimitsError, .noToken)
        }
    }
    func testGarbageOutputIsNoToken() {
        XCTAssertThrowsError(try KeychainTokenProvider.credentialsViaCommand(executable: "/bin/echo", arguments: ["not json"], timeout: 5)) {
            XCTAssertEqual($0 as? LimitsError, .noToken)
        }
    }
    func testHangingCommandTimesOut() {
        let start = Date()
        XCTAssertThrowsError(try KeychainTokenProvider.credentialsViaCommand(executable: "/bin/sleep", arguments: ["5"], timeout: 0.4)) {
            XCTAssertEqual($0 as? LimitsError, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
