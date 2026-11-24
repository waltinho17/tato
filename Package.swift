// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "touchbar-temp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "touchbar-temp",
            path: "Sources/touchbar-temp"
        )
    ]
)
