// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cachi",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/Subito-it/CachiKit", branch: "master"),
        .package(url: "https://github.com/Subito-it/Bariloche", branch: "master"),
        .package(url: "https://github.com/tcamin/http.git", branch: "master"),
        .package(url: "https://github.com/tcamin/Vaux", branch: "cachi"),
        .package(url: "https://github.com/michaeleisel/ZippyJSON", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Cachi",
            dependencies: [.product(name: "HTTPKit", package: "http"), "CachiKit", "Bariloche", "Vaux", "ZippyJSON"]
        ),
        .testTarget(
            name: "CachiTests",
            dependencies: ["Cachi"]
        ),
    ]
)
