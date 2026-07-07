// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModelChanges",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ModelChanges",
            path: "Sources/ModelChanges",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
