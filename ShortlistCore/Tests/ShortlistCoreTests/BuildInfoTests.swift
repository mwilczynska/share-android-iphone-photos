import XCTest
@testable import ShortlistCore

final class BuildInfoTests: XCTestCase {
    func testDecodesJSONWrittenByCI() throws {
        let json = #"{"channel":"test","commit":"0123456789abcdef0123456789abcdef01234567","branch":"feature/review-grid"}"#

        let info = try XCTUnwrap(BuildInfo(jsonData: Data(json.utf8)))

        XCTAssertEqual(info.channel, "test")
        XCTAssertEqual(info.commit, "0123456789abcdef0123456789abcdef01234567")
        XCTAssertEqual(info.branch, "feature/review-grid")
        XCTAssertEqual(info.shortCommit, "0123456")
    }

    func testDecodesCommittedLocalDefault() throws {
        let json = """
        {
          "channel": "local",
          "commit": "",
          "branch": ""
        }
        """

        let info = try XCTUnwrap(BuildInfo(jsonData: Data(json.utf8)))

        XCTAssertEqual(info, .local)
        XCTAssertEqual(info.shortCommit, "")
    }

    func testReturnsNilWhenAKeyIsMissing() {
        let json = #"{"channel":"test","commit":"abc"}"#

        XCTAssertNil(BuildInfo(jsonData: Data(json.utf8)))
    }

    func testReturnsNilForNonJSON() {
        XCTAssertNil(BuildInfo(jsonData: Data("not json".utf8)))
        XCTAssertNil(BuildInfo(jsonData: Data()))
    }

    func testShortCommitHandlesShortInput() {
        XCTAssertEqual(BuildInfo(channel: "test", commit: "abc", branch: "x").shortCommit, "abc")
    }
}
