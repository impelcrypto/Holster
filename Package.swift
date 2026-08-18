// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "holster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Holster", targets: ["Holster"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "HolsterKit",
            dependencies: [
                "KeyboardShortcuts",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                "Yams",
            ],
            resources: [.copy("Resources/examples")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Holster",
            dependencies: ["HolsterKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HolsterKitTests",
            dependencies: ["HolsterKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
