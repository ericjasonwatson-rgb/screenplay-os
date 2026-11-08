import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Campaign exact-byte change report review")
struct CampaignChangeReviewTests {
    private func fixture() throws -> (ScreenplayOSDocument, CampaignLedger, UUID) {
        let element = ScreenplayElement(type: .action, text: "Caf\u{00E9}\r\nCONFIDENTIAL_SCRIPT")
        let screenplay = Screenplay(metadata: .init(title: "Campaign"), elements: [element])
        let shot = Shot(label: "Hero", sourceRefs: [.init(screenplayElementID: element.id)])
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Caf\u{00E9}", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay, shots: [shot])
        var ledger = CampaignLedger(projectID: document.project.id, draft: .init(
            brief: .init(brand: "Brand", objective: "CONFIDENTIAL_BRIEF"),
            deliverables: [.init(name: "Hero", linkedShotIDs: [shot.id])],
            assumptions: [.init(text: "CONFIDENTIAL_ASSUMPTION")]))
        let revision = try ledger.draft.importAgencyText(data: Data("CONFIDENTIAL_AGENCY\r\nCafe\u{0301}".utf8), filename: "source.txt")
        try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Reviewer", note: "CONFIDENTIAL_REVIEW")
        try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 2,
            targetKind: .assumption, targetID: ledger.draft.assumptions[0].id, note: "CONFIDENTIAL_CITATION_NOTE")
        let baseline = try ledger.freeze(name: "Baseline", document: document)
        return (document, ledger, baseline.id)
    }

    @Test func defaultSummaryExcludesAllBeforeAfterCanariesIncludingUnresolved() throws {
        var (document, ledger, id) = try fixture()
        document.screenplay.elements[0].text += " changed"
        ledger.draft.brief.objective += " changed"
        ledger.draft.assumptions[0].text += " changed"
        let revision = try #require(ledger.draft.agency?.revisions.first)
        try ledger.draft.importAgencyText(data: Data("CONFIDENTIAL_NEW_AGENCY".utf8), filename: "new.txt", revisingDocumentID: revision.documentID)
        document.shots = []
        let preview = try ledger.previewChangeReport(baselineID: id, document: document)
        #expect(preview.unresolvedCount > 0)
        for canary in ["CONFIDENTIAL_SCRIPT", "CONFIDENTIAL_BRIEF", "CONFIDENTIAL_ASSUMPTION", "CONFIDENTIAL_AGENCY", "CONFIDENTIAL_NEW_AGENCY", "CONFIDENTIAL_REVIEW", "CONFIDENTIAL_CITATION_NOTE"] {
            #expect(!preview.text.contains(canary))
        }
        #expect(!preview.text.contains("Before evidence"))
        #expect(!preview.options.includeFullEvidence)
        #expect(preview.text.contains("Not automatically redacted"))
        #expect(preview.text.contains("Neither mode is client-safe"))
        #expect(preview.text.contains("Not a quote, approval, or spend authority"))
        #expect(preview.text.contains("Unresolved: YES"))
    }

    @Test func fullEvidenceKeepsEveryExactUTF8PayloadAndExportBytes() throws {
        var (document, ledger, id) = try fixture()
        document.screenplay.elements[0].text = "Cafe\u{0301}\r\n新しい 👩🏽‍🎨"
        let revision = try #require(ledger.draft.agency?.revisions.first)
        try ledger.draft.importAgencyText(data: Data("Exact\r\nCafe\u{0301}\r\n🚀".utf8), filename: "new.txt", revisingDocumentID: revision.documentID)
        let preview = try ledger.previewChangeReport(baselineID: id, document: document, options: .init(includeFullEvidence: true))
        for change in try ledger.compare(baselineID: id, document: document) {
            #expect(preview.data.range(of: Data(change.before.utf8)) != nil)
            #expect(preview.data.range(of: Data(change.after.utf8)) != nil)
        }
        #expect(preview.data.range(of: Data("Cafe\u{0301}\r\n新しい 👩🏽‍🎨".utf8)) != nil)
        #expect(preview.text.contains("CONFIDENTIAL_CITATION_NOTE"))
        #expect(preview.text.contains("CONFIDENTIAL_ASSUMPTION"))
        #expect(preview.data == Data(preview.text.utf8))
        #expect(try preview.validatedData(ledger: ledger, baselineID: id, document: document) == preview.data)
        let next = try ledger.previewChangeReport(baselineID: id, document: document)
        #expect(next.id != preview.id)
    }

    @Test func namesStayQuotedAndDuplicateRenamedDeletedAndUnlinkedImpactsAreClear() throws {
        var (document, ledger, _) = try fixture()
        ledger.draft.deliverables.append(.init(name: "Hero", linkedShotIDs: [document.shots[0].id]))
        let baseline = try ledger.freeze(name: "Baseline\r\nForged heading", document: document)
        let deleted = ledger.draft.deliverables.removeLast()
        let renamedID = ledger.draft.deliverables[0].id
        ledger.draft.deliverables[0].name = "Renamed\nForged heading"
        document.project.metadata.title = "Project\nForged heading"
        document.shots[0].notes = "Changed"
        let preview = try ledger.previewChangeReport(baselineID: baseline.id, document: document)
        #expect(preview.text.contains("current name: \"Renamed\\nForged heading\"; baseline name: \"Hero\""))
        #expect(preview.text.contains("ID: \(deleted.id.uuidString); current name: [not present]; baseline name: \"Hero\""))
        #expect(preview.text.contains(renamedID.uuidString))
        #expect(!preview.text.contains("\nForged heading"))
        #expect(preview.text.contains("Baseline\\r\\nForged heading"))
        document.screenplay.elements.append(.init(type: .action, text: "Unlinked"))
        let unlinked = try ledger.previewChangeReport(baselineID: baseline.id, document: document)
        #expect(unlinked.text.contains("None linked; impact is not established."))
    }

    @Test func wrongProjectAndBaselineFailClosed() throws {
        var (document, ledger, id) = try fixture()
        let second = try ledger.freeze(name: "Second", document: document)
        let preview = try ledger.previewChangeReport(baselineID: id, document: document)
        #expect(throws: CampaignError.self) { try preview.validatedData(ledger: ledger, baselineID: second.id, document: document) }
        let (otherDocument, otherLedger, _) = try fixture()
        #expect(try !preview.contextMatches(ledger: otherLedger, document: otherDocument))
        #expect(throws: CampaignError.self) { try ledger.previewChangeReport(baselineID: id, document: otherDocument) }
        #expect(throws: CampaignError.self) { try ledger.previewChangeReport(baselineID: UUID(), document: document) }
    }

    @Test func titleDraftSourceReviewAndDecisionEditsInvalidateFrozenBytes() throws {
        let (document, ledger, id) = try fixture()
        let preview = try ledger.previewChangeReport(baselineID: id, document: document)
        var changedDocument = document
        changedDocument.project.metadata.title = "Cafe\u{0301}"
        #expect(changedDocument.project.metadata.title == document.project.metadata.title)
        #expect(try !preview.contextMatches(ledger: ledger, document: changedDocument))
        changedDocument = document
        changedDocument.screenplay.elements[0].text = "Cafe\u{0301}\r\nCONFIDENTIAL_SCRIPT"
        #expect(try !preview.contextMatches(ledger: ledger, document: changedDocument))
        var changedLedger = ledger
        changedLedger.draft.brief.objective += " updated"
        #expect(try !preview.contextMatches(ledger: changedLedger, document: document))
        changedLedger = ledger
        let revision = try #require(ledger.draft.agency?.revisions.first)
        try changedLedger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Reviewer", note: "New review")
        #expect(try !preview.contextMatches(ledger: changedLedger, document: document))
        changedLedger = ledger
        try changedLedger.recordDecision(baselineID: id, scope: .creative, approver: "Reviewer", evidence: "New decision", document: document)
        #expect(throws: CampaignError.self) { try preview.validatedData(ledger: changedLedger, baselineID: id, document: document) }
        #expect(try preview.validatedData(ledger: ledger, baselineID: id, document: document) == preview.data)
    }

    @Test func limitsFailWithoutTruncationAndDatesMustBeFinite() throws {
        let (document, ledger, id) = try fixture()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let preview = try ledger.previewChangeReport(baselineID: id, document: document, at: date)
        #expect(preview.generatedAt == date)
        for cap in [0, -1, 1, 2_000_001] {
            #expect(throws: CampaignError.self) { try ledger.previewChangeReport(baselineID: id, document: document, options: .init(maximumUTF8Bytes: cap)) }
        }
        for interval in [Double.nan, .infinity, -.infinity] {
            #expect(throws: CampaignError.self) { try ledger.previewChangeReport(baselineID: id, document: document, at: Date(timeIntervalSinceReferenceDate: interval)) }
        }
        let exact = try ledger.previewChangeReport(baselineID: id, document: document, options: .init(maximumUTF8Bytes: preview.data.count), at: date)
        #expect(exact.data.count == preview.data.count)
        #expect(throws: CampaignError.self) { try ledger.previewChangeReport(baselineID: id, document: document, options: .init(maximumUTF8Bytes: preview.data.count - 1), at: date) }
    }
}
