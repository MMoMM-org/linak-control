// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinakControl",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.3.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "LinakControl",
            dependencies: [],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "deskctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/deskctl"
        ),
        .testTarget(
            name: "LinakControlTests",
            dependencies: [],
            path: "Tests/LinakControlTests"
        )
    ]
)
