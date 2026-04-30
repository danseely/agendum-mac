// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgendumMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgendumMacCore", targets: ["AgendumMacCore"]),
        .executable(name: "AgendumMac", targets: ["AgendumMac"])
    ],
    targets: [
        .target(
            name: "AgendumMacCore"
        ),
        .executableTarget(
            name: "AgendumMac",
            dependencies: ["AgendumMacCore"]
        ),
        .testTarget(
            name: "AgendumMacCoreTests",
            dependencies: ["AgendumMacCore"]
        )
    ]
)
