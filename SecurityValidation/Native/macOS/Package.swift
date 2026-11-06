// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CreativeIPShieldMacScaffold",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShieldNativeContract", targets: ["ShieldNativeContract"]),
        .library(name: "ShieldMacXPCInterfaces", targets: ["ShieldMacXPCInterfaces"]),
        .library(name: "ShieldReviewerKeychain", targets: ["ShieldReviewerKeychain"]),
        .library(name: "ShieldApprovalContract", targets: ["ShieldApprovalContract"]),
        .library(name: "ShieldApprovalVerification", targets: ["ShieldApprovalVerification"]),
        .library(name: "ShieldDurableApproval", targets: ["ShieldDurableApproval"]),
        .library(name: "ShieldReviewerReview", targets: ["ShieldReviewerReview"]),
        .executable(name: "ShieldMacService", targets: ["ShieldMacService"]),
        .executable(name: "ShieldXPCProbeServer", targets: ["ShieldXPCProbeServer"]),
        .executable(name: "ShieldXPCProbeClient", targets: ["ShieldXPCProbeClient"]),
        .executable(name: "ShieldDurableApprovalFixture", targets: ["ShieldDurableApprovalFixture"]),
        .executable(name: "ShieldReviewerDemoApp", targets: ["ShieldReviewerDemoApp"])
    ],
    targets: [
        .target(name: "ShieldNativeContract"),
        .target(name: "ShieldMacXPCInterfaces"),
        .target(name: "ShieldReviewerKeychain", dependencies: ["ShieldNativeContract"]),
        .target(name: "ShieldApprovalContract"),
        .target(name: "ShieldApprovalVerification", dependencies: ["ShieldApprovalContract"]),
        .target(name: "ShieldDurableApproval", dependencies: ["ShieldApprovalContract", "ShieldApprovalVerification"]),
        .target(name: "ShieldReviewerReview", dependencies: ["ShieldApprovalContract"]),
        .executableTarget(name: "ShieldMacService", dependencies: ["ShieldNativeContract", "ShieldMacXPCInterfaces"]),
        .executableTarget(name: "ShieldXPCProbeServer", dependencies: ["ShieldMacXPCInterfaces"]),
        .executableTarget(name: "ShieldXPCProbeClient", dependencies: ["ShieldMacXPCInterfaces"]),
        .executableTarget(name: "ShieldDurableApprovalFixture", dependencies: ["ShieldDurableApproval", "ShieldApprovalContract", "ShieldApprovalVerification"]),
        .executableTarget(name: "ShieldReviewerDemoApp", dependencies: ["ShieldReviewerReview", "ShieldApprovalContract"]),
        .testTarget(name: "ShieldNativeContractTests", dependencies: ["ShieldNativeContract"]),
        .testTarget(name: "ShieldReviewerKeychainTests", dependencies: ["ShieldReviewerKeychain", "ShieldNativeContract"]),
        .testTarget(name: "ShieldApprovalContractTests", dependencies: ["ShieldApprovalContract"]),
        .testTarget(name: "ShieldApprovalVerificationTests", dependencies: ["ShieldApprovalVerification", "ShieldApprovalContract"]),
        .testTarget(name: "ShieldDurableApprovalTests", dependencies: ["ShieldDurableApproval", "ShieldApprovalVerification", "ShieldApprovalContract"]),
        .testTarget(name: "ShieldReviewerReviewTests", dependencies: ["ShieldReviewerReview", "ShieldApprovalContract"])
    ]
)
