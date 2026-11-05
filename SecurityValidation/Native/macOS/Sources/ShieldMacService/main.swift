#if os(macOS)
import Foundation
import Security
import ShieldNativeContract
import ShieldMacXPCInterfaces

// This validation-only service NEVER dispatches protected content.
// Its methods all return a deterministic denial.
final class AgentEndpoint: NSObject, ShieldAgentXPC {
    func prepare(_ request: NSData, withReply reply: @escaping (NSData) -> Void) {
        reply(FailClosedCommandHandler.response(to: request as Data, role: .agent, requestedOperation: "prepare") as NSData)
    }
    func submit(_ request: NSData, withReply reply: @escaping (NSData) -> Void) {
        reply(FailClosedCommandHandler.response(to: request as Data, role: .agent, requestedOperation: "submit") as NSData)
    }
}

final class ReviewerEndpoint: NSObject, ShieldReviewerXPC {
    func pending(_ request: NSData, withReply reply: @escaping (NSData) -> Void) {
        reply(FailClosedCommandHandler.response(to: request as Data, role: .reviewer, requestedOperation: "pending") as NSData)
    }
    func approve(_ request: NSData, withReply reply: @escaping (NSData) -> Void) {
        reply(FailClosedCommandHandler.response(to: request as Data, role: .reviewer, requestedOperation: "approve") as NSData)
    }
    func reject(_ request: NSData, withReply reply: @escaping (NSData) -> Void) {
        reply(FailClosedCommandHandler.response(to: request as Data, role: .reviewer, requestedOperation: "reject") as NSData)
    }
}

final class SignedListenerDelegate: NSObject, NSXPCListenerDelegate {
    let configuration: SignedPeerConfiguration
    let agentListener: NSXPCListener
    let reviewerListener: NSXPCListener

    init(_ configuration: SignedPeerConfiguration) {
        self.configuration = configuration
        agentListener = NSXPCListener(machServiceName: configuration.agentMachService)
        reviewerListener = NSXPCListener(machServiceName: configuration.reviewerMachService)
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if listener === agentListener {
            connection.setCodeSigningRequirement(configuration.requirement(for: .agent))
            connection.exportedInterface = NSXPCInterface(with: ShieldAgentXPC.self)
            connection.exportedObject = AgentEndpoint()
        } else if listener === reviewerListener {
            connection.setCodeSigningRequirement(configuration.requirement(for: .reviewer))
            connection.exportedInterface = NSXPCInterface(with: ShieldReviewerXPC.self)
            connection.exportedObject = ReviewerEndpoint()
        } else {
            return false
        }
        connection.resume()
        return true
    }

    func serve() -> Never {
        agentListener.delegate = self
        reviewerListener.delegate = self
        agentListener.resume()
        reviewerListener.resume()
        RunLoop.current.run()
        fatalError("XPC service run loop exited unexpectedly")
    }
}

func requireSignedBundleValue(_ key: String) -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty else {
        fputs("missing signed helper configuration\n", stderr)
        exit(78)
    }
    return value
}

do {
    let config = try SignedPeerConfiguration(
        teamID: requireSignedBundleValue("CIPSTeamID"),
        agentBundleID: requireSignedBundleValue("CIPSAgentBundleID"),
        reviewerBundleID: requireSignedBundleValue("CIPSReviewerBundleID"),
        helperBundleID: requireSignedBundleValue("CFBundleIdentifier"),
        agentMachService: requireSignedBundleValue("CIPSAgentMachService"),
        reviewerMachService: requireSignedBundleValue("CIPSReviewerMachService")
    )
    let requirements = [
        config.requirement(for: .agent),
        config.requirement(for: .reviewer),
        config.helperRequirement()
    ]
    for requirement in requirements {
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, SecCSFlags(rawValue: 0), &parsed) == errSecSuccess,
              parsed != nil else {
            fputs("code-signing requirement failed OS parsing; service disabled\n", stderr)
            exit(78)
        }
    }
    // Deployment preflight: independently check the helper's OWN dynamic signature
    // before exposing the agent/reviewer Mach services. A CI build does not test
    // successful production signing; unsigned/ad-hoc helpers must fail closed.
    var helperRequirement: SecRequirement?
    guard SecRequirementCreateWithString(
            config.helperRequirement() as CFString, SecCSFlags(rawValue: 0), &helperRequirement
          ) == errSecSuccess,
          let helperRequirement else {
        fputs("helper requirement failed validation; service disabled\n", stderr)
        exit(78)
    }
    var runningCode: SecCode?
    guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &runningCode) == errSecSuccess,
          let runningCode,
          SecCodeCheckValidity(runningCode, SecCSFlags(rawValue: 0), helperRequirement) == errSecSuccess else {
        fputs("helper code-signing identity is not trusted; service disabled\n", stderr)
        exit(78)
    }
    SignedListenerDelegate(config).serve()
} catch {
    fputs("invalid signed helper configuration\n", stderr)
    exit(78)
}
#else
import Foundation
fputs("ShieldMacService requires macOS; no fallback service is started.\n", stderr)
exit(78)
#endif
