// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WASVPS",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WASVPS",
            targets: ["WASVPS"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(
            name: "WASVPS",
            path: "WASVPS.xcframework"
        ),
    ]
)
