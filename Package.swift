// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Claudometer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Claudometer",
            path: "Sources/Claudometer"
        )
    ]
)
