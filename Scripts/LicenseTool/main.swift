import CryptoKit
import Foundation
import ScreenplayDomain

func value(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

guard let privatePath = value(after: "--private-key"),
      let outputPath = value(after: "--output"),
      let tierText = value(after: "--tier"), let tier = ProductTier(rawValue: tierText),
      let seatsText = value(after: "--seats"), let seats = Int(seatsText), seats > 0,
      let plan = value(after: "--plan") else {
    fputs("Usage: swift run screenplay-license-tool --private-key /safe/test.key --output license.json --tier pro --seats 1 --plan test [--expires 2027-01-01T00:00:00Z] [--perpetual-until 1.0]\n", stderr)
    exit(64)
}

let keyURL = URL(fileURLWithPath: privatePath)
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: keyURL.path) {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
} else {
    key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try key.rawRepresentation.write(to: keyURL, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    print("Created TEST private key at \(keyURL.path). Never commit it.")
    print("Test public key (base64): \(key.publicKey.rawRepresentation.base64EncodedString())")
}

let formatter = ISO8601DateFormatter()
let expiry = value(after: "--expires").flatMap(formatter.date(from:))
let payload = LicensePayload(licenseID: UUID(), tier: tier, seatCount: seats, issuedAt: Date(), expiresAt: expiry,
                             planID: plan, perpetualUntilVersion: value(after: "--perpetual-until"))
let license = try LicenseVerifier.signed(payload: payload, privateKey: key)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(license).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
print("Wrote TEST license to \(outputPath)")
