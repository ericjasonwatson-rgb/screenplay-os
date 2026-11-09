#if os(macOS)
import Foundation
import ShieldApprovalVerification
import ShieldMacXPCInterfaces
import ShieldSignedSample

/// One challenge per authenticated connection. This fixture has no dispatch API.
final class SignedSampleEndpoint: NSObject, ShieldSignedSampleXPC {
    private let sample = SignedSample.Challenge()
    private let verifier: EphemeralApprovalVerifier

    init(fixtureKey: Data) throws {
        verifier = try EphemeralApprovalVerifier(trustedReviewerKeys: [SignedSample.keyID: fixtureKey])
        super.init()
    }

    func challenge(_ reply: @escaping (NSData) -> Void) {
        reply(((try? JSONEncoder().encode(sample)) ?? Data()) as NSData)
    }

    func verifySample(_ signature: NSData, withReply reply: @escaping (NSData) -> Void) {
        guard (8...144).contains(signature.length), let expected = try? sample.binding() else {
            reply(Data("denied".utf8) as NSData)
            return
        }
        let approval = ReviewerApprovalSignature(reviewerKeyID: SignedSample.keyID, signatureDER: signature as Data)
        let status: String
        switch verifier.verifyAndConsume(approval, for: expected, atTrustedTime: SignedSample.now) {
        case .success: status = "verified"
        case .failure(.previouslyConsumed): status = "replay-denied"
        case .failure: status = "denied"
        }
        reply(Data(status.utf8) as NSData)
    }
}
#endif
