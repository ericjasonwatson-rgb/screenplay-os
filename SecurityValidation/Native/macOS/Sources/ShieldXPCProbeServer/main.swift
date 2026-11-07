#if os(macOS)
import Foundation
import ShieldMacXPCInterfaces

// Validation process only: no file reads, network transmission, or real asset access.
final class Probe: NSObject, ShieldXPCValidationProbe {
    private var invocationCount = 0
    private let lock = NSLock()
    var deniedProbe: Probe?
    func ping(_ reply: @escaping (Bool) -> Void) {
        lock.lock()
        invocationCount += 1
        lock.unlock()
        reply(true)
    }
    func recordedInvocationCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCount
    }
    func deniedInvocationCount(_ reply: @escaping (Int) -> Void) {
        reply(deniedProbe?.recordedInvocationCount() ?? -1)
    }
}
final class ProbeDelegate: NSObject, NSXPCListenerDelegate {
    let control = NSXPCListener(machServiceName: "com.example.cips.validation.control")
    let denied = NSXPCListener(machServiceName: "com.example.cips.validation.denied")
    let deniedObject = Probe()
    lazy var controlObject: Probe = {
        let object = Probe()
        object.deniedProbe = deniedObject
        return object
    }()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ShieldXPCValidationProbe.self)
        if listener === denied {
            connection.exportedObject = deniedObject
            // Actual OS check in a launchd-registered service, not an anonymous listener.
            // The client in this test is ad-hoc signed, so no valid Team ID can match.
            connection.setCodeSigningRequirement(
                "identifier \"com.example.cips.validation.untrusted\" " +
                "and anchor apple generic and certificate leaf[subject.OU] = \"ZZ99999999\""
            )
        } else if listener === control {
            connection.exportedObject = controlObject
        } else {
            return false
        }
        connection.resume()
        return true
    }

    func run() {
        control.delegate = self
        denied.delegate = self
        control.resume()
        denied.resume()
        RunLoop.current.run()
    }
}
let server = ProbeDelegate()
server.run()
#else
import Foundation
fputs("This test requires macOS.\n", stderr)
exit(78)
#endif
