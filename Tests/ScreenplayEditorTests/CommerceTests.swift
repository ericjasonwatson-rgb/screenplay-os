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
            .init(licenseID: UUID(), email: "writer@example.com", tier: tier, seatCount: 1, issuedAt: now.addingTimeInterval(-100),
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

    @Test func providerBoundaryUsesHostedCheckoutAndNormalizesActivationIdentity() {
        let monthly = URL(string: "https://checkout.stripe.com/test/monthly")!
        let fallback = URL(string: "mailto:hello@screenplayos.com?subject=Cancel%20ScreenplayOS")!
        let provider = HostedPaymentProvider(identifier: "stripe-managed-payments",
                                             checkoutURLs: [.proMonthly: monthly],
                                             subscriptionManagementURL: nil,
                                             cancellationFallbackURL: fallback)
        #expect(provider.checkoutURL(for: .proMonthly) == monthly)
        #expect(provider.checkoutURL(for: .studioAnnual) == nil)
        #expect(provider.subscriptionManagementURL == nil)
        #expect(LicenseActivationRequest(email: " Writer@Example.COM ").email == "writer@example.com")
        #expect(LicenseActivationExchange(email: " Writer@Example.COM ", code: " 123456 ").code == "123456")
    }

    @Test func newLicenseSeparatesPaidPeriodFromFinalGraceExpiry() throws {
        let key = Curve25519.Signing.PrivateKey()
        let paidThrough = Date(timeIntervalSince1970: 1_800_000_000)
        let expires = paidThrough.addingTimeInterval(14 * 86_400)
        let payload = LicensePayload(licenseID: UUID(), email: "writer@example.com", tier: .pro,
                                     seatCount: 1, issuedAt: paidThrough.addingTimeInterval(-100),
                                     paidThrough: paidThrough, expiresAt: expires,
                                     planID: "pro-annual", perpetualUntilVersion: nil)
        let license = try LicenseVerifier.signed(payload: payload, privateKey: key)
        let verifier = LicenseVerifier(publicKey: key.publicKey.rawRepresentation)
        guard case .grace(_, let until) = verifier.verify(license, now: paidThrough.addingTimeInterval(1)) else {
            Issue.record("Expected grace status after paid period")
            return
        }
        #expect(until == expires)
        #expect(verifier.verify(license, now: expires.addingTimeInterval(1)) == .expired(payload))
    }

    @Test func swiftVerifierAcceptsWorkerCanonicalSignature() throws {
        // Fixed vector generated by the WebCrypto implementation used by
        // LicenseWorker. This catches canonical-JSON drift between JS and Swift.
        let data = Data(#"{"payload":{"email":"writer@example.com","expiresAt":"2027-01-15T00:00:00Z","issuedAt":"2026-12-01T00:00:00Z","licenseID":"12345678-1234-4234-8234-123456789ABC","paidThrough":"2027-01-01T00:00:00Z","planID":"pro-annual","seatCount":1,"tier":"pro"},"signature":"TKh7xXn4FpX5xyIZBHUxN+8FKVnzBK1L0Ip3WAPM2t0fuYb2PvLNLtwK3L3xcfMPAXaGPWlabXW2NfjYR9HtDw=="}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(SignedLicenseFile.self, from: data)
        let key = try #require(Data(base64Encoded: "hsL75CV4nPV7X0Iifd9kBnPBm9DX5ySVTLg16wzB7nQ="))
        let duringPaidPeriod = ISO8601DateFormatter().date(from: "2026-12-15T00:00:00Z")!
        #expect(LicenseVerifier(publicKey: key).verify(file, now: duringPaidPeriod) == .valid(file.payload))
    }
}
