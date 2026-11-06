#if os(macOS)
import Foundation
import ShieldMacXPCInterfaces

enum ProbeResult {
    case value(Bool)
    case error(NSError)
    case timeout
}
func ping(_ machName: String, requiringPeer requirement: String? = nil) -> ProbeResult {
    let connection = NSXPCConnection(machServiceName: machName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: ShieldXPCValidationProbe.self)
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: ProbeResult = .timeout
    var completed = false
    func finish(_ answer: ProbeResult) {
        lock.lock()
        if !completed {
            completed = true
            result = answer
            semaphore.signal()
        }
        lock.unlock()
    }
    // Client-initiated peer checking is independently testable against the
    // otherwise working control service, on the same launchd Mach endpoint.
    if let requirement {
        connection.setCodeSigningRequirement(requirement)
    }
    connection.resume()
    guard let remote = connection.remoteObjectProxyWithErrorHandler({ err in
        finish(.error(err as NSError))
    }) as? ShieldXPCValidationProbe else {
        connection.invalidate()
        return .timeout
    }
    remote.ping { value in finish(.value(value)) }
    let done = semaphore.wait(timeout: .now() + 6) == .success
    connection.invalidate()
    return done ? result : .timeout
}
func deniedCount() -> Int? {
    let connection = NSXPCConnection(
        machServiceName: "com.example.cips.validation.control", options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(with: ShieldXPCValidationProbe.self)
    let semaphore = DispatchSemaphore(value: 0)
    var count: Int?
    connection.resume()
    guard let remote = connection.remoteObjectProxyWithErrorHandler({ err in
        fputs("Control count error: \(err)\n", stderr)
        semaphore.signal()
    }) as? ShieldXPCValidationProbe else {
        connection.invalidate()
        return nil
    }
    remote.deniedInvocationCount { value in count = value; semaphore.signal() }
    let ok = semaphore.wait(timeout: .now() + 6) == .success
    connection.invalidate()
    return ok ? count : nil
}

if case .value(true) = ping("com.example.cips.validation.control") {
    print("PASS: live launchd XPC control responds")
} else {
    fputs("INCONCLUSIVE: launchd XPC control did not respond; no security claim\n", stderr)
    exit(77)
}
// Test 1: client requires a non-existent signed server on the KNOWN GOOD
// control endpoint. This tests an explicit OS-level signing error in isolation.
let impossibleServerRequirement = """
    identifier "com.example.cips.validation.nonexistent-server" \
    and anchor apple generic \
    and certificate leaf[subject.OU] = "ZZ99999999"
    """
switch ping("com.example.cips.validation.control", requiringPeer: impossibleServerRequirement) {
case .error(let ns):
    print("Client-required signing error: \(ns.domain) \(ns.code)")
    guard ns.code == NSXPCConnectionCodeSigningRequirementFailure else {
        fputs("FAIL: client-side signature check returned a generic connection error\n", stderr)
        exit(1)
    }
case .value, .timeout:
    fputs("FAIL: client-side signature requirement did not explicitly reject\n", stderr)
    exit(1)
}
print("PASS: macOS reports explicit code-signature failure on known-good endpoint")

// Test 2: server requires an impossible signed client. macOS may translate
// server-side denial to a generic interruption for the *client*. Therefore
// do not misrepresent error 4097 as error 4102; require a live control, a
// genuine failed request, and zero protected method invocations.
switch ping("com.example.cips.validation.denied") {
case .error(let ns):
    print("Server-required denial observed: \(ns.domain) \(ns.code)")
    guard ns.domain == NSCocoaErrorDomain else {
        fputs("FAIL: unexpected error domain from server peer validation\n", stderr)
        exit(1)
    }
case .value, .timeout:
    fputs("FAIL: server peer requirement did not result in an observed rejection\n", stderr)
    exit(1)
}
guard let attempts = deniedCount(), attempts == 0 else {
    fputs("FAIL: rejected client invoked protected method or observation failed\n", stderr)
    exit(1)
}
print("PASS: server-side restriction prevented invoking the protected method")
print("LIMITATION: server-side denial code alone cannot prove cause; real signed-app testing remains mandatory")
#else
import Foundation
exit(78)
#endif
