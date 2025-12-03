// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ecore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ECore",
            targets: ["ECore"]
        ),
        .executable(
            name: "swift-ecore",
            targets: ["swift-ecore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
    ],
    targets: [
        .target(
            name: "ECore",
            dependencies: [
                .product(name: "BigInt", package: "BigInt"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "swift-ecore",
            dependencies: [
                "ECore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ECoreTests",
            dependencies: ["ECore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)