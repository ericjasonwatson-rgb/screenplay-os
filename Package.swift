// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenplayOSStarter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ScreenplayDomain", targets: ["ScreenplayDomain"]),
        .library(name: "ScreenplayFDX", targets: ["ScreenplayFDX"]),
        .executable(name: "ScreenplayOS", targets: ["ScreenplayOSApp"]),
        .executable(name: "screenplay-inspect", targets: ["screenplay-inspect"]),
        .executable(name: "screenplay-license-tool", targets: ["screenplay-license-tool"])
    ],
    targets: [
        .testTarget(
            name: "ScreenplayEditorTests",
            dependencies: ["ScreenplayOSApp", "ScreenplayDomain", "ScreenplayFDX"]
        ),
        .target(name: "ScreenplayDomain", resources: [.copy("Resources/pricing.json")]),
        .target(
            name: "ScreenplayFDX",
            dependencies: ["ScreenplayDomain"]
        ),
        .executableTarget(
            name: "screenplay-inspect",
            dependencies: ["ScreenplayDomain", "ScreenplayFDX"]
        ),
        .executableTarget(
            name: "ScreenplayOSApp",
            dependencies: ["ScreenplayDomain", "ScreenplayFDX"],
            exclude: ["Resources/ScreenplayOSLogo.png"],
            resources: [
                .copy("Resources/ScreenplayOSAppIcon.png"),
                .copy("Resources/ScreenplayOS.icns")
            ]
        ),
        .executableTarget(
            name: "screenplay-self-test",
            dependencies: ["ScreenplayDomain", "ScreenplayFDX"],
            path: "Tests/ScreenplaySelfTest"
        ),
        .executableTarget(name: "screenplay-license-tool", dependencies: ["ScreenplayDomain"], path: "Scripts/LicenseTool")
    ]
)
