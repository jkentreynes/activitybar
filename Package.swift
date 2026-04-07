// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ActivityBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ActivityBar",
            path: "Sources/ActivityBar"
        )
    ]
)
