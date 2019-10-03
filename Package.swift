// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cachi",
    platforms: [
       .macOS(.v10_13)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/tcamin/CachiKit", .branch("master")),
        .package(url: "https://github.com/Subito-it/Bariloche", .branch("master")),
        .package(url: "https://github.com/vapor/http.git", .branch("master")),
        .package(url: "https://github.com/tcamin/Vaux", .branch("cachi")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Cachi",
            dependencies: ["HTTPKit", "CachiKit", "Bariloche", "Vaux"]),
        .testTarget(
            name: "CachiTests",
            dependencies: ["Cachi"]),
    ]
)
