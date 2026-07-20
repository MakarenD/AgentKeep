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
        .target(
            name: "AgentKeepIPC",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "AgentKeepPrivilegedCore",
            dependencies: ["AgentKeepIPC"]
        ),
        .target(
            name: "AgentKeepCore",
            dependencies: ["AgentKeepIPC"]
        ),
        .executableTarget(
            name: "AgentKeep",
            dependencies: ["AgentKeepCore"]
        ),
        .executableTarget(
            name: "AgentKeepPrivilegedHelper",
            dependencies: ["AgentKeepIPC", "AgentKeepPrivilegedCore"]
        ),
        .testTarget(
            name: "AgentKeepCoreTests",
            dependencies: ["AgentKeepCore"]
        ),
        .testTarget(
            name: "AgentKeepPrivilegedCoreTests",
            dependencies: ["AgentKeepIPC", "AgentKeepPrivilegedCore"]
        )
    ]
)
