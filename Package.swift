// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgendumMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgendumMac", targets: ["AgendumMac"])
    ],
    targets: [
        .executableTarget(
            name: "AgendumMac"
        )
    ]
)
