// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentKeep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AgentKeep", targets: ["AgentKeep"])
    ],
    targets: [
        .target(name: "AgentKeepCore"),
        .executableTarget(
            name: "AgentKeep",
            dependencies: ["AgentKeepCore"]
        ),
        .testTarget(
            name: "AgentKeepCoreTests",
            dependencies: ["AgentKeepCore"]
        )
    ]
)
