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
    ],
    targets: [
        .executableTarget(
            name: "WhisperFree",
            dependencies: [
            ],
            path: "Sources/WhisperFree",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
