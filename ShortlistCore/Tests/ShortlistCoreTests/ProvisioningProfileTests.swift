import XCTest
@testable import ShortlistCore

final class ProvisioningProfileTests: XCTestCase {
    private let day: TimeInterval = 86_400

    /// Builds bytes shaped like a real profile: binary container bytes, the XML
    /// plist, then more binary bytes. All values are synthetic.
    private func makeProfileData(plistBody: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(plistBody)
        </dict>
        </plist>
        """
        var data = Data([0x30, 0x82, 0x1F, 0x00, 0xFF, 0x00, 0x06, 0x09])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x82, 0x0D, 0x00, 0xFE, 0x31, 0x00]))
        return data
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testReadsDatesFromWrappedPlist() throws {
        let data = makeProfileData(plistBody: """
        <key>CreationDate</key><date>2026-11-21T10:00:00Z</date>
        <key>ExpirationDate</key><date>2026-11-28T10:00:00Z</date>
        <key>Name</key><string>Synthetic profile</string>
        """)

        let profile = try XCTUnwrap(ProvisioningProfile(data: data))

        XCTAssertEqual(profile.creationDate, date("2026-11-21T10:00:00Z"))
        XCTAssertEqual(profile.expirationDate, date("2026-11-28T10:00:00Z"))
    }

    func testCreationDateIsOptional() throws {
        let data = makeProfileData(plistBody: """
        <key>ExpirationDate</key><date>2026-11-28T10:00:00Z</date>
        """)

        let profile = try XCTUnwrap(ProvisioningProfile(data: data))

        XCTAssertNil(profile.creationDate)
    }

    func testReturnsNilWithoutExpirationDate() {
        let data = makeProfileData(plistBody: """
        <key>Name</key><string>Synthetic profile</string>
        """)

        XCTAssertNil(ProvisioningProfile(data: data))
    }

    func testReturnsNilForDataWithoutPlist() {
        XCTAssertNil(ProvisioningProfile(data: Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(ProvisioningProfile(data: Data()))
    }

    func testReturnsNilForTruncatedPlist() {
        let data = Data("<?xml version=\"1.0\"?><plist><dict><key>ExpirationDate</key>".utf8)

        XCTAssertNil(ProvisioningProfile(data: data))
    }

    func testDaysRemainingRoundsDown() {
        let expiry = date("2026-11-28T10:00:00Z")
        let profile = ProvisioningProfile(creationDate: nil, expirationDate: expiry)

        XCTAssertEqual(profile.daysRemaining(from: expiry.addingTimeInterval(-7 * day)), 7)
        XCTAssertEqual(profile.daysRemaining(from: expiry.addingTimeInterval(-7 * day + 1)), 6)
        XCTAssertEqual(profile.daysRemaining(from: expiry.addingTimeInterval(-1)), 0)
    }

    func testDaysRemainingIsNegativeAfterExpiry() {
        let expiry = date("2026-11-28T10:00:00Z")
        let profile = ProvisioningProfile(creationDate: nil, expirationDate: expiry)

        XCTAssertEqual(profile.daysRemaining(from: expiry.addingTimeInterval(1)), -1)
        XCTAssertEqual(profile.daysRemaining(from: expiry.addingTimeInterval(2 * day)), -2)
    }

    func testIsExpired() {
        let expiry = date("2026-11-28T10:00:00Z")
        let profile = ProvisioningProfile(creationDate: nil, expirationDate: expiry)

        XCTAssertFalse(profile.isExpired(at: expiry.addingTimeInterval(-1)))
        XCTAssertTrue(profile.isExpired(at: expiry))
        XCTAssertTrue(profile.isExpired(at: expiry.addingTimeInterval(1)))
    }
}
