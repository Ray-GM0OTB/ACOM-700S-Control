// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ACOMControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ACOMControl",
            path: "Sources/ACOMControl"
        )
    ]
)
