// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrainAtlas",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BrainAtlas",
            path: "Sources/BrainAtlas",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
