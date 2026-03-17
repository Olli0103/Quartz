// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuartzKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "QuartzKit",
            targets: ["QuartzKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", "0.5.0"..<"0.7.0"),
    ],
    targets: [
        .target(
            name: "QuartzKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/QuartzKit",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "QuartzKitTests",
            dependencies: ["QuartzKit"],
            path: "Tests/QuartzKitTests"
        ),
    ]
)
