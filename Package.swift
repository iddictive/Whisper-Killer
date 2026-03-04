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
    targets: [
        .executableTarget(
            name: "WhisperFree",
            path: "Sources/WhisperFree",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
