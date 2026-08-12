// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pallo",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Pallo", targets: ["PalloApp"])],
    targets: [
        .target(name: "PalloCore"),
        .target(name: "PalloGateway", dependencies: ["PalloCore"]),
        .target(name: "PalloFeatures", dependencies: ["PalloCore", "PalloGateway"]),
        .target(name: "PalloUI", dependencies: ["PalloCore", "PalloFeatures"]),
        .executableTarget(name: "PalloApp", dependencies: ["PalloGateway", "PalloFeatures", "PalloUI"]),
        .testTarget(name: "PalloCoreTests", dependencies: ["PalloCore"]),
        .testTarget(name: "PalloGatewayTests", dependencies: ["PalloCore", "PalloGateway"]),
    ]
)
