// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mimo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Mimo", targets: ["MimoApp"]),
        .library(name: "MimoRuntime", targets: ["MimoRuntime"]),
        .executable(name: "MimoRuntimeCLI", targets: ["MimoRuntimeCLI"]),
    ],
    dependencies: [
        // Pinned exactly: the SDK ships a checksum-verified binary xcframework, and bridge/SDK
        // protocol drift must never arrive silently through a version range.
        .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.08.11"),
    ],
    targets: [
        .target(name: "MimoCore"),
        .target(name: "MimoGateway", dependencies: ["MimoCore"]),
        .target(name: "MimoFeatures", dependencies: ["MimoCore", "MimoGateway", "MimoBridge"]),
        .target(
            name: "MimoUI",
            dependencies: ["MimoCore", "MimoFeatures", "MimoBridge"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MimoApp",
            dependencies: [
                "MimoGateway", "MimoFeatures", "MimoUI", "MimoMatrix", "MimoRuntime",
                "MimoBridge", "MimoBridgeService", "MimoIMessage",
            ]
        ),
        // iMessage does not go through Matrix: it is read from the local Messages database and
        // sent by asking Messages itself. It therefore implements the gateway seam directly.
        .target(
            name: "MimoIMessage",
            dependencies: ["MimoCore", "MimoGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "MimoRuntime"),
        // The bridge contract as pure data: bridgev2 protocol models, the network catalog, and the
        // login state machine. Deliberately dependency-free beyond MimoCore so MimoFeatures and
        // MimoUI can drive a login without importing the runtime or a process supervisor.
        .target(name: "MimoBridge", dependencies: ["MimoCore"]),
        // Everything that talks to a real bridge: provisioning client, installer, configuration,
        // supervision, and the deterministic dummy bridge used as a contract-test fixture.
        .target(name: "MimoBridgeService", dependencies: ["MimoBridge", "MimoCore", "MimoRuntime"]),
        .executableTarget(
            name: "MimoRuntimeCLI",
            dependencies: ["MimoRuntime", "MimoBridge", "MimoBridgeService", "MimoCore"]
        ),
        // The Matrix SDK stays behind this target. MimoFeatures and MimoUI must never import it,
        // so the app layer keeps depending only on the MessagingGateway protocol.
        .target(
            name: "MimoMatrix",
            dependencies: [
                "MimoCore",
                "MimoGateway",
                "MimoRuntime",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
        .testTarget(name: "MimoCoreTests", dependencies: ["MimoCore"]),
        .testTarget(name: "MimoGatewayTests", dependencies: ["MimoCore", "MimoGateway"]),
        .testTarget(
            name: "MimoFeaturesTests",
            dependencies: ["MimoCore", "MimoGateway", "MimoFeatures", "MimoBridge"]
        ),
        .testTarget(
            name: "MimoUITests",
            dependencies: ["MimoCore", "MimoFeatures", "MimoUI", "MimoBridge"]
        ),
        .testTarget(name: "MimoRuntimeTests", dependencies: ["MimoRuntime", "MimoRuntimeCLI"]),
        .testTarget(
            name: "MimoBridgeTests",
            dependencies: ["MimoBridge", "MimoBridgeService", "MimoCore", "MimoRuntime"]
        ),
        .testTarget(
            name: "MimoIMessageTests",
            dependencies: ["MimoIMessage", "MimoCore", "MimoGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MimoMatrixTests",
            dependencies: ["MimoMatrix", "MimoCore", "MimoGateway", "MimoRuntime"]
        ),
    ]
)
