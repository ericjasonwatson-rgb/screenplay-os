import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign agency document provenance")
struct CampaignAgencyDocumentOriginTests {
    private func origin(text: String = "Hero\n30 seconds", bytes: Data = Data([0x50, 0x4b, 0x03, 0x04]) + Data("synthetic provenance fixture".utf8)) throws -> CampaignAgencyDocumentOrigin {
        try .init(format: "docx", originalBytes: bytes, sections: [text], extractor: "docx-body-text-v1", notices: ["Text extraction needs original-document review. No OCR."])
    }

    private func document() -> ScreenplayOSDocument {
        let script = Screenplay(metadata: .init(title: "Agency"))
        return ScreenplayOSDocument(project: .init(metadata: .init(title: "Agency", author: ""), screenplayID: script.id), screenplay: script)
    }

    @Test func exactOriginalAndExtractedTextRoundtripWithoutChangingTextImportShape() throws {
        let original = try origin(text: "Cafe\u{0301}\r\nSecond")
        var draft = CampaignDraft()
        let plain = try draft.importAgencyText(data: Data("Old source".utf8), filename: "Old.txt")
        let revision = try draft.importAgencyDocument(origin: original, filename: "Agency.docx")
        #expect(revision.origin?.originalBytes == original.originalBytes)
        #expect(revision.origin?.originalSHA256 == original.originalSHA256)
        #expect(revision.bytes == Data(original.text.utf8))
        #expect(revision.text.utf8.elementsEqual(original.text.utf8))
        let encodedPlain = try JSONEncoder().encode(plain)
        #expect(!String(decoding: encodedPlain, as: UTF8.self).contains("\"origin\""))
        let restoredPlain = try JSONDecoder().decode(CampaignAgencyRevision.self, from: encodedPlain)
        #expect(restoredPlain.origin == nil)
        let projectID = UUID()
        let ledger = CampaignLedger(projectID: projectID, draft: draft)
        #expect(try CampaignWorkspaceStore.decode(CampaignWorkspaceStore.encoded(ledger), projectID: projectID) == ledger)
    }

