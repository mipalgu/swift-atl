// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-atl",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ATL",
            targets: ["ATL"]
        ),
        .executable(
            name: "swift-atl",
            targets: ["swift-atl"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/swiftxml/SwiftXML.git", from: "1.0.0"),
        .package(url: "https://github.com/mipalgu/swift-ecore.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "ATL",
            dependencies: [
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "swift-atl",
            dependencies: [
                "ATL",
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ATLTests",
            dependencies: [
                "ATL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
