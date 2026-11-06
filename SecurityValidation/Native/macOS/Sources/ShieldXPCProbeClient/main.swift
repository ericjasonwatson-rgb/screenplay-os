#if os(macOS)
import Foundation
import ShieldMacXPCInterfaces

enum ProbeResult {
    case value(Bool)
    case error(NSError)
    case timeout
}
func ping(_ machName: String) -> ProbeResult {
    let connection = NSXPCConnection(machServiceName: machName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: ShieldXPCValidationProbe.self)
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: ProbeResult = .timeout
    func finish(_ answer: ProbeResult) {
        lock.lock()
        result = answer
        lock.unlock()
        semaphore.signal()
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
let bad = ping("com.example.cips.validation.denied")
switch bad {
case .error(let ns):
    print("Rejected client NSError: \(ns.domain) \(ns.code)")
    guard ns.code == NSXPCConnectionCodeSigningRequirementFailure else {
        fputs("FAIL: error is not explicit XPC code-signing rejection\n", stderr)
        exit(1)
    }
case .value, .timeout:
    fputs("FAIL: no proven XPC code-signing rejection\n", stderr)
    exit(1)
}
guard let attempts = deniedCount(), attempts == 0 else {
    fputs("FAIL: rejected connection invoked protected service method, or count was inaccessible\n", stderr)
    exit(1)
}
print("PASS: mismatched signing requirement rejected before any protected method ran")
#else
import Foundation
exit(78)
#endif
