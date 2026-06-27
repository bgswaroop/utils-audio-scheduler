// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "utils-audio-scheduler",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "utils-audio-scheduler", targets: ["frontend"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "frontend",
            dependencies: [],
            path: "Sources/frontend"
        )
    ]
)
