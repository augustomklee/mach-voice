// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MachVoice",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MachVoice",
            path: "Sources/MachVoice",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
