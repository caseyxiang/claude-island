// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeIsland",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeIsland",
            path: "ClaudeIsland",
            exclude: [
                "Info.plist",
                "ClaudeIsland.entitlements"
            ],
            resources: [
                .copy("Resources/hooks"),
                .process("Assets.xcassets")
            ]
        )
    ]
)