    @Test func originalRevisionChangesInvalidateReviewEvenWhenTextIsIdentical() throws {
        let doc = document()
        var ledger = CampaignLedger(projectID: doc.project.id,
            draft: .init(brief: .init(brand: "Brand", objective: "Launch"), deliverables: [.init(name: "Hero")]))
        let first = try ledger.draft.importAgencyDocument(origin: origin(), filename: "Agency.docx")
        try ledger.draft.reviewAgencyRevision(revisionID: first.id, reviewer: "Producer", note: "Compared source")
        let baseline = try ledger.freeze(name: "Reviewed DOCX", document: doc)
        try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Client", evidence: "Email", document: doc)
        let secondOrigin = try origin(bytes: Data([0x50, 0x4b, 0x03, 0x04]) + Data("new original with same extracted text".utf8))
        let second = try ledger.draft.importAgencyDocument(origin: secondOrigin, filename: "Agency-v2.docx", revisingDocumentID: first.documentID)
        #expect(first.bytes == second.bytes)
        #expect(first.origin?.originalSHA256 != second.origin?.originalSHA256)
        #expect(ledger.draft.agency?.currentReview(revisionID: second.id) == nil)
        #expect(try ledger.compare(baselineID: baseline.id, document: doc).contains { $0.sourceKind == .agencyDocument && $0.unresolved })
        #expect(ledger.baselines[0].draft.agency?.revisions[0].origin?.originalBytes == first.origin?.originalBytes)
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .production, approver: "Producer", evidence: "No source review", document: doc) }
    }

    @Test func provenanceRejectsUnsupportedFormatsExtractorsEmptySectionsAndLimits() throws {
        let valid = try origin()
        #expect(throws: CampaignError.self) { try CampaignAgencyDocumentOrigin(format: "pdf", originalBytes: Data("%PDF-1.7\n".utf8), sections: valid.sections, extractor: "pdfkit-text-v1", notices: valid.notices) }
        #expect(throws: CampaignError.self) { try CampaignAgencyDocumentOrigin(format: "doc", originalBytes: valid.originalBytes, sections: valid.sections, extractor: "docx-body-text-v1", notices: valid.notices) }
        #expect(throws: CampaignError.self) { try CampaignAgencyDocumentOrigin(format: "docx", originalBytes: valid.originalBytes, sections: valid.sections, extractor: "future-extractor", notices: valid.notices) }
        #expect(throws: CampaignError.self) { try origin(text: " ") }
        #expect(throws: CampaignError.self) { try origin(text: String(repeating: "A", count: CampaignAgencyWorkspace.maximumSourceBytes + 1)) }
        #expect(throws: CampaignError.self) { try origin(bytes: Data(repeating: 65, count: CampaignAgencyDocumentOrigin.maximumOriginalBytes + 1)) }
        #expect(throws: CampaignError.self) { try CampaignAgencyDocumentOrigin(format: "docx", originalBytes: valid.originalBytes, sections: Array(repeating: "Body", count: 2), extractor: "docx-body-text-v1", notices: valid.notices) }
        #expect(throws: CampaignError.self) { try CampaignAgencyDocumentOrigin(format: "docx", originalBytes: valid.originalBytes, sections: valid.sections, extractor: "docx-body-text-v1", notices: []) }
    }

    @Test func tamperedOriginalHashTextAndUnknownFieldsRemainProtected() throws {
        let id = UUID()
        var ledger = CampaignLedger(projectID: id)
        try ledger.draft.importAgencyDocument(origin: origin(), filename: "Agency.docx")
        let bytes = try CampaignWorkspaceStore.encoded(ledger)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for field in ["originalSHA256", "sections", "futurePrivateData"] {
            var object = original
            var draft = try #require(object["draft"] as? [String: Any])
            var agency = try #require(draft["agency"] as? [String: Any])
            var revisions = try #require(agency["revisions"] as? [[String: Any]])
            var provenance = try #require(revisions[0]["origin"] as? [String: Any])
            if field == "sections" { provenance[field] = ["Altered extraction"] }
            else { provenance[field] = "Altered or unsupported" }
            revisions[0]["origin"] = provenance; agency["revisions"] = revisions; draft["agency"] = agency; object["draft"] = draft
            #expect(throws: (any Error).self) { try CampaignWorkspaceStore.decode(JSONSerialization.data(withJSONObject: object), projectID: id) }
        }
    }

    @Test func totalOriginalByteLimitFailsAtomically() throws {
        var bytes = Data([0x50, 0x4b, 0x03, 0x04])
        bytes.append(Data(repeating: 65, count: CampaignAgencyDocumentOrigin.maximumOriginalBytes - bytes.count))
        let provenance = try origin(bytes: bytes)
        var draft = CampaignDraft()
        try draft.importAgencyDocument(origin: provenance, filename: "One.docx")
        try draft.importAgencyDocument(origin: provenance, filename: "Two.docx")
        let previous = draft
        #expect(throws: CampaignError.self) { try draft.importAgencyDocument(origin: origin(), filename: "Three.docx") }
        #expect(draft == previous)
    }

    @MainActor @Test func documentImportPersistsBeforePublishAndUndoKeepsBaselineOriginal() throws {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let doc = document(), source = try origin()
        let session = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        session.updateDraft { $0.brief.brand = "Brand"; $0.brief.objective = "Launch"; $0.deliverables = [.init(name: "Hero")] }
        let preview = CampaignAgencyImport.Preview(filename: "Agency.docx", bytes: Data(source.text.utf8), text: source.text, origin: source)
        #expect(session.importAgencyText(preview, revisingDocumentID: nil))
        let first = try #require(session.ledger.draft.agency?.revisions.first)
        #expect(session.reviewAgencyRevision(first.id, reviewer: "Producer", note: "Original compared"))
        let baseline = try #require(session.freeze(name: "Source pinned", document: doc))
        let second = try origin(text: "New extracted text")
        #expect(session.importAgencyText(.init(filename: "New.docx", bytes: Data(second.text.utf8), text: second.text, origin: second), revisingDocumentID: first.documentID))
        session.undoDraft()
        let reopened = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger.draft.agency?.revisions.count == 1)
        #expect(reopened.ledger.baselines.first { $0.id == baseline }?.draft.agency?.revisions.first?.origin?.originalBytes == source.originalBytes)
    }

    @MainActor @Test func mismatchBetweenExtractionAndPreviewCannotImport() throws {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        let preview = CampaignAgencyImport.Preview(filename: "Agency.docx", bytes: Data("Unseen".utf8), text: "Unseen", origin: try origin())
        #expect(!session.importAgencyText(preview, revisingDocumentID: nil))
        #expect(session.ledger.draft.agency == nil)
        #expect(!session.canUndoDraft)
    }

    @Test func cancelledReadCannotOpenOrProduceAnImportPreview() async throws {
        let task = Task { () throws -> CampaignAgencyImport.Preview in
            withUnsafeCurrentTask { $0?.cancel() }
            return try CampaignAgencyImport.read(URL(fileURLWithPath: "/does-not-exist.docx"))
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled import unexpectedly produced a preview") }
        catch is CancellationError { }
    }
}
