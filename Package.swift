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
        // Test target requires Xcode (XCTest/Testing framework).
        // Uncomment when Xcode is available:
        // .testTarget(
        //     name: "AnvilTests",
        //     dependencies: ["Anvil"],
        //     path: "Tests/AnvilTests"
        // ),
    ]
)
