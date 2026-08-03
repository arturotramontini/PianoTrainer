// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AudioTCPExperiment",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AudioTCPExperiment", targets: ["AudioTCPExperiment"]),
        .executable(name: "AudioTCPClient", targets: ["AudioTCPClient"]),
        .executable(name: "AudioTCPGUIClient", targets: ["AudioTCPGUIClient"])
    ],
    targets: [
        .executableTarget(
            name: "AudioTCPExperiment",
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "AudioTCPClient",
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "AudioTCPGUIClient",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
