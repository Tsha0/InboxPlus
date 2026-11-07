// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InboxPlusIMessage",
    platforms: [.macOS(.v15)],
    products: [.library(name: "InboxPlusIMessage", targets: ["InboxPlusIMessage"])],
    targets: [
        .target(name: "InboxPlusIMessage", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "InboxPlusIMessageTests", dependencies: ["InboxPlusIMessage"]),
    ]
)
