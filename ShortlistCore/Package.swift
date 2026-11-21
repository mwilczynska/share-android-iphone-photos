// swift-tools-version: 5.9
import PackageDescription

// Platform-independent logic for the app. Nothing in this package may import
// Apple-only frameworks, so it can be unit-tested with `swift test` on any host.
let package = Package(
    name: "ShortlistCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ShortlistCore", targets: ["ShortlistCore"]),
    ],
    targets: [
        .target(name: "ShortlistCore"),
        .testTarget(name: "ShortlistCoreTests", dependencies: ["ShortlistCore"]),
    ]
)
