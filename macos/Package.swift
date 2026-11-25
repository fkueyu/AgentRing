// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentRing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentRing", targets: ["AgentRing"]),
    ],
    targets: [
        .executableTarget(
            name: "AgentRing",
            path: "Sources/AgentRing"
        ),
    ]
)
