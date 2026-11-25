// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentRingCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentRingCore", targets: ["AgentRingCore"]),
    ],
    targets: [
        .target(name: "AgentRingCore", path: "Sources/AgentRingCore"),
        .testTarget(
            name: "AgentRingCoreTests",
            dependencies: ["AgentRingCore"],
            path: "Tests/AgentRingCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
