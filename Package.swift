// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cachi",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/Subito-it/CachiKit", branch: "master"),
        .package(url: "https://github.com/Subito-it/Bariloche", branch: "master"),
        .package(url: "https://github.com/tcamin/Vaux", branch: "cachi"),
        .package(url: "https://github.com/michaeleisel/ZippyJSON", branch: "master"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.77.1")
    ],
    targets: [
        .executableTarget(
            name: "Cachi",
            dependencies: ["CachiKit", "Bariloche", "Vaux", "ZippyJSON", .product(name: "Vapor", package: "vapor")]
        ),
        .testTarget(
            name: "CachiTests",
            dependencies: ["Cachi"]
        )
    ]
)
