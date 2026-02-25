// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Anvil",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Anvil",
            path: "Sources/Anvil"
        )
    ]
)
