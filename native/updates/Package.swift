// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InboxPlusUpdates",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InboxPlusUpdates", targets: ["InboxPlusUpdates"]),
        .executable(name: "verify-update", targets: ["VerifyUpdate"]),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "InboxPlusUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "VerifyUpdate", dependencies: ["InboxPlusUpdates"]),
        .testTarget(name: "InboxPlusUpdatesTests", dependencies: ["InboxPlusUpdates"]),
    ]
)
