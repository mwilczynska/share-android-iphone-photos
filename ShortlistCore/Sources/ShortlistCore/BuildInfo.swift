import Foundation

/// Identifies which build is installed, so a test build can be told apart from a
/// build of `main`. CI writes these values into `BuildInfo.json` in the app bundle;
/// the committed copy of that file describes a local build.
public struct BuildInfo: Codable, Equatable, Sendable {
    /// "latest" for builds of the main branch, "test" for work in progress, "local" otherwise.
    public let channel: String
    /// Full commit hash, or empty for a local build.
    public let commit: String
    public let branch: String

    public static let local = BuildInfo(channel: "local", commit: "", branch: "")

    public init(channel: String, commit: String, branch: String) {
        self.channel = channel
        self.commit = commit
        self.branch = branch
    }

    /// Returns nil when the data is not the expected JSON object.
    public init?(jsonData: Data) {
        guard let decoded = try? JSONDecoder().decode(BuildInfo.self, from: jsonData) else { return nil }
        self = decoded
    }

    /// The first seven characters of the commit hash, as shown by git.
    public var shortCommit: String {
        String(commit.prefix(7))
    }
}
