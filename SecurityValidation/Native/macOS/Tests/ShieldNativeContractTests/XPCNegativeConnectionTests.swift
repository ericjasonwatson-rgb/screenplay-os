#if os(macOS)
import Foundation
import XCTest

// macOS-only runtime test of Apple's XPC peer-signature rejection.
// This is a test fixture, not the deployed helper, and has no data egress.
@objc private protocol NegativeProbeXPC {
    func ping(_ reply: @escaping (Bool) -> Void)
}

private final class NegativeProbeTarget: NSObject, NegativeProbeXPC {
    let onUnexpectedInvocation: () -> Void

    init(onUnexpectedInvocation: @escaping () -> Void) {
        self.onUnexpectedInvocation = onUnexpectedInvocation
    }

    func ping(_ reply: @escaping (Bool) -> Void) {
        onUnexpectedInvocation()
        reply(true)
    }
}

private final class NegativeProbeListenerDelegate: NSObject, NSXPCListenerDelegate {
    let target: NegativeProbeTarget
    let impossibleRequirement: String

    init(target: NegativeProbeTarget, impossibleRequirement: String) {
        self.target = target
        self.impossibleRequirement = impossibleRequirement
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NegativeProbeXPC.self)
        connection.exportedObject = target
        // A synthetic Team ID cannot match the ad-hoc GitHub test process.
        // The requirement syntax is checked separately via Security.framework.
        connection.setCodeSigningRequirement(impossibleRequirement)
        connection.resume()
        return true
    }
}

final class XPCNegativeConnectionTests: XCTestCase {
    func testUntrustedClientFailsBeforeInvokingExportedMethod() throws {
        let notCalled = expectation(description: "protected XPC method never invoked")
        notCalled.isInverted = true

        let target = NegativeProbeTarget(onUnexpectedInvocation: { notCalled.fulfill() })
        let requirement = """
            identifier "com.example.shield.impossible-client" and anchor apple generic \
            and certificate leaf[subject.OU] = "ZZ99999999"
            """
        let delegate = NegativeProbeListenerDelegate(
            target: target,
            impossibleRequirement: requirement
        )

        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: NegativeProbeXPC.self)
        connection.resume()
        defer { connection.invalidate() }

        let rejected = expectation(description: "XPC rejects unmatched code signing")
        let remote = connection.remoteObjectProxyWithErrorHandler { error in
            let nsError = error as NSError
            XCTAssertEqual(
                nsError.code,
                NSXPCConnectionCodeSigningRequirementFailure,
                "Expected an actual XPC code-signing rejection, got: \(nsError)"
            )
            rejected.fulfill()
        } as? NegativeProbeXPC
        XCTAssertNotNil(remote)
        remote?.ping { _ in
            notCalled.fulfill()
        }

        wait(for: [rejected, notCalled], timeout: 5)
    }
}
#endif
