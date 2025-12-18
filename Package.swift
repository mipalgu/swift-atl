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
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/mipalgu/swift-ecore", branch: "main"),
    ],
    targets: [
        .target(
            name: "ATL",
            dependencies: [
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "EMFBase", package: "swift-ecore"),
                .product(name: "OCL", package: "swift-ecore"),
                .product(name: "OrderedCollections", package: "swift-collections"),
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
