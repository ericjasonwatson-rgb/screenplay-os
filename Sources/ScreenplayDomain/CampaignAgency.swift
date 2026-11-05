import CryptoKit
import Foundation

public enum CampaignAgencyTargetKind: String, Codable, CaseIterable {
    case deliverable, assumption
}

/// An immutable local import. Identity and a digest describe provenance, not authenticity.
/// Exact UTF-8 bytes, including a BOM and original newline encoding, are retained.
public struct CampaignAgencyRevision: Codable, Equatable, Identifiable {
    public let id: UUID
    public let documentID: UUID
    public let priorRevisionID: UUID?
    public let filename: String
    public let bytes: Data
    public let text: String
    public let sha256: String
    public let importedAt: Date
    public let origin: CampaignAgencyDocumentOrigin?

    /// One-based citation coordinates. Only LF and CRLF delimit lines. A terminal
    /// newline creates a final empty line; lone CR and Unicode separators stay literal.
    public var lines: [String] {
        let rows = text.components(separatedBy: "\n")
        return rows.enumerated().map { index, line in
            index < rows.count - 1 && line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
    }

    public func excerpt(firstLine: Int, lastLine: Int) throws -> String {
        let rows = lines
        guard firstLine > 0, lastLine >= firstLine, lastLine <= rows.count else {
            throw CampaignError.invalid("Agency citation lines are outside the imported revision.")
        }
        return rows[(firstLine - 1)...(lastLine - 1)].joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey { case id, documentID, priorRevisionID, filename, bytes, text, sha256, importedAt, origin }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        priorRevisionID = try c.decodeIfPresent(UUID.self, forKey: .priorRevisionID)
        filename = try c.decode(String.self, forKey: .filename)
        bytes = try c.decode(Data.self, forKey: .bytes)
        text = try c.decode(String.self, forKey: .text)
        sha256 = try c.decode(String.self, forKey: .sha256)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        origin = try c.decodeIfPresent(CampaignAgencyDocumentOrigin.self, forKey: .origin)
        try validate()
    }

    fileprivate init(documentID: UUID, priorRevisionID: UUID?, filename: String, bytes: Data, origin: CampaignAgencyDocumentOrigin? = nil, at date: Date) throws {
        guard !bytes.isEmpty, bytes.count <= CampaignAgencyWorkspace.maximumSourceBytes else {
            throw CampaignError.invalid("Agency text must contain 1–262144 bytes.")
        }
        id = UUID(); self.documentID = documentID; self.priorRevisionID = priorRevisionID
        self.filename = filename; self.bytes = bytes; self.origin = origin
        text = String(decoding: bytes, as: UTF8.self)
        sha256 = campaignAgencyDigest(bytes); importedAt = date
        try validate()
    }

    fileprivate func validate() throws {
        if let origin {
            try origin.validate()
            guard Data(origin.text.utf8) == bytes else {
                throw CampaignError.invalid("Extracted agency text no longer matches its retained provenance.")
            }
        }
        guard !bytes.isEmpty, bytes.count <= CampaignAgencyWorkspace.maximumSourceBytes,
              Data(text.utf8) == bytes,
              !text.unicodeScalars.contains(where: { $0.value == 0 }),
              campaignAgencyDigest(bytes) == sha256 else {
            throw CampaignError.invalid("Agency sources must contain valid UTF-8 text, match their exact bytes and SHA256, and be at most 256 KiB.")
        }
        guard !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              filename.utf8.count <= 255, ![".", ".."].contains(filename),
              !filename.contains("/"), !filename.contains("\\"),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              importedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CampaignError.invalid("Agency provenance requires a filename only and a finite import date.")
        }
    }
}

/// A person's local review note. It is not a verified identity or campaign approval.
public struct CampaignAgencyReview: Codable, Equatable, Identifiable {
    public let id: UUID
    public let documentID: UUID
    public let revisionID: UUID
    public let reviewer: String
    public let note: String
    public let createdAt: Date
}

/// A human-authored reconciliation to an exact imported revision and target state.
/// Editing either end never silently migrates this evidence to the new state.
public struct CampaignAgencyCitation: Codable, Equatable, Identifiable {
    public let id: UUID
    public let documentID: UUID
    public let revisionID: UUID
    public let firstLine: Int
    public let lastLine: Int
    public let targetKind: CampaignAgencyTargetKind
    public let targetID: UUID
    public let targetSnapshot: String
    public let note: String
    public let createdAt: Date
}

public struct CampaignAgencyWarning: Equatable, Identifiable {
    public let id: String
    public let sourceID: UUID
    public let sourceKind: CampaignSourceKind
    public let message: String
    public let affectedDeliverableIDs: [UUID]
}

