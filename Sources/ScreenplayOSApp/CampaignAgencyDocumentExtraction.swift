import Foundation

/// Local text extraction only. No renderer, URL-based document reader, OCR,
/// password prompts, external relationship resolution, or provider is invoked.
/// The caller retains the original bytes separately from this derived text.
enum CampaignAgencyDocumentExtraction {
    static let maximumOriginalBytes = 2 * 1_024 * 1_024
    static let maximumTextBytes = 256 * 1_024

    struct Extraction: Equatable, Sendable {
        let formatRawValue: String
        let sections: [String]
        let extractor: String
        let notices: [String]
        var text: String { sections.joined(separator: "\n\n") }
    }

    enum Failure: LocalizedError, Equatable {
        case unsupported, pdfDisabled, originalTooLarge, unreadable, noText
        case tooMuchText, unsafeArchive, unsafeXML
        case externalRelationship, unsupportedContent

        var errorDescription: String? {
            switch self {
            case .unsupported: return "Choose a supported .docx document. Legacy .doc files and OCR are not supported."
            case .pdfDisabled: return "PDF import is not enabled until its parser can be isolated safely. Export verified UTF-8 text or a supported DOCX first. No OCR was performed."
            case .originalTooLarge: return "Document originals must be nonempty and no larger than 2 MiB."
            case .unreadable: return "This document could not be safely read. Export its relevant text as UTF-8 and verify it against the original."
            case .noText: return "No extractable text was found. Scanned documents require OCR outside CampaignOS."
            case .tooMuchText: return "The extracted text exceeds the 256 KiB limit. No truncated import was made."
            case .unsafeArchive: return "The DOCX archive is malformed or outside the supported safety limits. ZIP64, encrypted, duplicate, nonregular, and unsafe-path members are not supported."
            case .unsafeXML: return "The DOCX XML is malformed or outside the supported safety limits. DTDs, entity declarations, and external resources are not supported."
            case .externalRelationship: return "This DOCX contains external relationships. Nothing was fetched. Export a self-contained copy or verified plain text first."
            case .unsupportedContent: return "This DOCX contains unsupported content such as tracked changes, fields, content controls, alternative content, or embedded objects. Resolve that content or export verified plain text first."
            }
        }
    }

    static func extract(data: Data, filename: String) throws -> Extraction {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= maximumOriginalBytes else { throw Failure.originalTooLarge }
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": throw Failure.pdfDisabled
        case "docx": return try CampaignAgencyDocumentXML.extract(archive: data)
        default: throw Failure.unsupported
        }
    }
}
