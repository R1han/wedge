// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wedge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WedgeCore", targets: ["WedgeCore"]),
    ],
    targets: [
        .target(name: "WedgeCore"),
        .testTarget(name: "WedgeCoreTests", dependencies: ["WedgeCore"]),
    ]
)
