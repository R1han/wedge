// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wedge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WedgeCore", targets: ["WedgeCore"]),
        .executable(name: "wedge", targets: ["wedge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "WedgeCore"),
        .target(
            name: "WedgeCLI",
            dependencies: [
                "WedgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .executableTarget(name: "wedge", dependencies: ["WedgeCLI"]),
        .testTarget(name: "WedgeCLITests", dependencies: ["WedgeCLI", "WedgeCore"]),
        .testTarget(name: "WedgeCoreTests", dependencies: ["WedgeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
