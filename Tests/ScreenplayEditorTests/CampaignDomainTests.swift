import Foundation
import Testing
@testable import ScreenplayDomain

struct CampaignDomainTests {
    private func fixture() -> (ScreenplayOSDocument, CampaignLedger) {
        let element = ScreenplayElement(type: .action, text: "A product turns in sunlight.")
        let screenplay = Screenplay(metadata: .init(title: "Campaign test"), elements: [element])
        let shot = Shot(label: "Hero", sourceRefs: [.init(screenplayElementID: element.id)])
        var board = BoardFrame(shotID: shot.id, sceneSpineID: "", frameNumber: 1, label: "Hero board")
        let image = BoardImageVersion(fileURL: URL(fileURLWithPath: "/private/local-assets/secret.png"), sha256: String(repeating: "a", count: 64), prompt: "", model: "local")
        board.imageVersions = [image]; board.selectedImageID = image.id
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Campaign test", author: ""), screenplayID: screenplay.id), screenplay: screenplay, shots: [shot], boardFrames: [board])
        let draft = CampaignDraft(brief: .init(brand: "Sample", objective: "Launch", audience: "Viewers", keyMessage: "Light", mandatoryRequirements: "End card"), deliverables: [.init(name: "Hero film", linkedShotIDs: [shot.id])], assumptions: [.init(text: "One location", sourceLabel: "Client brief", sourceReference: "Section 2")])
        return (document, CampaignLedger(projectID: document.project.id, draft: draft))
    }

