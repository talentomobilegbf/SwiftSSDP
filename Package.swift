// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "SwiftSSDP",
    platforms: [
        .macOS(.v10_14), .iOS(.v12), .watchOS(.v5)
    ],
    products: [
        .library(name: "SwiftSSDP", targets: ["SwiftSSDP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.48.0")
    ],
    targets: [
        .testTarget(name: "SwiftSSDPTests", dependencies: ["SwiftSSDP"]),
        .target(name: "SwiftSSDP", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIO", package: "swift-nio")])
    ]
)
