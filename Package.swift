// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pallo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pallo", targets: ["PalloApp"]),
        .library(name: "PalloRuntime", targets: ["PalloRuntime"]),
        .executable(name: "PalloRuntimeCLI", targets: ["PalloRuntimeCLI"]),
    ],
    dependencies: [
        // Pinned exactly: the SDK ships a checksum-verified binary xcframework, and bridge/SDK
        // protocol drift must never arrive silently through a version range.
        .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.08.11"),
    ],
    targets: [
        .target(name: "PalloCore"),
        .target(name: "PalloGateway", dependencies: ["PalloCore"]),
        .target(name: "PalloFeatures", dependencies: ["PalloCore", "PalloGateway", "PalloBridge"]),
        .target(
            name: "PalloUI",
            dependencies: ["PalloCore", "PalloFeatures", "PalloBridge"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PalloApp",
            dependencies: [
                "PalloGateway", "PalloFeatures", "PalloUI", "PalloMatrix", "PalloRuntime",
                "PalloBridge", "PalloBridgeService", "PalloIMessage",
            ]
        ),
        // iMessage does not go through Matrix: it is read from the local Messages database and
        // sent by asking Messages itself. It therefore implements the gateway seam directly.
        .target(
            name: "PalloIMessage",
            dependencies: ["PalloCore", "PalloGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "PalloRuntime"),
        // The bridge contract as pure data: bridgev2 protocol models, the network catalog, and the
        // login state machine. Deliberately dependency-free beyond PalloCore so PalloFeatures and
        // PalloUI can drive a login without importing the runtime or a process supervisor.
        .target(name: "PalloBridge", dependencies: ["PalloCore"]),
        // Everything that talks to a real bridge: provisioning client, installer, configuration,
        // supervision, and the deterministic dummy bridge used as a contract-test fixture.
        .target(name: "PalloBridgeService", dependencies: ["PalloBridge", "PalloCore", "PalloRuntime"]),
        .executableTarget(
            name: "PalloRuntimeCLI",
            dependencies: ["PalloRuntime", "PalloBridge", "PalloBridgeService", "PalloCore"]
        ),
        // The Matrix SDK stays behind this target. PalloFeatures and PalloUI must never import it,
        // so the app layer keeps depending only on the MessagingGateway protocol.
        .target(
            name: "PalloMatrix",
            dependencies: [
                "PalloCore",
                "PalloGateway",
                "PalloRuntime",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
        .testTarget(name: "PalloCoreTests", dependencies: ["PalloCore"]),
        .testTarget(name: "PalloGatewayTests", dependencies: ["PalloCore", "PalloGateway"]),
        .testTarget(
            name: "PalloFeaturesTests",
            dependencies: ["PalloCore", "PalloGateway", "PalloFeatures", "PalloBridge"]
        ),
        .testTarget(
            name: "PalloUITests",
            dependencies: ["PalloCore", "PalloFeatures", "PalloUI", "PalloBridge"]
        ),
        .testTarget(name: "PalloRuntimeTests", dependencies: ["PalloRuntime", "PalloRuntimeCLI"]),
        .testTarget(
            name: "PalloBridgeTests",
            dependencies: ["PalloBridge", "PalloBridgeService", "PalloCore", "PalloRuntime"]
        ),
        .testTarget(
            name: "PalloIMessageTests",
            dependencies: ["PalloIMessage", "PalloCore", "PalloGateway"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PalloMatrixTests",
            dependencies: ["PalloMatrix", "PalloCore", "PalloGateway", "PalloRuntime"]
        ),
    ]
)
