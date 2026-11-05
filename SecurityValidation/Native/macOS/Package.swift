// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CreativeIPShieldMacScaffold",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShieldNativeContract", targets: ["ShieldNativeContract"]),
        .library(name: "ShieldMacXPCInterfaces", targets: ["ShieldMacXPCInterfaces"]),
        .executable(name: "ShieldMacService", targets: ["ShieldMacService"])
    ],
    targets: [
        .target(name: "ShieldNativeContract"),
        .target(name: "ShieldMacXPCInterfaces"),
        .executableTarget(name: "ShieldMacService", dependencies: ["ShieldNativeContract", "ShieldMacXPCInterfaces"]),
        .testTarget(name: "ShieldNativeContractTests", dependencies: ["ShieldNativeContract"])
    ]
)
