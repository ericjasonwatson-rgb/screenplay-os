// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CreativeIPShieldMacScaffold",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShieldNativeContract", targets: ["ShieldNativeContract"]),
        .library(name: "ShieldMacXPCInterfaces", targets: ["ShieldMacXPCInterfaces"]),
        .executable(name: "ShieldMacService", targets: ["ShieldMacService"]),
        .executable(name: "ShieldXPCProbeServer", targets: ["ShieldXPCProbeServer"]),
        .executable(name: "ShieldXPCProbeClient", targets: ["ShieldXPCProbeClient"])
    ],
    targets: [
        .target(name: "ShieldNativeContract"),
        .target(name: "ShieldMacXPCInterfaces"),
        .executableTarget(name: "ShieldMacService", dependencies: ["ShieldNativeContract", "ShieldMacXPCInterfaces"]),
        .executableTarget(name: "ShieldXPCProbeServer", dependencies: ["ShieldMacXPCInterfaces"]),
        .executableTarget(name: "ShieldXPCProbeClient", dependencies: ["ShieldMacXPCInterfaces"]),
        .testTarget(name: "ShieldNativeContractTests", dependencies: ["ShieldNativeContract"])
    ]
)
