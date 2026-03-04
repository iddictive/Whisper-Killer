// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperFree",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperFree", targets: ["WhisperFree"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperFree",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/WhisperFree",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
