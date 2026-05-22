// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sounda",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SoundaCore",
            targets: ["SoundaCore"]
        ),
        .executable(
            name: "SoundaApp",
            targets: ["SoundaApp"]
        ),
        .executable(
            name: "SoundaCoreSmokeTests",
            targets: ["SoundaCoreSmokeTests"]
        ),
    ],
    targets: [
        .target(
            name: "SoundaCore"
        ),
        .executableTarget(
            name: "SoundaApp",
            dependencies: ["SoundaCore"]
        ),
        .executableTarget(
            name: "SoundaCoreSmokeTests",
            dependencies: ["SoundaCore"]
        ),
        .testTarget(
            name: "SoundaCoreTests",
            dependencies: ["SoundaCore"]
        ),
    ]
)
