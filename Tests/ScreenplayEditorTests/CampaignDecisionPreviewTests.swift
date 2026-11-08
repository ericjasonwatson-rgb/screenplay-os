import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Campaign baseline-bound decision previews")
struct CampaignDecisionPreviewTests {
    private func fixture() throws -> (ScreenplayOSDocument, CampaignLedger, UUID) {
        let element = ScreenplayElement(type: .action, text: "Caf\u{00E9}")
        let screenplay = Screenplay(metadata: .init(title: "Synthetic approval"), elements: [element])
        let shot = Shot(label: "Synthetic hero", sourceRefs: [.init(screenplayElementID: element.id)])
        let board = BoardFrame(shotID: shot.id, sceneSpineID: "", frameNumber: 1, label: "Synthetic board")
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic approval", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay, shots: [shot], boardFrames: [board])
        var ledger = CampaignLedger(projectID: document.project.id, draft: .init(
            brief: .init(brand: "Caf\u{00E9}", objective: "Synthetic launch"),
            deliverables: [.init(name: "Hero", linkedShotIDs: [shot.id])]))
        let revision = try ledger.draft.importAgencyText(data: Data("Synthetic source".utf8), filename: "synthetic.txt")
        _ = try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Synthetic reviewer", note: "Compared original")
        let baseline = try ledger.freeze(name: "Synthetic baseline A", document: document)
        return (document, ledger, baseline.id)
    }

