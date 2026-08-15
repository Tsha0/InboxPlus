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
        .target(name: "PalloFeatures", dependencies: ["PalloCore", "PalloGateway"]),
        .target(name: "PalloUI", dependencies: ["PalloCore", "PalloFeatures"]),
        .executableTarget(
            name: "PalloApp",
            dependencies: ["PalloGateway", "PalloFeatures", "PalloUI", "PalloMatrix", "PalloRuntime"]
        ),
        .target(name: "PalloRuntime"),
        // The bridge contract: bridgev2 provisioning models, a client, and a deterministic dummy
        // bridge that scripts each network's real login flow for tests.
        .target(name: "PalloBridge", dependencies: ["PalloCore", "PalloRuntime"]),
        .executableTarget(name: "PalloRuntimeCLI", dependencies: ["PalloRuntime"]),
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
        .testTarget(name: "PalloFeaturesTests", dependencies: ["PalloCore", "PalloGateway", "PalloFeatures"]),
        .testTarget(name: "PalloUITests", dependencies: ["PalloCore", "PalloFeatures", "PalloUI"]),
        .testTarget(name: "PalloRuntimeTests", dependencies: ["PalloRuntime", "PalloRuntimeCLI"]),
        .testTarget(name: "PalloBridgeTests", dependencies: ["PalloBridge", "PalloRuntime"]),
        .testTarget(
            name: "PalloMatrixTests",
            dependencies: ["PalloMatrix", "PalloCore", "PalloGateway", "PalloRuntime"]
        ),
    ]
)
