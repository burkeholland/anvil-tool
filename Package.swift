// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Anvil",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Anvil",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr"),
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
