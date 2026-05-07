// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgendumMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgendumBackend", targets: ["AgendumBackend"]),
        .library(name: "AgendumFeature", targets: ["AgendumFeature"]),
        .executable(name: "AgendumMac", targets: ["AgendumMac"])
    ],
    targets: [
        .target(
            name: "AgendumBackend"
        ),
        .target(
            name: "AgendumFeature",
            dependencies: ["AgendumBackend"]
        ),
        .executableTarget(
            name: "AgendumMac",
            dependencies: ["AgendumBackend", "AgendumFeature"],
            exclude: ["Info.plist.template"]
        ),
        .testTarget(
            name: "AgendumBackendTests",
            dependencies: ["AgendumBackend"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "AgendumFeatureTests",
            dependencies: ["AgendumFeature"]
        )
    ]
)
