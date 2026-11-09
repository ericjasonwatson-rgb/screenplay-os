#if os(macOS)
import Foundation

/// Separate ObjC-compatible XPC interfaces; no general purpose execute/evaluate API.
@objc public protocol ShieldAgentXPC {
    func prepare(_ request: NSData, withReply reply: @escaping (NSData) -> Void)
    func submit(_ request: NSData, withReply reply: @escaping (NSData) -> Void)
}

@objc public protocol ShieldReviewerXPC {
    func pending(_ request: NSData, withReply reply: @escaping (NSData) -> Void)
    func approve(_ request: NSData, withReply reply: @escaping (NSData) -> Void)
    func reject(_ request: NSData, withReply reply: @escaping (NSData) -> Void)
}
/// Local test fixture. Carries only a challenge and a fixture signature.
@objc public protocol ShieldSignedSampleXPC {
    func challenge(_ reply: @escaping (NSData) -> Void)
    func verifySample(_ signature: NSData, withReply reply: @escaping (NSData) -> Void)
}
#endif

#if os(macOS)
/// Fixture-only XPC interface used by two independently launched processes.
@objc public protocol ShieldXPCValidationProbe {
    func ping(_ reply: @escaping (Bool) -> Void)
    func deniedInvocationCount(_ reply: @escaping (Int) -> Void)
}
#endif
