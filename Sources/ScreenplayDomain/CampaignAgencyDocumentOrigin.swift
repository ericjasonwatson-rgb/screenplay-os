import Foundation
import CryptoKit

/// Retained original document bytes and the exact output of one bounded local
/// extractor. Neither a digest nor a filename authenticates an agency or sender.
public struct CampaignAgencyDocumentOrigin: Codable, Equatable {
    public static let maximumOriginalBytes = 2 * 1_024 * 1_024
    public static let maximumTotalOriginalBytes = 4 * 1_024 * 1_024
    public let format: String
    public let originalBytes: Data
    public let originalSHA256: String
    public let sections: [String]
    public let extractor: String
    public let notices: [String]
    public var text: String { sections.joined(separator: "\n\n") }

    public init(format: String, originalBytes: Data, sections: [String], extractor: String, notices: [String]) throws {
        self.format = format; self.originalBytes = originalBytes
        originalSHA256 = Self.digest(originalBytes)
        self.sections = sections; self.extractor = extractor; self.notices = notices
        try validate()
    }

    enum CodingKeys: String, CodingKey { case format, originalBytes, originalSHA256, sections, extractor, notices }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        originalBytes = try c.decode(Data.self, forKey: .originalBytes)
        originalSHA256 = try c.decode(String.self, forKey: .originalSHA256)
        sections = try c.decode([String].self, forKey: .sections)
        extractor = try c.decode(String.self, forKey: .extractor)
        notices = try c.decode([String].self, forKey: .notices)
        try validate()
    }

    public func validate() throws {
        guard format == "docx",
              extractor == "docx-body-text-v1",
              !originalBytes.isEmpty, originalBytes.count <= Self.maximumOriginalBytes,
              Self.digest(originalBytes) == originalSHA256 else {
            throw CampaignError.invalid("Unsupported or damaged agency document provenance.")
        }
        let signature = Data([0x50, 0x4b, 0x03, 0x04])
        guard originalBytes.starts(with: signature), !sections.isEmpty,
              sections.count == 1,
              sections.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !text.unicodeScalars.contains(where: { $0.value == 0 }),
              text.utf8.count <= CampaignAgencyWorkspace.maximumSourceBytes,
              !notices.isEmpty, notices.count <= 16,
              notices.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4_096 }) else {
            throw CampaignError.invalid("Agency document extraction is empty, unsupported, or exceeds its bounded limits.")
        }
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
