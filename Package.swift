// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MachVoice",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "MachVoiceKit",
            path: "Sources/MachVoiceKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MachVoice",
            dependencies: ["MachVoiceKit"],
            path: "Sources/MachVoice",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MachVoiceKitTests",
            dependencies: ["MachVoiceKit"],
            path: "Tests/MachVoiceKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
