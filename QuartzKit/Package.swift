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
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "QuartzKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/QuartzKit"
        ),
        .testTarget(
            name: "QuartzKitTests",
            dependencies: ["QuartzKit"],
            path: "Tests/QuartzKitTests"
        ),
    ]
)
