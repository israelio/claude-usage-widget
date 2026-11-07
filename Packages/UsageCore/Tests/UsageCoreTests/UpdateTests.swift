import XCTest
@testable import UsageCore

final class UpdateTests: XCTestCase {
    func testVersionParse() {
        XCTAssertEqual(AppVersion("0.1.4"), AppVersion("v0.1.4"))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x.2"))
        XCTAssertNil(AppVersion(""))
        XCTAssertEqual(AppVersion("0.1.5-beta.1")?.prerelease, "beta.1")
    }
    func testVersionOrder() {
        XCTAssertTrue(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
        XCTAssertTrue(AppVersion("0.1.5-beta.1")! < AppVersion("0.1.5")!)
        XCTAssertTrue(AppVersion("0.1.5-beta.1")! > AppVersion("0.1.4")!)
        XCTAssertTrue(AppVersion("1.0.0")! > AppVersion("0.9.9")!)
        XCTAssertTrue(AppVersion("0.1.5-beta.2")! < AppVersion("0.1.5-beta.10")!)
    }

    private func json(tag: String, draft: Bool = false, pre: Bool = false, assets: String? = nil) -> Data {
        let a = assets ?? """
        [{"name":"ClaudeUsage-9.9.9.dmg","browser_download_url":"https://example.com/a.dmg","size":1},
         {"name":"ClaudeUsage-9.9.9.dmg.sha256","browser_download_url":"https://example.com/a.sha256","size":1}]
        """
        return Data("""
        {"tag_name":"\(tag)","name":"x","body":"notes","html_url":"https://example.com/r","draft":\(draft),"prerelease":\(pre),"assets":\(a)}
        """.utf8)
    }
    private func checker(_ cur: String, status: Int = 200, data: Data) -> UpdateChecker {
        UpdateChecker(currentVersion: cur) { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testNewer() async throws {
        let i = try await checker("0.1.4", data: json(tag: "v9.9.9")).check()
        XCTAssertEqual(i?.version, "9.9.9")
        XCTAssertEqual(i?.dmgURL.absoluteString, "https://example.com/a.dmg")
        XCTAssertEqual(i?.sha256URL?.absoluteString, "https://example.com/a.sha256")
        XCTAssertEqual(i?.notes, "notes")
    }
    func testUpToDateAndOlder() async throws {
        let a = try await checker("9.9.9", data: json(tag: "v9.9.9")).check()
        XCTAssertNil(a)
        let b = try await checker("10.0.0", data: json(tag: "v9.9.9")).check()
        XCTAssertNil(b)
    }
    func testDraftPrereleaseIgnored() async throws {
        let a = try await checker("0.1.4", data: json(tag: "v9.9.9", draft: true)).check()
        XCTAssertNil(a)
        let b = try await checker("0.1.4", data: json(tag: "v9.9.9", pre: true)).check()
        XCTAssertNil(b)
    }
    func testNoDMG() async {
        do { _ = try await checker("0.1.4", data: json(tag: "v9.9.9", assets: "[]")).check(); XCTFail() }
        catch { XCTAssertEqual(error as? UpdateError, .noDMGAsset) }
    }
    func testHTTPErrors() async {
        for code in [403, 429, 500] {
            do { _ = try await checker("0.1.4", status: code, data: Data()).check(); XCTFail() }
            catch { XCTAssertEqual(error as? UpdateError, .http(code)) }
        }
    }
    func testMissingShaIsNil() async throws {
        let a = #"[{"name":"x.dmg","browser_download_url":"https://example.com/a.dmg"}]"#
        let i = try await checker("0.1.4", data: json(tag: "v9.9.9", assets: a)).check()
        XCTAssertNil(i?.sha256URL)
    }

    func testChecksumParse() {
        let h = String(repeating: "AB", count: 32)
        XCTAssertEqual(Checksum.parse("\(h)  ClaudeUsage-1.dmg\n"), h.lowercased())
        XCTAssertNil(Checksum.parse("abc  f"))
        XCTAssertNil(Checksum.parse(""))
        XCTAssertNil(Checksum.parse(String(repeating: "z", count: 64)))
    }
    func testSHA256File() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: u)
        defer { try? FileManager.default.removeItem(at: u) }
        XCTAssertEqual(try Checksum.sha256(of: u),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testScript() {
        let s = UpdateScript.make(pid: 42, newApp: "/tmp/a b/New.app", destApp: "/Apps/Bob's Claude.app")
        XCTAssertTrue(s.contains("'/tmp/a b/New.app'"))
        XCTAssertTrue(s.contains("'/Apps/Bob'\\''s Claude.app'"))
        for k in ["PID=42", "kill -0", "ditto", "$DEST.old", "xattr -dr com.apple.quarantine", "open \"$DEST\"", "mv \"$OLD\" \"$DEST\""] {
            XCTAssertTrue(s.contains(k), k)
        }
    }
}
