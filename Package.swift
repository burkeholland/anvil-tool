// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Anvil",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Anvil",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Anvil"
        ),
        // Tests use XCTest — requires Xcode (not just Command Line Tools).
        // Run with: xcodebuild test -scheme Anvil -destination 'platform=macOS'
        .testTarget(
            name: "AnvilTests",
            dependencies: ["Anvil"],
            path: "Tests/AnvilTests"
        ),
    ]
)
