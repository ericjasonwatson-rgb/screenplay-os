import Foundation
import Testing
@testable import ScreenplayDomain

struct CampaignAgencyTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() -> (ScreenplayOSDocument, CampaignLedger) {
        let screenplay = Screenplay(metadata: .init(title: "Agency test"), elements: [ScreenplayElement(type: .action, text: "Local screenplay.")])
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Agency test", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        let draft = CampaignDraft(brief: .init(brand: "Sample", objective: "Launch"),
            deliverables: [.init(name: "Hero"), .init(name: "Cut-down", durationSeconds: 15)],
            assumptions: [.init(text: "One location")])
        return (document, CampaignLedger(projectID: document.project.id, draft: draft))
    }

    private func reviewed(_ draft: inout CampaignDraft, text: String = "Hero is 30 seconds.\r\nOne location.\n") throws -> CampaignAgencyRevision {
        let revision = try draft.importAgencyText(data: Data(text.utf8), filename: "agency.txt", at: timestamp)
        _ = try draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Producer", note: "Compared the imported brief with the campaign.", at: timestamp)
        return revision
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func decodeWorkspace(_ object: [String: Any]) throws -> CampaignAgencyWorkspace {
        try JSONDecoder().decode(CampaignAgencyWorkspace.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func exactUTF8BOMAndLineCoordinatesArePreserved() throws {
        var (_, ledger) = fixture()
        let text = "\u{FEFF}Caf\u{0065}\u{0301}\r\nSecond 😀\n\rThird\u{2028}literal\r"
        let revision = try ledger.draft.importAgencyText(data: Data(text.utf8), filename: "agency.txt", at: timestamp)
        #expect(revision.bytes == Data(text.utf8))
        #expect(revision.text.utf8.elementsEqual(text.utf8))
        #expect(revision.lines.count == 3)
        #expect(revision.lines[0].utf8.elementsEqual("\u{FEFF}Cafe\u{0301}".utf8))
        #expect(revision.lines[1] == "Second 😀")
        #expect(revision.lines[2] == "\rThird\u{2028}literal\r")
        #expect(try revision.excerpt(firstLine: 1, lastLine: 2).utf8.elementsEqual("\u{FEFF}Cafe\u{0301}\nSecond 😀".utf8))
        #expect(throws: CampaignError.self) { try revision.excerpt(firstLine: 0, lastLine: 1) }
        #expect(throws: CampaignError.self) { try revision.excerpt(firstLine: 2, lastLine: 1) }
        #expect(throws: CampaignError.self) { try revision.excerpt(firstLine: 1, lastLine: Int.max) }
        let decoded = try JSONDecoder().decode(CampaignLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded.draft.agency?.revisions[0].bytes == revision.bytes)
        #expect(decoded.draft.agency?.revisions[0].text.utf8.elementsEqual(text.utf8) == true)
    }

    @Test func digestCoversRawBytesAndTerminalNewlinesHaveAnEmptyLine() throws {
        var draft = CampaignDraft()
        let abc = try draft.importAgencyText(data: Data("abc".utf8), filename: "abc.txt")
        #expect(abc.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let composed = try draft.importAgencyText(data: Data("Café\n".utf8), filename: "composed.txt")
        let decomposed = try draft.importAgencyText(data: Data("Cafe\u{0301}\n".utf8), filename: "decomposed.txt")
        #expect(composed.text == decomposed.text)
        #expect(composed.sha256 != decomposed.sha256)
        #expect(composed.lines == ["Café", ""])
        let crlf = try draft.importAgencyText(data: Data("Café\r\n".utf8), filename: "crlf.txt")
        #expect(crlf.lines == composed.lines)
        #expect(crlf.sha256 != composed.sha256)
    }

    @Test func badUTF8EmptyOversizedPathsAndUnknownAncestryAreAtomicFailures() throws {
        var draft = CampaignDraft()
        for data in [Data(), Data([0xFF]), Data([0xC0, 0xAF]), Data([0]), Data(repeating: 65, count: CampaignAgencyWorkspace.maximumSourceBytes + 1)] {
            #expect(throws: CampaignError.self) { try draft.importAgencyText(data: data, filename: "agency.txt") }
            #expect(draft.agency == nil)
        }
        for name in ["/private/agency.txt", "../agency.txt", "C:\\agency.txt", "..", "", "a\nb.txt"] {
            #expect(throws: CampaignError.self) { try draft.importAgencyText(data: Data("A".utf8), filename: name) }
            #expect(draft.agency == nil)
        }
        #expect(throws: CampaignError.self) { try draft.importAgencyText(data: Data("A".utf8), filename: "a.txt", revisingDocumentID: UUID()) }
        let valid = try draft.importAgencyText(data: Data(repeating: 65, count: CampaignAgencyWorkspace.maximumSourceBytes), filename: "large.txt")
        #expect(valid.bytes.count == CampaignAgencyWorkspace.maximumSourceBytes)
    }

    @Test func malformedDigestTextAndRevisionChainsAreRejected() throws {
        var draft = CampaignDraft()
        let first = try reviewed(&draft)
        _ = try draft.importAgencyText(data: Data("New".utf8), filename: "agency-v2.txt", revisingDocumentID: first.documentID, at: timestamp)
        let original = try json(try #require(draft.agency))
        let revisions = try #require(original["revisions"] as? [[String: Any]])
        for field in ["sha256", "text", "filename", "documentID", "priorRevisionID"] {
            var broken = original
            var rows = revisions
            switch field {
            case "sha256": rows[1][field] = String(repeating: "0", count: 64)
            case "text": rows[1][field] = "Different text"
            case "filename": rows[1][field] = "/private/file.txt"
            default: rows[1][field] = UUID().uuidString
            }
            broken["revisions"] = rows
            #expect(throws: (any Error).self) { try decodeWorkspace(broken) }
        }
        var duplicated = original; duplicated["revisions"] = revisions + [revisions[0]]
        #expect(throws: (any Error).self) { try decodeWorkspace(duplicated) }
        var reordered = original; reordered["revisions"] = Array(revisions.reversed())
        #expect(throws: (any Error).self) { try decodeWorkspace(reordered) }
        var rootLost = original; rootLost["revisions"] = [revisions[1]]
        #expect(throws: (any Error).self) { try decodeWorkspace(rootLost) }
    }

    @Test func newRevisionKeepsHistoryAndRequiresFreshReviewAndReconciliation() throws {
        var (document, ledger) = fixture()
        let first = try reviewed(&ledger.draft)
        let target = ledger.draft.deliverables[0].id
        let citation = try ledger.draft.citeAgencyRevision(revisionID: first.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: "Duration agreed.", at: timestamp)
        let baseline = try ledger.freeze(name: "Reviewed", document: document)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Director", evidence: "Local review", document: document)
        let second = try ledger.draft.importAgencyText(data: Data("Hero is now 45 seconds.\n".utf8), filename: "agency-v2.txt", revisingDocumentID: first.documentID, at: timestamp.addingTimeInterval(-60))
        #expect(second.documentID == first.documentID)
        #expect(second.priorRevisionID == first.id)
        #expect(ledger.draft.agency?.revisions.count == 2)
        #expect(ledger.draft.agency?.revisions[0] == first)
        #expect(ledger.draft.agency?.latestRevision(documentID: first.documentID)?.id == second.id)
        #expect(ledger.draft.agency?.currentReview(revisionID: first.id) == nil)
        #expect(ledger.draft.agency?.warnings(draft: ledger.draft).count == 2)
        #expect(ledger.baselines[0] == baseline)
        #expect(throws: CampaignError.self) { try ledger.draft.reviewAgencyRevision(revisionID: first.id, reviewer: "Producer", note: "Old") }
        #expect(throws: CampaignError.self) { try ledger.draft.citeAgencyRevision(revisionID: second.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: "Unreviewed") }
        _ = try ledger.draft.reviewAgencyRevision(revisionID: second.id, reviewer: "Producer", note: "Considered duration update.")
        let stale = try ledger.freeze(name: "Still needs reconciliation", document: document)
        #expect(try ledger.compare(baselineID: stale.id, document: document).contains { $0.unresolved && $0.sourceKind == .agencyCitation })
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: stale.id, scope: .production, approver: "Producer", evidence: "Review", document: document) }
        try ledger.draft.removeAgencyCitation(id: citation.id)
        _ = try ledger.draft.citeAgencyRevision(revisionID: second.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: "Keep current duration pending negotiation.")
        let current = try ledger.freeze(name: "Reconciled", document: document)
        #expect(try ledger.compare(baselineID: current.id, document: document).isEmpty)
        _ = try ledger.recordDecision(baselineID: current.id, scope: .production, approver: "Producer", evidence: "Review", document: document)
        #expect(ledger.decisions.count == 2)
        #expect(try JSONDecoder().decode(CampaignLedger.self, from: JSONEncoder().encode(ledger)) == ledger)
        document.screenplay.elements[0].text = "Still independent."
        #expect(ledger.draft.agency?.latestRevision(documentID: first.documentID)?.text == second.text)
    }

    @Test func importAndReviewChangesInvalidatePriorApprovalsWithoutApprovingAnything() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Before import", document: document)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Director", evidence: "Review", document: document)
        let revision = try ledger.draft.importAgencyText(data: Data("New mandatory requirement".utf8), filename: "new.txt")
        let changed = try ledger.compare(baselineID: baseline.id, document: document)
        #expect(changed.contains { $0.sourceKind == .agencyDocument && !$0.unresolved })
        #expect(changed.contains { $0.sourceKind == .agencyDocument && $0.unresolved })
        #expect(ledger.decisions.count == 1)
        let unreviewed = try ledger.freeze(name: "Unreviewed", document: document)
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: unreviewed.id, scope: .creative, approver: "Director", evidence: "Review", document: document) }
        _ = try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Producer", note: "Requirements considered.")
        #expect(ledger.decisions.count == 1)
        let reviewed = try ledger.freeze(name: "Reviewed", document: document)
        #expect(try ledger.compare(baselineID: reviewed.id, document: document).isEmpty)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Second producer", note: "More review.")
        #expect(try ledger.compare(baselineID: reviewed.id, document: document).contains { $0.sourceKind == .agencyDocument })
        #expect(ledger.draft.agency?.reviews.count == 2)
        #expect(document.screenplay.elements[0].text == "Local screenplay.")
    }

    @Test func editedOrRemovedTargetsStayUnresolvedAndCitationRemovalMapsOriginalTarget() throws {
        var (document, ledger) = fixture()
        let revision = try reviewed(&ledger.draft)
        let target = ledger.draft.deliverables[0].id
        let citation = try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: "Duration checked.")
        let baseline = try ledger.freeze(name: "Cited", document: document)
        ledger.draft.deliverables[0].name = "Edited hero"
        #expect(ledger.draft.agency?.warnings(draft: ledger.draft).contains { $0.message.contains("target changed") } == true)
        let edited = try ledger.freeze(name: "Target edited", document: document)
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: edited.id, scope: .creative, approver: "Director", evidence: "Review", document: document) }
        ledger.draft.deliverables.removeFirst()
        #expect(ledger.draft.agency?.warnings(draft: ledger.draft).contains { $0.message.contains("removed") && $0.affectedDeliverableIDs == [target] } == true)
        let missing = try ledger.freeze(name: "Target removed", document: document)
        #expect(try ledger.compare(baselineID: missing.id, document: document).contains { $0.unresolved && $0.affectedDeliverableIDs == [target] })
        try ledger.draft.removeAgencyCitation(id: citation.id)
        let removed = try #require(try ledger.compare(baselineID: baseline.id, document: document).first { $0.sourceKind == .agencyCitation })
        #expect(removed.affectedDeliverableIDs == [target])
        #expect(removed.after == "Not present")
        #expect(ledger.baselines[0].draft.agency?.citations == [citation])
        #expect(throws: CampaignError.self) { try ledger.draft.removeAgencyCitation(id: citation.id) }
    }

    @Test func assumptionEvidenceAffectsAllDeliverablesAndExactTargetText() throws {
        var (document, ledger) = fixture()
        ledger.draft.assumptions[0].text = "Café"
        let revision = try reviewed(&ledger.draft)
        let target = ledger.draft.assumptions[0].id
        _ = try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 2, lastLine: 2, targetKind: .assumption, targetID: target, note: "Location assumption checked.")
        let baseline = try ledger.freeze(name: "Assumption", document: document)
        ledger.draft.assumptions[0].text = "Cafe\u{0301}"
        let changes = try ledger.compare(baselineID: baseline.id, document: document)
        let warning = try #require(changes.first { $0.unresolved && $0.sourceKind == .agencyCitation })
        #expect(Set(warning.affectedDeliverableIDs) == Set(ledger.draft.deliverables.map(\.id)))
    }

    @Test func invalidCitationsAndReviewNotesDoNotPartiallyMutateWorkspace() throws {
        var (_, ledger) = fixture()
        let revision = try ledger.draft.importAgencyText(data: Data("A\nB".utf8), filename: "brief.txt")
        let target = ledger.draft.deliverables[0].id
        #expect(throws: CampaignError.self) { try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: "No review") }
        #expect(throws: CampaignError.self) { try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: " ", note: "Note") }
        #expect(throws: CampaignError.self) { try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Producer", note: " ") }
        #expect(ledger.draft.agency?.reviews.isEmpty == true)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Producer", note: "Read.")
        for bounds in [(0, 1), (2, 1), (1, 3), (1, Int.max)] {
            #expect(throws: CampaignError.self) { try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: bounds.0, lastLine: bounds.1, targetKind: .deliverable, targetID: target, note: "Range") }
        }
        #expect(throws: CampaignError.self) { try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: UUID(), note: "Unknown") }
        #expect(throws: CampaignError.self) { try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: target, note: " ") }
        #expect(ledger.draft.agency?.citations.isEmpty == true)
    }

    @Test func malformedReviewsCitationsAndDuplicateAnnotationsAreRejected() throws {
        var (_, ledger) = fixture()
        let revision = try reviewed(&ledger.draft)
        _ = try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: ledger.draft.deliverables[0].id, note: "Checked")
        let original = try json(try #require(ledger.draft.agency))
        for collection in ["reviews", "citations"] {
            let rows = try #require(original[collection] as? [[String: Any]])
            var duplicate = original; duplicate[collection] = rows + rows
            #expect(throws: (any Error).self) { try decodeWorkspace(duplicate) }
            var unknown = original; var changed = rows; changed[0]["revisionID"] = UUID().uuidString; unknown[collection] = changed
            #expect(throws: (any Error).self) { try decodeWorkspace(unknown) }
        }
        let citations = try #require(original["citations"] as? [[String: Any]])
        for field in ["lastLine", "documentID", "targetSnapshot", "targetID", "note"] {
            var broken = original; var changed = citations
            switch field {
            case "lastLine": changed[0][field] = Int.max
            case "targetSnapshot": changed[0][field] = "{}"
            case "note": changed[0][field] = ""
            default: changed[0][field] = UUID().uuidString
            }
            broken["citations"] = changed
            #expect(throws: (any Error).self) { try decodeWorkspace(broken) }
        }
    }

    @Test func oldVersionOneLedgersOmitAbsentAgencyAcrossDraftAndBaselines() throws {
        var (document, ledger) = fixture()
        _ = try ledger.freeze(name: "Old format", document: document)
        let before = try json(ledger)
        let beforeDraft = try #require(before["draft"] as? [String: Any])
        #expect(beforeDraft["agency"] == nil)
        let encoded = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(CampaignLedger.self, from: encoded)
        #expect(decoded.version == 1)
        #expect(decoded.draft.agency == nil)
        #expect(decoded.baselines[0].draft.agency == nil)
        let after = try json(decoded)
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
        #expect(try ledger.compare(baselineID: ledger.baselines[0].id, document: document).isEmpty)
    }

    @Test func identicalReimportAndEvidenceRemovalStillInvalidateAnApprovedBaseline() throws {
        var (document, ledger) = fixture()
        let first = try reviewed(&ledger.draft)
        let baseline = try ledger.freeze(name: "Original evidence", document: document)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Director", evidence: "Reviewed", document: document)
        let second = try ledger.draft.importAgencyText(data: first.bytes, filename: first.filename, revisingDocumentID: first.documentID)
        #expect(first.sha256 == second.sha256)
        #expect(first.id != second.id)
        #expect(ledger.draft.agency?.currentReview(revisionID: second.id) == nil)
        #expect(try ledger.compare(baselineID: baseline.id, document: document).contains { $0.sourceKind == .agencyDocument })
        ledger.draft.agency = nil
        let removed = try ledger.compare(baselineID: baseline.id, document: document)
        #expect(removed.contains { $0.sourceKind == .agencyDocument && $0.after == "Not present" })
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .production, approver: "Producer", evidence: "Review", document: document) }
        #expect(ledger.baselines[0].draft.agency?.revisions == [first])
        #expect(ledger.decisions.count == 1)
    }

    @Test func revisionAndTotalByteLimitsFailAtomically() throws {
        var small = CampaignDraft()
        let first = try small.importAgencyText(data: Data("A".utf8), filename: "a.txt")
        for _ in 1..<CampaignAgencyWorkspace.maximumRevisions {
            _ = try small.importAgencyText(data: Data("A".utf8), filename: "a.txt", revisingDocumentID: first.documentID)
        }
        let before = small
        #expect(throws: CampaignError.self) { try small.importAgencyText(data: Data("B".utf8), filename: "a.txt", revisingDocumentID: first.documentID) }
        #expect(small == before)
        var large = CampaignDraft()
        for _ in 0..<4 {
            _ = try large.importAgencyText(data: Data(repeating: 65, count: CampaignAgencyWorkspace.maximumSourceBytes), filename: "large.txt")
        }
        let full = large
        #expect(throws: CampaignError.self) { try large.importAgencyText(data: Data("A".utf8), filename: "a.txt") }
        #expect(large == full)
    }
}