    @Test func freezeIsImmutableLocalSnapshotAndDoesNotApproveAnything() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "First review", document: document)
        let encoded = try JSONEncoder().encode(ledger)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("/private/local-assets"))
        #expect(try JSONDecoder().decode(CampaignLedger.self, from: encoded) == ledger)
        #expect(ledger.decisions.isEmpty)
        ledger.draft.brief.objective = "Changed"
        document.screenplay.elements[0].text = "Changed script"
        #expect(ledger.baselines[0] == baseline)
        let changes = try ledger.compare(baselineID: baseline.id, document: document)
        #expect(changes.contains { $0.sourceKind == .brief })
        #expect(changes.contains { $0.sourceKind == .script })
        #expect(changes.allSatisfy(\.requiresHumanReview))
        #expect(changes.allSatisfy { $0.affectedDeliverableIDs == ledger.draft.deliverables.map(\.id) })
    }

    @Test func catchesExactScriptShotBoardTimingAndImageChanges() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Bid basis", document: document)
        #expect(try ledger.compare(baselineID: baseline.id, document: document).isEmpty)
        document.screenplay.elements[0].text += " Again."
        document.shots[0].notes = "New setup"
        document.boardFrames[0].durationSeconds = 8
        document.boardFrames[0].imageVersions[0].sha256 = String(repeating: "b", count: 64)
        let first = try ledger.compare(baselineID: baseline.id, document: document)
        #expect(Set(first.map(\.sourceKind)) == [.script, .shot, .board])
        #expect(first == (try ledger.compare(baselineID: baseline.id, document: document)))
        #expect(first.first { $0.sourceKind == .board }?.after.contains("8.0") == true)
        #expect(first.first { $0.sourceKind == .script }?.before.contains("sunlight") == true)
    }

    @Test func unionOfOldAndNewLinksRetainsRemovedDeliverablesAndReportsDanglingLinks() throws {
        var (document, ledger) = fixture()
        let originalID = ledger.draft.deliverables[0].id
        let baseline = try ledger.freeze(name: "Original", document: document)
        ledger.draft.deliverables = [.init(name: "Replacement", linkedShotIDs: [document.shots[0].id])]
        document.shots[0].label = "New hero"
        let changes = try ledger.compare(baselineID: baseline.id, document: document)
        let shotChange = try #require(changes.first { $0.sourceKind == .shot })
        #expect(Set(shotChange.affectedDeliverableIDs) == [originalID, ledger.draft.deliverables[0].id])
        document.shots = []
        let dangling = try ledger.compare(baselineID: baseline.id, document: document)
        #expect(dangling.contains { $0.unresolved && $0.sourceKind == .deliverable })
        #expect(dangling.contains { $0.unresolved && $0.sourceKind == .board })
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Reviewer", evidence: "Reviewed", document: document) }
    }

    @Test func approvalsAreBaselineBoundScopeSeparatedAndRejectStaleState() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Reviewed", document: document)
        let creative = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Creative reviewer", evidence: "Review meeting notes", document: document)
        #expect(creative.baselineID == baseline.id)
        #expect(creative.scope == .creative)
        #expect(creative.spendCeilingMinorUnits == nil)
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Reviewer", evidence: "Notes", document: document, spendCeilingMinorUnits: 100, currencyCode: "USD") }
        let spend = try ledger.recordDecision(baselineID: baseline.id, scope: .spend, approver: "Producer", evidence: "Written approval reference", document: document, spendCeilingMinorUnits: 100, currencyCode: "USD")
        #expect(spend.scope == .spend)
        #expect(ledger.decisions.count == 2)
        document.boardFrames[0].durationSeconds += 1
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .production, approver: "Producer", evidence: "Reviewed", document: document) }
        #expect(ledger.decisions.count == 2)
        #expect(try JSONDecoder().decode(CampaignLedger.self, from: JSONEncoder().encode(ledger)) == ledger)
    }

    @Test func rejectsDuplicatesMalformedIDsInvalidDurationsAndWrongProject() throws {
        var (document, ledger) = fixture()
        ledger.draft.deliverables[0].durationSeconds = 0
        #expect(throws: CampaignError.self) { try ledger.freeze(name: "Bad", document: document) }
        ledger.draft.deliverables[0].durationSeconds = 30
        ledger.draft.deliverables.append(ledger.draft.deliverables[0])
        #expect(throws: CampaignError.self) { try ledger.validated() }
        ledger.draft.deliverables.removeLast()
        document.boardFrames[0].durationSeconds = .infinity
        #expect(throws: CampaignError.self) { try ledger.freeze(name: "Bad", document: document) }
        document.boardFrames[0].durationSeconds = 4
        document.shots.append(document.shots[0])
        #expect(throws: CampaignError.self) { try ledger.freeze(name: "Bad", document: document) }
        document.shots.removeLast()
        let json = String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self).replacingOccurrences(of: ledger.projectID.uuidString, with: "not-a-uuid")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CampaignLedger.self, from: Data(json.utf8)) }
        var otherLedger = CampaignLedger(projectID: UUID())
        #expect(throws: CampaignError.self) { try otherLedger.freeze(name: "Wrong project", document: document) }
    }

    @Test func ignoresMediaRelocationButDetectsUnresolvedSelectedImage() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Local", document: document)
        document.boardFrames[0].imageVersions[0].fileURL = URL(fileURLWithPath: "/somewhere/else.png")
        #expect(try ledger.compare(baselineID: baseline.id, document: document).isEmpty)
        document.boardFrames[0].selectedImageID = UUID()
        #expect(try ledger.compare(baselineID: baseline.id, document: document).contains { $0.unresolved })
    }
    @Test func rejectsUnknownVersionDuplicateStoredBaselinesAndIncompleteFreeze() throws {
        let (document, original) = fixture()
        var ledger = original
        _ = try ledger.freeze(name: "Basis", document: document)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        object["version"] = 2
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CampaignLedger.self, from: JSONSerialization.data(withJSONObject: object)) }
        object["version"] = 1
        let baselines = try #require(object["baselines"] as? [[String: Any]])
        object["baselines"] = baselines + baselines
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CampaignLedger.self, from: JSONSerialization.data(withJSONObject: object)) }
        var empty = CampaignLedger(projectID: document.project.id)
        #expect(throws: CampaignError.self) { try empty.freeze(name: "Incomplete", document: document) }
        #expect(empty.baselines.isEmpty)
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: ledger.baselines[0].id, scope: .spend, approver: "Producer", evidence: "Notes", document: document) }
    }

    @Test func exactUnicodeAndBoardOnlyScriptLinksAreTracked() throws {
        var (document, ledger) = fixture()
        document.shots[0].sourceRefs = []
        document.boardFrames[0].sourceRefs = [.init(screenplayElementID: document.screenplay.elements[0].id)]
        document.screenplay.elements[0].text = "Caf\u{00E9}"
        let baseline = try ledger.freeze(name: "Unicode", document: document)
        document.screenplay.elements[0].text = "Cafe\u{0301}"
        let changes = try ledger.compare(baselineID: baseline.id, document: document)
        let script = try #require(changes.first { $0.sourceKind == .script })
        #expect(script.affectedDeliverableIDs == ledger.draft.deliverables.map(\.id))
    }

    @Test func malformedShotAndBoardRangesCannotBeApprovedAfterFreeze() throws {
        let badRanges: [(Int?, Int?)] = [(-1, 2), (3, 2), (nil, 2), (0, nil), (0, Int.max)]
        for (start, end) in badRanges {
            for useBoard in [false, true] {
                var (document, ledger) = fixture()
                let ref = ShotSourceRef(screenplayElementID: document.screenplay.elements[0].id, startOffset: start, endOffset: end)
                if useBoard { document.boardFrames[0].sourceRefs = [ref] }
                else { document.shots[0].sourceRefs = [ref] }
                let baseline = try ledger.freeze(name: "Needs review", document: document)
                let changes = try ledger.compare(baselineID: baseline.id, document: document)
                #expect(changes.contains { $0.unresolved && $0.after.lowercased().contains("source range") })
                #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Reviewer", evidence: "Notes", document: document) }
                #expect(ledger.decisions.isEmpty)
            }
        }
    }

    @Test func wholeElementReferencesAreApprovableButUnverifiedLegacyRangesNeedReview() throws {
        var (document, ledger) = fixture()
        document.screenplay.elements[0].text = "A😀B"
        document.shots[0].sourceRefs = [.init(screenplayElementID: document.screenplay.elements[0].id)]
        document.boardFrames[0].sourceRefs = [.init(screenplayElementID: document.screenplay.elements[0].id)]
        let baseline = try ledger.freeze(name: "Whole element references", document: document)
        #expect(try ledger.compare(baselineID: baseline.id, document: document).isEmpty)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Reviewer", evidence: "Notes", document: document)
        document.boardFrames[0].sourceRefs[0].startOffset = 1
        document.boardFrames[0].sourceRefs[0].endOffset = 3
        let rangedBaseline = try ledger.freeze(name: "Unverified range", document: document)
        #expect(try ledger.compare(baselineID: rangedBaseline.id, document: document).contains { $0.unresolved && $0.after.contains("offset units unspecified") })
        #expect(throws: CampaignError.self) { try ledger.recordDecision(baselineID: rangedBaseline.id, scope: .creative, approver: "Reviewer", evidence: "Notes", document: document) }
    }

    @Test func refusesMismatchedProjectScreenplayIdentity() throws {
        var (document, ledger) = fixture()
        document.project.screenplayID = UUID()
        #expect(throws: CampaignError.self) { try CampaignSourceSnapshot.capture(document) }
        #expect(throws: CampaignError.self) { try ledger.freeze(name: "Wrong screenplay", document: document) }
        #expect(ledger.baselines.isEmpty)
    }

}
