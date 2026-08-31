// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BridgeMindOne",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BridgeMindOne",
            targets: ["App"]
        ),
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .library(
            name: "UI",
            targets: ["UI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core"
        ),
        .target(
            name: "UI",
            dependencies: ["Core"],
            path: "Sources/UI"
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "UI"
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        )
    ]
)
