import CryptoKit
import Foundation

public enum ProductTier: String, Codable, CaseIterable, Sendable { case free, pro, studio }

public enum CommerceFeature: String, Codable, CaseIterable, Sendable {
    case continuityBible, promptComposer, aiGeneration, takes, animaticAudio, costLedger, provenance
    case editHandoff, sharedBibles, reviewApprovals, disclosureReports

    public var minimumTier: ProductTier {
        switch self {
        case .sharedBibles, .reviewApprovals, .disclosureReports: return .studio
        default: return .pro
        }
    }
}

public enum CoreCapability: String, CaseIterable, Sendable {
    case open, save, autosave, recovery, pdfExport, fdxExport, readExistingDocuments
}

public enum CommerceConfiguration {
    public static let enforcementKey = "commerce.enforcement"
    public static let licenseServiceBaseURL = URL(string: "https://license.screenplayos.com")!
    // Replace only during the production signer ceremony. The private half
    // belongs in the license Worker secret store and must never ship in the app.
    public static let licensePublicKeyBase64 = "PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw="
    public static func enforcementEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enforcementKey) // absent is deliberately false
    }
}

public enum CommercePlan: String, Codable, CaseIterable, Sendable {
    case proMonthly = "pro-monthly"
    case proAnnual = "pro-annual"
    case foundingAnnual = "founding-annual"
    case studioMonthly = "studio-monthly"
    case studioAnnual = "studio-annual"
}

/// The application depends on this boundary, not Stripe, Paddle, or their SDKs.
/// Implementations return browser URLs only; payment UI never appears in-app.
public protocol PaymentProvider: Sendable {
    var identifier: String { get }
    func checkoutURL(for plan: CommercePlan) -> URL?
    var subscriptionManagementURL: URL? { get }
    var cancellationFallbackURL: URL { get }
}

public struct HostedPaymentProvider: PaymentProvider, Equatable, Sendable {
    public let identifier: String
    public let checkoutURLs: [CommercePlan: URL]
    public let subscriptionManagementURL: URL?
    public let cancellationFallbackURL: URL

    public init(identifier: String, checkoutURLs: [CommercePlan: URL],
                subscriptionManagementURL: URL?, cancellationFallbackURL: URL) {
        self.identifier = identifier
        self.checkoutURLs = checkoutURLs
        self.subscriptionManagementURL = subscriptionManagementURL
        self.cancellationFallbackURL = cancellationFallbackURL
    }

    public func checkoutURL(for plan: CommercePlan) -> URL? { checkoutURLs[plan] }
}

