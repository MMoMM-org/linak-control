// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinakControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Expose the shared library so Xcode projects can link against it
        .library(name: "LinakControlKit", targets: ["LinakControlKit"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.3.0"
        )
    ],
    targets: [
        // Shared library — all BLE, Core, Config, IPC, Util logic
        .target(
            name: "LinakControlKit",
            dependencies: [],
            path: "Sources/LinakControlKit"
        ),
        // Menu bar app — thin @main entry point
        .executableTarget(
            name: "LinakControl",
            dependencies: ["LinakControlKit"],
            path: "Sources/App"
        ),
        // CLI tool
        .executableTarget(
            name: "deskctl",
            dependencies: [
                "LinakControlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/deskctl"
        ),
        // Tests
        .testTarget(
            name: "LinakControlTests",
            dependencies: ["LinakControlKit"],
            path: "Tests/LinakControlTests"
        )
    ]
)
