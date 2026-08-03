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
        .target(
            name: "CAudioEngine",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "AudioTCPExperiment",
            dependencies: ["CAudioEngine"],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMIDI"),
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
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMIDI")
            ]
        )
    ]
)