public struct LicenseActivationRequest: Codable, Equatable, Sendable {
    public let email: String
    public init(email: String) { self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

public struct LicenseActivationExchange: Codable, Equatable, Sendable {
    public let email: String
    public let code: String
    public init(email: String, code: String) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Entitlements: Equatable, Sendable {
    public var tier: ProductTier
    public var enforcementEnabled: Bool

    public init(tier: ProductTier = .free, enforcementEnabled: Bool = false) {
        self.tier = tier
        self.enforcementEnabled = enforcementEnabled
    }

    public init(tier: ProductTier, defaults: UserDefaults) {
        self.init(tier: tier, enforcementEnabled: CommerceConfiguration.enforcementEnabled(in: defaults))
    }

    public func allows(_ feature: CommerceFeature) -> Bool {
        guard enforcementEnabled else { return feature.minimumTier != .studio }
        return rank(tier) >= rank(feature.minimumTier)
    }

    public func allows(_ capability: CoreCapability) -> Bool { true }

    private func rank(_ tier: ProductTier) -> Int {
        switch tier { case .free: return 0; case .pro: return 1; case .studio: return 2 }
    }
}

public struct PricingConfiguration: Codable, Equatable, Sendable {
    public static let current: PricingConfiguration = {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PricingConfiguration.self, from: data) else {
            fatalError("The bundled pricing configuration is missing or invalid.")
        }
        return value
    }()

    public let currency: String
    public let proMonthlyCents: Int
    public let proAnnualCents: Int
    public let foundingAnnualCents: Int
    public let studioMinimumSeats: Int
    public let studioMonthlyPerSeatCents: Int?
    public let studioAnnualPerSeatCents: Int?
    public let perpetualEligibilityPaidMonths: Int

    public func annualProPriceCents(isFoundingCustomer: Bool) -> Int {
        isFoundingCustomer ? foundingAnnualCents : proAnnualCents
    }

    public func billableStudioSeats(requested: Int) -> Int { max(studioMinimumSeats, requested) }
}

public struct LicensePayload: Codable, Equatable, Sendable {
    public let licenseID: UUID
    public let email: String
    public let tier: ProductTier
    public let seatCount: Int
    public let issuedAt: Date
    /// End of the paid period. `expiresAt` includes the 14-day offline grace.
    public let paidThrough: Date?
    public let expiresAt: Date?
    public let planID: String
    public let perpetualUntilVersion: String?

    public init(licenseID: UUID, email: String = "", tier: ProductTier, seatCount: Int, issuedAt: Date,
                paidThrough: Date? = nil, expiresAt: Date?, planID: String, perpetualUntilVersion: String?) {
        self.licenseID = licenseID
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.tier = tier
        self.seatCount = seatCount
        self.issuedAt = issuedAt
        self.paidThrough = paidThrough
        self.expiresAt = expiresAt
        self.planID = planID
        self.perpetualUntilVersion = perpetualUntilVersion
    }
}

public struct SignedLicenseFile: Codable, Equatable, Sendable {
    public let payload: LicensePayload
    public let signature: String

    public init(payload: LicensePayload, signature: String) {
        self.payload = payload
        self.signature = signature
    }
}

public enum LicenseStatus: Equatable, Sendable {
    case valid(LicensePayload)
    case grace(LicensePayload, until: Date)
    case expired(LicensePayload)
    case invalid
}

public struct LicenseVerifier: Sendable {
    public static let offlineGraceDays = 14
    public let publicKey: Data

    public init(publicKey: Data) { self.publicKey = publicKey }

    public func verify(_ file: SignedLicenseFile, now: Date) -> LicenseStatus {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard file.payload.seatCount > 0,
              file.payload.paidThrough == nil || file.payload.email.contains("@"),
              let signature = Data(base64Encoded: file.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              let payload = try? encoder.encode(file.payload),
              key.isValidSignature(signature, for: payload) else { return .invalid }
        guard let expiry = file.payload.expiresAt else { return .valid(file.payload) }
        if let paidThrough = file.payload.paidThrough {
            if now <= paidThrough { return .valid(file.payload) }
            return now <= expiry ? .grace(file.payload, until: expiry) : .expired(file.payload)
        }
        // Compatibility with foundation licenses issued before paidThrough existed.
        if now <= expiry { return .valid(file.payload) }
        let graceEnd = expiry.addingTimeInterval(TimeInterval(Self.offlineGraceDays * 86_400))
        return now <= graceEnd ? .grace(file.payload, until: graceEnd) : .expired(file.payload)
    }

    public static func signed(payload: LicensePayload, privateKey: Curve25519.Signing.PrivateKey) throws -> SignedLicenseFile {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return .init(payload: payload, signature: try privateKey.signature(for: encoder.encode(payload)).base64EncodedString())
    }
}

public struct PerpetualFallback: Equatable, Sendable {
    public let paidMonths: Int
    public let perpetualUntilVersion: String?

    public func allows(version: String, pricing: PricingConfiguration = .current) -> Bool {
        guard paidMonths >= pricing.perpetualEligibilityPaidMonths,
              let ceiling = perpetualUntilVersion else { return false }
        return version.compare(ceiling, options: .numeric) != .orderedDescending
    }
}