public struct CampaignAgencyWorkspace: Codable, Equatable {
    public static let maximumSourceBytes = 256 * 1_024
    public static let maximumTotalSourceBytes = 1_024 * 1_024
    public static let maximumRevisions = 32
    public static let maximumAnnotations = 256
    public private(set) var revisions: [CampaignAgencyRevision]
    public private(set) var reviews: [CampaignAgencyReview]
    public private(set) var citations: [CampaignAgencyCitation]

    public init() { revisions = []; reviews = []; citations = [] }

    enum CodingKeys: String, CodingKey { case revisions, reviews, citations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revisions = try c.decode([CampaignAgencyRevision].self, forKey: .revisions)
        reviews = try c.decode([CampaignAgencyReview].self, forKey: .reviews)
        citations = try c.decode([CampaignAgencyCitation].self, forKey: .citations)
        try validate()
    }

    /// Import sequence, never a wall-clock timestamp, determines the latest revision.
    public var latestRevisions: [CampaignAgencyRevision] {
        let previousIDs = Set(revisions.compactMap(\.priorRevisionID))
        return revisions.filter { !previousIDs.contains($0.id) }
    }

    public func latestRevision(documentID: UUID) -> CampaignAgencyRevision? {
        revisions.last { $0.documentID == documentID }
    }

    public func currentReview(revisionID: UUID) -> CampaignAgencyReview? {
        guard let revision = revisions.first(where: { $0.id == revisionID }),
              latestRevision(documentID: revision.documentID)?.id == revisionID else { return nil }
        return reviews.last { $0.revisionID == revisionID }
    }

    public func validate() throws {
        guard revisions.count <= Self.maximumRevisions, reviews.count <= Self.maximumAnnotations,
              citations.count <= Self.maximumAnnotations else {
            throw CampaignError.invalid("Agency evidence exceeds the supported revision or annotation limit.")
        }
        try campaignUnique(revisions.map(\.id), "agency revisions")
        try campaignUnique(reviews.map(\.id), "agency reviews")
        try campaignUnique(citations.map(\.id), "agency citations")
        var heads: [UUID: UUID] = [:]
        var totalBytes = 0
        var totalOriginalBytes = 0
        for revision in revisions {
            try revision.validate()
            totalBytes += revision.bytes.count
            totalOriginalBytes += revision.origin?.originalBytes.count ?? 0
            guard totalOriginalBytes <= CampaignAgencyDocumentOrigin.maximumTotalOriginalBytes else {
                throw CampaignError.invalid("Retained original agency documents exceed the 4 MiB workspace limit.")
            }
            guard totalBytes <= Self.maximumTotalSourceBytes,
                  revision.priorRevisionID == heads[revision.documentID] else {
                throw CampaignError.invalid("Agency history must be a retained, ordered revision chain per document, totaling at most 1 MiB.")
            }
            heads[revision.documentID] = revision.id
        }
        let byID = Dictionary(uniqueKeysWithValues: revisions.map { ($0.id, $0) })
        for review in reviews {
            guard byID[review.revisionID]?.documentID == review.documentID else {
                throw CampaignError.invalid("Agency review references an unknown document revision.")
            }
            try campaignAgencyNote(review.reviewer, label: "reviewer", maximumBytes: 1_024)
            try campaignAgencyNote(review.note, label: "review note")
            try campaignAgencyDate(review.createdAt)
        }
        for citation in citations {
            guard let revision = byID[citation.revisionID], revision.documentID == citation.documentID,
                  reviews.contains(where: { $0.revisionID == citation.revisionID }) else {
                throw CampaignError.invalid("Agency citation requires a retained, explicitly reviewed document revision.")
            }
            _ = try revision.excerpt(firstLine: citation.firstLine, lastLine: citation.lastLine)
            try campaignAgencyNote(citation.note, label: "reconciliation note")
            try campaignAgencyDate(citation.createdAt)
            guard citation.targetSnapshot.utf8.count <= 256 * 1_024 else {
                throw CampaignError.invalid("Agency citation target snapshot is too large.")
            }
            let snapshot = Data(citation.targetSnapshot.utf8)
            let canonical: String
            switch citation.targetKind {
            case .deliverable:
                let item = try JSONDecoder().decode(CampaignDeliverable.self, from: snapshot)
                guard item.id == citation.targetID else { throw CampaignError.invalid("Citation target identity does not match its evidence.") }
                try CampaignDraft(deliverables: [item]).validate()
                canonical = try campaignJSON(item)
            case .assumption:
                let item = try JSONDecoder().decode(CampaignAssumption.self, from: snapshot)
                guard item.id == citation.targetID else { throw CampaignError.invalid("Citation target identity does not match its evidence.") }
                canonical = try campaignJSON(item)
            }
            guard canonical.utf8.elementsEqual(citation.targetSnapshot.utf8) else {
                throw CampaignError.invalid("Citation target evidence is malformed or contains unsupported data.")
            }
        }
    }

