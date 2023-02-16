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
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket.git", from: "7.6.5")
    ],
    targets: [
        .target(name: "SwiftSSDP", dependencies: ["CocoaAsyncSocket"])
    ]
)
