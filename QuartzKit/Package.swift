// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuartzKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "QuartzKit",
            targets: ["QuartzKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", "0.5.0"..<"0.7.0"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "QuartzKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Textual", package: "textual"),
            ],
            path: "Sources/QuartzKit",
            resources: [
                .process("Resources"),
            ],
        ),
        .testTarget(
            name: "QuartzKitTests",
            dependencies: [
                "QuartzKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/QuartzKitTests",
            exclude: [
                "__Snapshots__",
            ]
        ),
    ]
)
