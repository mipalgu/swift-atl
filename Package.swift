// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ecore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftEcore",
            targets: ["SwiftEcore"]
        ),
        .executable(
            name: "swift-ecore",
            targets: ["swift-ecore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SwiftEcore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "swift-ecore",
            dependencies: [
                "SwiftEcore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftEcoreTests",
            dependencies: ["SwiftEcore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
