import Foundation

/// The parts of an app's embedded provisioning profile that the app needs in
/// order to warn before its signature lapses.
///
/// A sideloaded app carries `embedded.mobileprovision` in its bundle. The file
/// is a signed container wrapped around an XML property list, so the plist is
/// located by its textual markers instead of decoding the container.
public struct ProvisioningProfile: Equatable, Sendable {
    public let creationDate: Date?
    public let expirationDate: Date

    public init(creationDate: Date?, expirationDate: Date) {
        self.creationDate = creationDate
        self.expirationDate = expirationDate
    }

    /// Returns nil when the data holds no property list or no expiry date.
    public init?(data: Data) {
        guard
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard
            let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
            let dictionary = object as? [String: Any],
            let expiry = dictionary["ExpirationDate"] as? Date
        else { return nil }

        self.creationDate = dictionary["CreationDate"] as? Date
        self.expirationDate = expiry
    }

    /// Whole days until the signature lapses, rounded down. Negative once expired.
    public func daysRemaining(from now: Date = Date()) -> Int {
        Int((expirationDate.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        expirationDate <= now
    }
}
