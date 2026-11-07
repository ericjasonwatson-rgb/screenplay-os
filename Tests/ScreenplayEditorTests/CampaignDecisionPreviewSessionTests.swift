import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign approval preview persistence")
struct CampaignDecisionPreviewSessionTests {
    private struct Fixture {
        let session: CampaignWorkspaceSession
        let document: ScreenplayOSDocument
        let baselineID: UUID
        let root: URL
        let url: URL
    }

    @MainActor private func fixture() throws -> Fixture {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        let screenplay = Screenplay(metadata: .init(title: "Synthetic approval"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic approval", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        session.updateDraft {
            $0.brief.brand = "Synthetic brand"; $0.brief.objective = "Synthetic objective"
            $0.deliverables = [.init(name: "Synthetic hero")]
        }
        let baselineID = try #require(session.freeze(name: "Synthetic baseline A", document: document))
        let url = try CampaignWorkspaceStore.url(projectID: document.project.id, root: root)
        return .init(session: session, document: document, baselineID: baselineID, root: root, url: url)
    }

    @MainActor private func preview(_ f: Fixture) throws -> CampaignDecisionPreview {
        try #require(f.session.previewDecision(baselineID: f.baselineID, scope: .creative,
            approver: "Cafe\u{0301} reviewer", evidence: "Caf\u{00E9}\r\nExact synthetic evidence",
            document: f.document, amount: "", currency: ""))
    }

    @MainActor @Test func successPersistsExactProposalOnceAndNeverAddsDraftUndo() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let before = f.session.ledger, bytes = try Data(contentsOf: f.url)
        let undoBefore = f.session.canUndoDraft
        let pending = try preview(f)
        #expect(try Data(contentsOf: f.url) == bytes)
        #expect(f.session.ledger == before)
        let confirmationStarted = Date()
        #expect(f.session.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
        #expect(f.session.ledger.decisions[0].createdAt >= confirmationStarted)
        #expect(f.session.ledger.decisions[0].createdAt <= Date())
        #expect(f.session.decisionPreview == nil)
        #expect(f.session.ledger.decisions.map(\.id) == [pending.decision.id])
        #expect(f.session.ledger.decisions[0].evidence.utf8.elementsEqual(pending.decision.evidence.utf8))
        #expect(f.session.ledger.baselines == before.baselines)
        #expect(f.session.ledger.draft == before.draft)
        #expect(f.session.canUndoDraft == undoBefore)
        #expect(!f.session.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(reopened.ledger == f.session.ledger)
        #expect(reopened.decisionPreview == nil)
        #expect(!reopened.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
        f.session.undoDraft()
        #expect(f.session.ledger.decisions.map(\.id) == [pending.id])
        #expect(f.session.ledger.baselines == before.baselines)
        #expect(!f.session.canUndoDraft)
    }

    @MainActor @Test func failedWriteRetainsPreviewBytesAndUndoHistoryForExplicitRetry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), before = f.session.ledger, bytes = try Data(contentsOf: f.url)
        let undoBefore = f.session.canUndoDraft
        let lock = f.url.deletingLastPathComponent().appendingPathComponent(".campaign.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        #expect(!f.session.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
        #expect(f.session.problem != nil)
        #expect(f.session.ledger == before)
        #expect(try Data(contentsOf: f.url) == bytes)
        #expect(f.session.canUndoDraft == undoBefore)
        #expect(f.session.decisionPreview?.id == pending.id)
        try FileManager.default.removeItem(at: lock)
        let retryStarted = Date()
        #expect(f.session.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
        #expect(f.session.ledger.decisions[0].createdAt >= retryStarted)
        #expect(f.session.ledger.decisions[0].createdAt <= Date())
        #expect(f.session.ledger.decisions.map(\.id) == [pending.id])
        #expect(f.session.decisionPreview == nil)
        f.session.undoDraft()
        #expect(f.session.ledger.draft == CampaignDraft())
        #expect(f.session.ledger.decisions.map(\.id) == [pending.id])
    }

    @MainActor @Test func leaseConflictNeverOverwritesAnotherWritersDecisionOrRecapturesPreview() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), original = f.session.ledger
        let writer = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(writer.record(baselineID: f.baselineID, scope: .production, approver: "Synthetic producer",
            evidence: "New decision", document: f.document, amount: "", currency: ""))
        let winningBytes = try Data(contentsOf: f.url)
        for _ in 0..<2 {
            #expect(!f.session.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
            #expect(f.session.ledger == original)
            #expect(f.session.decisionPreview?.id == pending.id)
            #expect(try Data(contentsOf: f.url) == winningBytes)
        }
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(reopened.ledger == writer.ledger)
        #expect(!reopened.confirmDecision(pending, baselineID: f.baselineID, document: f.document))
    }

    @MainActor @Test func discardedReplacedWrongBaselineAndStaleProposalsCannotConfirm() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let second = try #require(f.session.freeze(name: "Synthetic baseline B", document: f.document))
        let first = try preview(f)
        #expect(!f.session.confirmDecision(first, baselineID: second, document: f.document))
        f.session.discardDecisionPreview()
        #expect(!f.session.confirmDecision(first, baselineID: f.baselineID, document: f.document))
        let replacement = try preview(f)
        #expect(replacement.id != first.id)
        #expect(!f.session.confirmDecision(first, baselineID: f.baselineID, document: f.document))
        f.session.updateDraft { $0.brief.objective = "Changed" }
        let before = f.session.ledger
        #expect(!f.session.confirmDecision(replacement, baselineID: f.baselineID, document: f.document))
        #expect(f.session.ledger == before)
        #expect(f.session.ledger.decisions.isEmpty)
    }

    @MainActor @Test func invalidNewPreviewDiscardsOldAndSpendParsingIsExact() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let prior = try preview(f)
        for amount in ["", "-1", "1.25", "9223372036854775808"] {
            #expect(f.session.previewDecision(baselineID: f.baselineID, scope: .spend, approver: "Reviewer",
                evidence: "Evidence", document: f.document, amount: amount, currency: "USD") == nil)
            #expect(f.session.decisionPreview == nil)
        }
        #expect(!f.session.confirmDecision(prior, baselineID: f.baselineID, document: f.document))
        let spend = try #require(f.session.previewDecision(baselineID: f.baselineID, scope: .spend,
            approver: "Reviewer", evidence: "Evidence", document: f.document, amount: "12500", currency: "usd"))
        #expect(spend.decision.spendCeilingMinorUnits == 12500)
        #expect(spend.decision.currencyCode == "USD")
        #expect(f.session.confirmDecision(spend, baselineID: f.baselineID, document: f.document))
    }
}