    public func warnings(draft: CampaignDraft) -> [CampaignAgencyWarning] {
        let all = draft.deliverables.map(\.id).sorted { $0.uuidString < $1.uuidString }
        var result: [CampaignAgencyWarning] = []
        for revision in latestRevisions where currentReview(revisionID: revision.id) == nil {
            result.append(.init(id: "agencyDocument:" + revision.documentID.uuidString + ":unresolved",
                sourceID: revision.documentID, sourceKind: .agencyDocument,
                message: "Current agency revision needs explicit human review: " + revision.filename,
                affectedDeliverableIDs: all))
        }
        for citation in citations {
            var reasons: [String] = []
            if latestRevision(documentID: citation.documentID)?.id != citation.revisionID {
                reasons.append("Citation points to a superseded agency revision. Review the current revision and explicitly replace or remove this citation.")
            }
            let current = try? draft.agencyTargetSnapshot(kind: citation.targetKind, id: citation.targetID)
            if current == nil {
                reasons.append("Cited campaign target was removed.")
            } else if !(current?.utf8.elementsEqual(citation.targetSnapshot.utf8) ?? false) {
                reasons.append("Cited campaign target changed. Explicitly replace or remove this citation after reconciliation.")
            }
            if !reasons.isEmpty {
                result.append(.init(id: "agencyCitation:" + citation.id.uuidString + ":unresolved",
                    sourceID: citation.id, sourceKind: .agencyCitation,
                    message: reasons.joined(separator: "\n"),
                    affectedDeliverableIDs: citation.targetKind == .deliverable ? [citation.targetID] : all))
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    fileprivate mutating func importText(data: Data, filename: String, revisingDocumentID: UUID?, origin: CampaignAgencyDocumentOrigin? = nil, at date: Date) throws -> CampaignAgencyRevision {
        try validate()
        let prior = revisingDocumentID.flatMap { latestRevision(documentID: $0) }
        if revisingDocumentID != nil && prior == nil { throw CampaignError.invalid("Choose an existing agency document to import its next revision.") }
        let revision = try CampaignAgencyRevision(documentID: prior?.documentID ?? UUID(), priorRevisionID: prior?.id, filename: filename, bytes: data, origin: origin, at: date)
        var candidate = self; candidate.revisions.append(revision); try candidate.validate()
        self = candidate
        return revision
    }

    fileprivate mutating func review(revisionID: UUID, reviewer: String, note: String, at date: Date) throws -> CampaignAgencyReview {
        guard let revision = revisions.first(where: { $0.id == revisionID }),
              latestRevision(documentID: revision.documentID)?.id == revisionID else {
            throw CampaignError.invalid("Review the current agency revision, not an unknown or superseded revision.")
        }
        let record = CampaignAgencyReview(id: UUID(), documentID: revision.documentID, revisionID: revisionID, reviewer: reviewer, note: note, createdAt: date)
        var candidate = self; candidate.reviews.append(record); try candidate.validate()
        self = candidate
        return record
    }

    fileprivate mutating func cite(revisionID: UUID, firstLine: Int, lastLine: Int, targetKind: CampaignAgencyTargetKind, targetID: UUID, targetSnapshot: String, note: String, at date: Date) throws -> CampaignAgencyCitation {
        guard let review = currentReview(revisionID: revisionID) else {
            throw CampaignError.invalid("Explicitly review the current agency revision before reconciling a citation.")
        }
        let citation = CampaignAgencyCitation(id: UUID(), documentID: review.documentID, revisionID: revisionID, firstLine: firstLine, lastLine: lastLine, targetKind: targetKind, targetID: targetID, targetSnapshot: targetSnapshot, note: note, createdAt: date)
        var candidate = self; candidate.citations.append(citation); try candidate.validate()
        self = candidate
        return citation
    }

    fileprivate mutating func removeCitation(id: UUID) throws {
        guard citations.contains(where: { $0.id == id }) else { throw CampaignError.invalid("Agency citation not found.") }
        citations.removeAll { $0.id == id }
    }
}

extension CampaignDraft {
    @discardableResult public mutating func importAgencyText(data: Data, filename: String, revisingDocumentID: UUID? = nil, at date: Date = Date()) throws -> CampaignAgencyRevision {
        try validate()
        var workspace = agency ?? .init()
        let revision = try workspace.importText(data: data, filename: filename, revisingDocumentID: revisingDocumentID, at: date)
        agency = workspace
        return revision
    }

    @discardableResult public mutating func importAgencyDocument(origin: CampaignAgencyDocumentOrigin, filename: String, revisingDocumentID: UUID? = nil, at date: Date = Date()) throws -> CampaignAgencyRevision {
        try validate()
        try origin.validate()
        var workspace = agency ?? .init()
        let revision = try workspace.importText(data: Data(origin.text.utf8), filename: filename,
            revisingDocumentID: revisingDocumentID, origin: origin, at: date)
        agency = workspace
        return revision
    }

    @discardableResult public mutating func reviewAgencyRevision(revisionID: UUID, reviewer: String, note: String, at date: Date = Date()) throws -> CampaignAgencyReview {
        try validate()
        guard var workspace = agency else { throw CampaignError.invalid("Import an agency text document first.") }
        let review = try workspace.review(revisionID: revisionID, reviewer: reviewer, note: note, at: date)
        agency = workspace
        return review
    }

    @discardableResult public mutating func citeAgencyRevision(revisionID: UUID, firstLine: Int, lastLine: Int, targetKind: CampaignAgencyTargetKind, targetID: UUID, note: String, at date: Date = Date()) throws -> CampaignAgencyCitation {
        try validate()
        guard var workspace = agency else { throw CampaignError.invalid("Import an agency text document first.") }
        let snapshot = try agencyTargetSnapshot(kind: targetKind, id: targetID)
        let citation = try workspace.cite(revisionID: revisionID, firstLine: firstLine, lastLine: lastLine, targetKind: targetKind, targetID: targetID, targetSnapshot: snapshot, note: note, at: date)
        agency = workspace
        return citation
    }

    public mutating func removeAgencyCitation(id: UUID) throws {
        try validate()
        guard var workspace = agency else { throw CampaignError.invalid("Agency citation not found.") }
        try workspace.removeCitation(id: id)
        agency = workspace
    }

    fileprivate func agencyTargetSnapshot(kind: CampaignAgencyTargetKind, id: UUID) throws -> String {
        switch kind {
        case .deliverable:
            if let item = deliverables.first(where: { $0.id == id }) { return try campaignJSON(item) }
        case .assumption:
            if let item = assumptions.first(where: { $0.id == id }) { return try campaignJSON(item) }
        }
        throw CampaignError.invalid("Agency citation target does not exist in this campaign.")
    }
}

private func campaignAgencyDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
private func campaignAgencyNote(_ value: String, label: String, maximumBytes: Int = 16 * 1_024) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= maximumBytes else {
        throw CampaignError.invalid("Provide an agency \(label) within the supported text limit.")
    }
}
private func campaignAgencyDate(_ date: Date) throws {
    guard date.timeIntervalSinceReferenceDate.isFinite else { throw CampaignError.invalid("Agency evidence requires a finite date.") }
}

// Agency evidence is derived from the frozen/current campaign draft, keeping old
// ledgers byte-shape compatible and historical baselines self-contained.
extension CampaignSourceSnapshot {
    static func agency(_ draft: CampaignDraft) throws -> [Self] {
        guard let workspace = draft.agency else { return [] }
        var result: [Self] = []
        for revision in workspace.latestRevisions {
            result.append(.init(sourceKind: .agencyDocument, sourceID: revision.documentID, fields: [
                "Filename": revision.filename, "Revision ID": revision.id.uuidString,
                "Prior revision ID": revision.priorRevisionID?.uuidString ?? "",
                "Imported at": try campaignJSON(revision.importedAt),
                "Bytes": String(revision.bytes.count), "SHA256": revision.sha256,
                "Text": revision.text,
                "Human review": try campaignJSON(workspace.currentReview(revisionID: revision.id)),
                "Original format": revision.origin?.format ?? "plain UTF-8",
                "Original SHA256": revision.origin?.originalSHA256 ?? revision.sha256,
                "Original bytes": String(revision.origin?.originalBytes.count ?? revision.bytes.count),
                "Extractor": revision.origin?.extractor ?? "exact-utf8-v1",
                "Extraction sections": String(revision.origin?.sections.count ?? 1),
                "Extraction notices": (revision.origin?.notices ?? []).joined(separator: "\n")
            ], linkedShotIDs: [], linkedElementIDs: []))
        }
        for citation in workspace.citations {
            let revision = workspace.revisions.first { $0.id == citation.revisionID }
            result.append(.init(sourceKind: .agencyCitation, sourceID: citation.id, fields: [
                "Target kind": citation.targetKind.rawValue, "Target ID": citation.targetID.uuidString,
                "Evidence": try campaignJSON(citation),
                "Excerpt": try revision?.excerpt(firstLine: citation.firstLine, lastLine: citation.lastLine) ?? "Missing revision"
            ], linkedShotIDs: [], linkedElementIDs: []))
        }
        return result
    }
}
