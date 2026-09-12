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
        .executable(name: "screenplay-inspect", targets: ["screenplay-inspect"])
    ],
    targets: [
        .target(name: "ScreenplayDomain"),
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
            dependencies: ["ScreenplayDomain", "ScreenplayFDX"]
        ),
        .executableTarget(
            name: "screenplay-self-test",
            dependencies: ["ScreenplayDomain", "ScreenplayFDX"],
            path: "Tests/ScreenplaySelfTest"
        )
    ]
)
