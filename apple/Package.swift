// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VBANAppleShared",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "VBANAppleShared",
            targets: ["VBANAppleShared"]
        ),
    ],
    targets: [
        .target(
            name: "VBANAppleShared"
        ),
        .testTarget(
            name: "VBANAppleSharedTests",
            dependencies: ["VBANAppleShared"]
        ),
    ]
)
