// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentsElements",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentsElements",
            path: "Sources/AgentsElements"
        )
    ]
)
