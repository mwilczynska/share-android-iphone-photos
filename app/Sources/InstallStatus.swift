import Foundation
import ShortlistCore

/// Counts launches in UserDefaults. If these values survive a 7-day refresh and an
/// app update, the sideloading tool is keeping the app's data container.
enum LaunchLog {
    private static let firstOpenedKey = "launchLog.firstOpened"
    private static let openCountKey = "launchLog.openCount"

    static func recordLaunch(defaults: UserDefaults = .standard, now: Date = Date()) {
        if defaults.object(forKey: firstOpenedKey) == nil {
            defaults.set(now, forKey: firstOpenedKey)
        }
        defaults.set(defaults.integer(forKey: openCountKey) + 1, forKey: openCountKey)
    }

    static func firstOpened(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: firstOpenedKey) as? Date
    }

    static func openCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: openCountKey)
    }
}

/// Everything the Phase 0 status screen shows. Read fresh each time the app
/// becomes active, because a refresh replaces the provisioning profile.
struct InstallStatus {
    let profile: ProvisioningProfile?
    let build: BuildInfo
    let firstOpened: Date?
    let openCount: Int
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let systemVersion: String

    static func current(bundle: Bundle = .main) -> InstallStatus {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return InstallStatus(
            profile: embeddedProfile(in: bundle),
            build: buildInfo(in: bundle),
            firstOpened: LaunchLog.firstOpened(),
            openCount: LaunchLog.openCount(),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            bundleIdentifier: bundle.bundleIdentifier ?? "?",
            systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }

    /// Falls back to the local description if the bundled file is missing or malformed.
    private static func buildInfo(in bundle: Bundle) -> BuildInfo {
        guard
            let url = bundle.url(forResource: "BuildInfo", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let info = BuildInfo(jsonData: data)
        else { return .local }
        return info
    }

    /// Absent in the Simulator and in unsigned builds.
    private static func embeddedProfile(in bundle: Bundle) -> ProvisioningProfile? {
        guard
            let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return ProvisioningProfile(data: data)
    }
}
