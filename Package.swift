// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgendumMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgendumMacCore", targets: ["AgendumMacCore"]),
        .library(name: "AgendumMacWorkflow", targets: ["AgendumMacWorkflow"]),
        .executable(name: "AgendumMac", targets: ["AgendumMac"])
    ],
    targets: [
        .target(
            name: "AgendumMacCore"
        ),
        .target(
            name: "AgendumMacWorkflow",
            dependencies: ["AgendumMacCore"]
        ),
        .executableTarget(
            name: "AgendumMac",
            dependencies: ["AgendumMacCore", "AgendumMacWorkflow"],
            exclude: ["Info.plist.template"]
        ),
        .testTarget(
            name: "AgendumMacCoreTests",
            dependencies: ["AgendumMacCore"]
        ),
        .testTarget(
            name: "AgendumMacWorkflowTests",
            dependencies: ["AgendumMacWorkflow"]
        )
    ]
)
