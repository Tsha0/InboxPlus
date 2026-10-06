// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InboxPlus",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "InboxPlus", targets: ["InboxPlusApp"]),
        .library(name: "InboxPlusRuntime", targets: ["InboxPlusRuntime"]),
        .executable(name: "InboxPlusRuntimeCLI", targets: ["InboxPlusRuntimeCLI"]),
    ],
    dependencies: [
        // Pinned exactly: the SDK ships a checksum-verified binary xcframework, and bridge/SDK
        // protocol drift must never arrive silently through a version range.
        .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.08.11"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(name: "InboxPlusRuntimeBundler", dependencies: ["InboxPlusRuntime", "InboxPlusBridgeService"]),
        .target(name: "InboxPlusCore"),
        .target(name: "InboxPlusGateway", dependencies: ["InboxPlusCore"]),
        .target(name: "InboxPlusFeatures", dependencies: ["InboxPlusCore", "InboxPlusGateway", "InboxPlusBridge"]),
        .target(
            name: "InboxPlusUI",
            dependencies: ["InboxPlusCore", "InboxPlusFeatures", "InboxPlusBridge"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "InboxPlusApp",
            dependencies: [
                "InboxPlusCore", "InboxPlusGateway", "InboxPlusFeatures", "InboxPlusUI", "InboxPlusMatrix", "InboxPlusRuntime",
                "InboxPlusBridge", "InboxPlusBridgeService", "InboxPlusIMessage",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // iMessage does not go through Matrix: it is read from the local Messages database and
        // sent by asking Messages itself. It therefore implements the gateway seam directly.
        .target(
            name: "InboxPlusIMessage",
            dependencies: ["InboxPlusCore", "InboxPlusGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "InboxPlusRuntime"),
        // The bridge contract as pure data: bridgev2 protocol models, the network catalog, and the
        // login state machine. Deliberately dependency-free beyond InboxPlusCore so InboxPlusFeatures and
        // InboxPlusUI can drive a login without importing the runtime or a process supervisor.
        .target(name: "InboxPlusBridge", dependencies: ["InboxPlusCore"]),
        // Everything that talks to a real bridge: provisioning client, installer, configuration,
        // and supervision.
        .target(
            name: "InboxPlusBridgeService",
            dependencies: ["InboxPlusBridge", "InboxPlusCore", "InboxPlusRuntime"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "InboxPlusRuntimeCLI",
            dependencies: ["InboxPlusRuntime", "InboxPlusBridge", "InboxPlusBridgeService", "InboxPlusCore"]
        ),
        // The Matrix SDK stays behind this target. InboxPlusFeatures and InboxPlusUI must never import it,
        // so the app layer keeps depending only on the MessagingGateway protocol.
        .target(
            name: "InboxPlusMatrix",
            dependencies: [
                "InboxPlusCore",
                "InboxPlusGateway",
                "InboxPlusRuntime",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
        .target(
            name: "InboxPlusTestSupport",
            dependencies: ["InboxPlusCore", "InboxPlusGateway", "InboxPlusFeatures", "InboxPlusBridge", "InboxPlusRuntime"],
            path: "Tests/InboxPlusTestSupport"
        ),
        .testTarget(name: "InboxPlusAppTests", dependencies: ["InboxPlusApp"]),
        .testTarget(name: "InboxPlusCoreTests", dependencies: ["InboxPlusCore"]),
        .testTarget(name: "InboxPlusGatewayTests", dependencies: ["InboxPlusCore", "InboxPlusGateway"]),
        .testTarget(
            name: "InboxPlusFeaturesTests",
            dependencies: ["InboxPlusCore", "InboxPlusGateway", "InboxPlusFeatures", "InboxPlusBridge", "InboxPlusTestSupport"]
        ),
        .testTarget(
            name: "InboxPlusUITests",
            dependencies: ["InboxPlusCore", "InboxPlusFeatures", "InboxPlusUI", "InboxPlusBridge", "InboxPlusTestSupport"]
        ),
        .testTarget(name: "InboxPlusRuntimeTests", dependencies: ["InboxPlusRuntime", "InboxPlusRuntimeCLI"]),
        .testTarget(
            name: "InboxPlusBridgeTests",
            dependencies: ["InboxPlusBridge", "InboxPlusBridgeService", "InboxPlusCore", "InboxPlusRuntime", "InboxPlusTestSupport"]
        ),
        .testTarget(
            name: "InboxPlusIMessageTests",
            dependencies: ["InboxPlusIMessage", "InboxPlusCore", "InboxPlusGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "InboxPlusMatrixTests",
            dependencies: [
                "InboxPlusMatrix", "InboxPlusCore", "InboxPlusGateway", "InboxPlusRuntime",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
    ]
)
