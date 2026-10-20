// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Automnt",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AutomntCore", targets: ["AutomntCore"]),
        .library(name: "AutomntCLI", targets: ["AutomntCLI"]),
        .library(name: "AutomntPlatform", targets: ["AutomntPlatform"])
    ],
    targets: [
        .target(name: "AutomntCore"),
        .target(name: "AutomntPlatform", dependencies: ["AutomntCore"]),
        .target(name: "AutomntCLI", dependencies: ["AutomntCore"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AutomntCoreTests", dependencies: ["AutomntCore"]),
        .testTarget(name: "AutomntCLITests", dependencies: ["AutomntCLI", "AutomntCore"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AutomntPlatformTests", dependencies: ["AutomntPlatform"])
    ]
)
