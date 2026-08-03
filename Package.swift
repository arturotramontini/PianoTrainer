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
            name: "AudioTCPEngine",
            path: "Sources/AudioTCPExperiment",
            exclude: ["main.swift"],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "AudioTCPExperiment",
            dependencies: ["AudioTCPEngine"],
            path: "Sources/AudioTCPExperiment",
            exclude: ["AudioTCPServer.swift", "SF2SamplerEngine.swift", "AudioSynth.swift", "MIDIManager.swift"],
            sources: ["main.swift"],
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
            dependencies: ["AudioTCPEngine"],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMIDI")
            ]
        )
    ]
)
