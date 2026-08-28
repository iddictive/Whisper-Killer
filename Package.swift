// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKiller",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperKiller", targets: ["WhisperKiller"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")
    ],
    targets: [
        .executableTarget(
            name: "WhisperKiller",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/WhisperFree",
            exclude: [
                "Resources"
            ]
        ),
        .testTarget(
            name: "WhisperKillerTests",
            dependencies: ["WhisperKiller"]
        )
    ]
)
