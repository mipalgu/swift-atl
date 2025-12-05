// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ecore",
    platforms: [
        .macOS(.v15),
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
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0"),
        .package(url: "https://github.com/swiftxml/SwiftXML.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ECore",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "SwiftXML", package: "SwiftXML"),
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
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)