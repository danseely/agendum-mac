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
        .library(name: "AgendumMacStore", targets: ["AgendumMacStore"]),
        .executable(name: "AgendumMac", targets: ["AgendumMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "AgendumBackend"
        ),
        .target(
            name: "AgendumFeature",
            dependencies: ["AgendumBackend"]
        ),
        .target(
            name: "AgendumMacStore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
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
        ),
        .testTarget(
            name: "AgendumMacStoreTests",
            dependencies: [
                "AgendumMacStore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