    private func preview(_ ledger: CampaignLedger, _ document: ScreenplayOSDocument, _ id: UUID) throws -> CampaignDecisionPreview {
        try ledger.previewDecision(baselineID: id, scope: .creative, approver: "Cafe\u{0301} reviewer",
            evidence: "Exact\r\nCaf\u{00E9} 👩🏽‍🎨", document: document, at: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func immutablePreviewRecordsExactDecisionOnceWithoutMutatingBaselineOrDraft() throws {
        var (document, ledger, id) = try fixture()
        let before = try campaignJSON(ledger)
        let pending = try preview(ledger, document, id)
        #expect(try campaignJSON(ledger).utf8.elementsEqual(before.utf8))
        let confirmedAt = pending.decision.createdAt.addingTimeInterval(3600)
        let decision = try ledger.confirmDecision(pending, baselineID: id, document: document, at: confirmedAt)
        #expect(decision.id == pending.id)
        #expect(decision.createdAt == confirmedAt)
        #expect(decision.createdAt != pending.decision.createdAt)
        #expect(decision.approver.utf8.elementsEqual(pending.decision.approver.utf8))
        #expect(decision.evidence.utf8.elementsEqual(pending.decision.evidence.utf8))
        #expect(ledger.baselines == [pending.baseline])
        #expect(ledger.draft == pending.baseline.draft)
        #expect(throws: CampaignError.self) { try ledger.confirmDecision(pending, baselineID: id, document: document) }
        #expect(ledger.decisions.count == 1)
        var reopened = try JSONDecoder().decode(CampaignLedger.self, from: JSONEncoder().encode(ledger))
        #expect(throws: CampaignError.self) { try reopened.confirmDecision(pending, baselineID: id, document: document) }
    }

    @Test func nonfiniteConfirmationTimeFailsWithoutConsumingProposal() throws {
        var (document, ledger, id) = try fixture()
        let pending = try preview(ledger, document, id), original = ledger
        for interval in [Double.infinity, -Double.infinity, Double.nan] {
            #expect(throws: CampaignError.self) {
                try ledger.confirmDecision(pending, baselineID: id, document: document,
                    at: Date(timeIntervalSinceReferenceDate: interval))
            }
            #expect(ledger == original)
        }
        let confirmedAt = pending.decision.createdAt.addingTimeInterval(7200)
        let recorded = try ledger.confirmDecision(pending, baselineID: id, document: document, at: confirmedAt)
        #expect(recorded.createdAt == confirmedAt)
        #expect(recorded.id == pending.id)
        #expect(recorded.evidence.utf8.elementsEqual(pending.decision.evidence.utf8))
    }

    @Test func identicalContentBaselinesAndOtherProjectsCannotReceiveTheProposal() throws {
        var (document, ledger, id) = try fixture()
        let second = try ledger.freeze(name: "Synthetic baseline B", document: document)
        let pending = try preview(ledger, document, id)
        #expect(try ledger.compare(baselineID: second.id, document: document).isEmpty)
        #expect(throws: CampaignError.self) { try ledger.confirmDecision(pending, baselineID: second.id, document: document) }
        #expect(ledger.decisions.isEmpty)
        let (otherDocument, otherLedger, _) = try fixture()
        #expect(try !pending.contextMatches(ledger: otherLedger, document: otherDocument))
        #expect(throws: CampaignError.self) { try ledger.confirmDecision(pending, baselineID: id, document: otherDocument) }
    }

    @Test func exactUnicodeDraftScriptShotBoardAndReviewChangesInvalidateWithoutMutation() throws {
        let (document, ledger, id) = try fixture()
        let pending = try preview(ledger, document, id)
        var draftChanged = ledger
        draftChanged.draft.brief.brand = "Cafe\u{0301}"
        #expect(draftChanged.draft.brief.brand == ledger.draft.brief.brand)
        #expect(throws: CampaignError.self) { try draftChanged.confirmDecision(pending, baselineID: id, document: document) }
        for kind in 0..<3 {
            var sourceChanged = document, target = ledger
            switch kind {
            case 0: sourceChanged.screenplay.elements[0].text = "Cafe\u{0301}"
            case 1: sourceChanged.shots[0].notes = "New setup"
            default: sourceChanged.boardFrames[0].durationSeconds += 1
            }
            #expect(try !pending.contextMatches(ledger: target, document: sourceChanged))
            #expect(throws: CampaignError.self) { try target.confirmDecision(pending, baselineID: id, document: sourceChanged) }
            #expect(target == ledger)
        }
        var reviewChanged = ledger
        let revision = try #require(reviewChanged.draft.agency?.revisions.first)
        _ = try reviewChanged.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Synthetic reviewer", note: "New review")
        #expect(try !pending.contextMatches(ledger: reviewChanged, document: document))
        #expect(throws: CampaignError.self) { try reviewChanged.confirmDecision(pending, baselineID: id, document: document) }
        var sourceRevisionChanged = ledger
        _ = try sourceRevisionChanged.draft.importAgencyText(data: Data("Revised synthetic source".utf8),
            filename: "synthetic-v2.txt", revisingDocumentID: revision.documentID)
        #expect(try !pending.contextMatches(ledger: sourceRevisionChanged, document: document))
    }

    @Test func newDecisionOnAnotherBaselineInvalidatesPendingConfirmation() throws {
        var (document, ledger, id) = try fixture()
        let other = try ledger.freeze(name: "Same-content second baseline", document: document)
        let pending = try preview(ledger, document, id)
        _ = try ledger.recordDecision(baselineID: other.id, scope: .production, approver: "Synthetic producer", evidence: "Other record", document: document)
        let prior = ledger
        #expect(throws: CampaignError.self) { try ledger.confirmDecision(pending, baselineID: id, document: document) }
        #expect(ledger == prior)
    }

    @Test func normalizationOnlyChangesToRetainedBaselineOrDecisionHistoryAreStale() throws {
        var (document, ledger, id) = try fixture()
        _ = try ledger.recordDecision(baselineID: id, scope: .production, approver: "Reviewer",
            evidence: "Caf\u{00E9}", document: document)
        let pending = try preview(ledger, document, id)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        for field in ["baseline", "decision"] {
            var object = original
            if field == "baseline" {
                var baselines = try #require(object["baselines"] as? [[String: Any]])
                var draft = try #require(baselines[0]["draft"] as? [String: Any])
                var brief = try #require(draft["brief"] as? [String: Any])
                brief["brand"] = "Cafe\u{0301}"; draft["brief"] = brief
                baselines[0]["draft"] = draft; object["baselines"] = baselines
            } else {
                var decisions = try #require(object["decisions"] as? [[String: Any]])
                decisions[0]["evidence"] = "Cafe\u{0301}"; object["decisions"] = decisions
            }
            var changed = try JSONDecoder().decode(CampaignLedger.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(changed == ledger) // Canonical Unicode equality is insufficient.
            #expect(try !pending.contextMatches(ledger: changed, document: document))
            #expect(throws: CampaignError.self) { try changed.confirmDecision(pending, baselineID: id, document: document) }
            #expect(changed.decisions.count == 1)
        }
    }

    @Test func scopesUseExistingValidationAndOnlySpendHasACeiling() throws {
        var (document, ledger, id) = try fixture()
        for scope in CampaignApprovalScope.allCases {
            let spend = scope == .spend
            let pending = try ledger.previewDecision(baselineID: id, scope: scope, approver: "Synthetic reviewer",
                evidence: "Synthetic evidence", document: document, spendCeilingMinorUnits: spend ? 12500 : nil,
                currencyCode: spend ? "USD" : nil)
            #expect(pending.decision.scope == scope)
            #expect(pending.decision.spendCeilingMinorUnits == (spend ? 12500 : nil))
            _ = try ledger.confirmDecision(pending, baselineID: id, document: document)
        }
        for scope in [CampaignApprovalScope.creative, .production] {
            #expect(throws: CampaignError.self) {
                try ledger.previewDecision(baselineID: id, scope: scope, approver: "Reviewer", evidence: "Evidence",
                    document: document, spendCeilingMinorUnits: 1, currencyCode: "USD")
            }
        }
        for currency in ["usd", "US", "US€"] {
            #expect(throws: CampaignError.self) {
                try ledger.previewDecision(baselineID: id, scope: .spend, approver: "Reviewer", evidence: "Evidence",
                    document: document, spendCeilingMinorUnits: 1, currencyCode: currency)
            }
        }
        #expect(throws: CampaignError.self) {
            try ledger.previewDecision(baselineID: id, scope: .spend, approver: "Reviewer", evidence: "Evidence", document: document)
        }
        #expect(throws: CampaignError.self) {
            try ledger.previewDecision(baselineID: id, scope: .creative, approver: " ", evidence: "Evidence", document: document)
        }
    }
}
