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
        .library(name: "AgendumGitHub", targets: ["AgendumGitHub"]),
        .library(name: "AgendumMacStore", targets: ["AgendumMacStore"]),
        .library(name: "AgendumSync", targets: ["AgendumSync"]),
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
            name: "AgendumGitHub"
        ),
        .target(
            name: "AgendumMacStore",
            dependencies: [
                "AgendumFeature",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "AgendumSync",
            dependencies: [
                "AgendumFeature",
                "AgendumGitHub",
                "AgendumMacStore"
            ]
        ),
        .executableTarget(
            name: "AgendumMac",
            dependencies: ["AgendumBackend", "AgendumFeature", "AgendumMacStore"],
            exclude: ["Info.plist.template"]
        ),
        .testTarget(
            name: "AgendumBackendTests",
            dependencies: ["AgendumBackend"]
        ),
        .testTarget(
            name: "AgendumFeatureTests",
            dependencies: ["AgendumFeature"]
        ),
        .testTarget(
            name: "AgendumGitHubTests",
            dependencies: ["AgendumGitHub"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "AgendumMacStoreTests",
            dependencies: [
                "AgendumMacStore",
                "AgendumFeature",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "AgendumSyncTests",
            dependencies: [
                "AgendumSync",
                "AgendumFeature",
                "AgendumGitHub",
                "AgendumMacStore"
            ]
        )
    ]
)
