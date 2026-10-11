import CryptoKit
import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Commerce foundations")
struct CommerceTests {
    @Test func enforcementDefaultsToProWithoutLimitingCoreWork() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!CommerceConfiguration.enforcementEnabled(in: defaults))
        let defaultAccess = Entitlements()
        #expect(defaultAccess.allows(.continuityBible))
        #expect(defaultAccess.allows(.editHandoff))
        #expect(!defaultAccess.allows(.sharedBibles))
        for capability in CoreCapability.allCases { #expect(defaultAccess.allows(capability)) }

        let enforcedFree = Entitlements(tier: .free, enforcementEnabled: true)
        #expect(!enforcedFree.allows(.continuityBible))
        for capability in CoreCapability.allCases { #expect(enforcedFree.allows(capability)) }
        #expect(Entitlements(tier: .studio, enforcementEnabled: true).allows(.sharedBibles))
    }

    @Test func pricingHonorsFoundingMinimumSeatAndPerpetualRules() {
        let pricing = PricingConfiguration.current
        #expect(pricing.annualProPriceCents(isFoundingCustomer: true) == 6_900)
        #expect(pricing.annualProPriceCents(isFoundingCustomer: false) == 9_900)
        #expect(pricing.billableStudioSeats(requested: 1) == 3)
        #expect(PerpetualFallback(paidMonths: 12, perpetualUntilVersion: "1.4").allows(version: "1.3"))
        #expect(!PerpetualFallback(paidMonths: 11, perpetualUntilVersion: "1.4").allows(version: "1.3"))
        #expect(!PerpetualFallback(paidMonths: 12, perpetualUntilVersion: "1.4").allows(version: "1.5"))
    }

    @Test func signedLicensesValidateExpiryGraceTamperingAndTier() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func payload(tier: ProductTier = .pro, expiry: Date?) -> LicensePayload {
            .init(licenseID: UUID(), tier: tier, seatCount: 1, issuedAt: now.addingTimeInterval(-100),
                  expiresAt: expiry, planID: "test", perpetualUntilVersion: nil)
        }
        let verifier = LicenseVerifier(publicKey: key.publicKey.rawRepresentation)
        let valid = try LicenseVerifier.signed(payload: payload(tier: .studio, expiry: now.addingTimeInterval(60)), privateKey: key)
        guard case let .valid(value) = verifier.verify(valid, now: now) else { Issue.record("Expected valid license"); return }
        #expect(value.tier == .studio)

        let grace = try LicenseVerifier.signed(payload: payload(expiry: now.addingTimeInterval(-86_400)), privateKey: key)
        guard case .grace = verifier.verify(grace, now: now) else { Issue.record("Expected grace license"); return }
        let expired = try LicenseVerifier.signed(payload: payload(expiry: now.addingTimeInterval(-15 * 86_400)), privateKey: key)
        guard case .expired = verifier.verify(expired, now: now) else { Issue.record("Expected expired license"); return }

        let tampered = SignedLicenseFile(payload: payload(tier: .free, expiry: nil), signature: valid.signature)
        #expect(verifier.verify(tampered, now: now) == .invalid)
        #expect(LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation).verify(valid, now: now) == .invalid)
    }
}
