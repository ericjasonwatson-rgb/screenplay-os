import Foundation
import Testing
@testable import ScreenplayDomain

struct CampaignReviewChecklistTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(linked: Bool = true) -> (ScreenplayOSDocument, CampaignLedger) {
        let element = ScreenplayElement(type: .action, text: "A synthetic product turns in sunlight.")
        let screenplay = Screenplay(metadata: .init(title: "Review checklist test"), elements: [element])
        let shot = Shot(label: "Hero", sourceRefs: [.init(screenplayElementID: element.id)])
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Review checklist test", author: ""), screenplayID: screenplay.id), screenplay: screenplay, shots: [shot])
        let draft = CampaignDraft(brief: .init(brand: "Sample", objective: "Launch"),
            deliverables: [.init(name: "Hero film", linkedShotIDs: linked ? [shot.id] : [])],
            assumptions: [.init(text: "One location", sourceLabel: "Manual brief", sourceReference: "Version 2, page 3")])
        return (document, CampaignLedger(projectID: document.project.id, draft: draft))
    }

    private func item(_ destination: CampaignReviewDestination,
                      in checklist: CampaignReviewChecklist) throws -> CampaignReviewChecklistItem {
        try #require(checklist.items.first { $0.destination == destination })
    }

    private func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    @Test func blankCampaignGivesConcreteFieldsAndKeepsAgencySourcesOptional() throws {
        let (document, _) = fixture()
        let ledger = CampaignLedger(projectID: document.project.id)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(result.nextStep.destination == .brief)
        #expect(result.missingBaselineFields == ["Enter the brand.", "Enter the campaign objective.", "Add at least one deliverable."])
        #expect(result.items.map(\.id) == ["brief", "agencySources", "coverage", "assumptions", "baseline", "decisions", "report"])
        #expect(try !item(.agencySources, in: result).needsAttention)
        #expect(try item(.agencySources, in: result).summary.contains("Manual references"))
        #expect(result.changes == nil)
        #expect(result.changeCount == nil)
        #expect(result.unresolvedCount == nil)
        #expect(result.decisionRecords == nil)
    }

    @Test func partialBriefNamesEveryBlankFieldWithoutTrimmingAuthoredData() throws {
        var (document, ledger) = fixture()
        ledger.draft.brief.brand = " \n\t"
        ledger.draft.brief.objective = "  Keep exact spacing  "
        ledger.draft.deliverables[0].name = "\n"
        ledger.draft.deliverables[0].aspectRatio = " \t"
        ledger.draft.deliverables.append(.init(name: "Second", aspectRatio: ""))
        document.screenplay.elements[0].text = "Cafe\u{0301}\r\nOriginal"
        let oldLedger = try bytes(ledger)
        let oldDocument = try bytes(document)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(result.missingBaselineFields.count == 4)
        #expect(result.missingBaselineFields[0] == "Enter the brand.")
        #expect(result.missingBaselineFields[1].contains(ledger.draft.deliverables[0].id.uuidString))
        #expect(result.missingBaselineFields[1].contains("enter a name"))
        #expect(result.missingBaselineFields[2].contains("enter an aspect ratio"))
        #expect(result.missingBaselineFields[3].contains(ledger.draft.deliverables[1].id.uuidString))
        #expect(try bytes(ledger) == oldLedger)
        #expect(try bytes(document) == oldDocument)
    }

    @Test func manualReferencesAndUnlinkedDeliverablesDoNotBecomeNewApprovalGates() throws {
        let (document, ledger) = fixture(linked: false)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(result.missingBaselineFields.isEmpty)
        #expect(result.nextStep.destination == .baseline)
        #expect(result.unlinkedDeliverableCount == 1)
        #expect(result.missingShotLinkCount == 0)
        #expect(try !item(.coverage, in: result).needsAttention)
        #expect(try item(.coverage, in: result).details.contains { $0.contains("not semantic or exhaustive coverage") })
        #expect(result.agencyWarnings.isEmpty)
        #expect(try !item(.agencySources, in: result).needsAttention)
        #expect(try !item(.assumptions, in: result).needsAttention)
        #expect(try item(.assumptions, in: result).summary.contains("1 manual bid assumption"))
        #expect(try item(.baseline, in: result).summary.contains("before freezing"))
    }

    @Test func unreviewedSourceThenRevisionAndCitationWarningsDriveAgencyReview() throws {
        var (document, ledger) = fixture()
        let first = try ledger.draft.importAgencyText(data: Data("Hero is 30 seconds.\n".utf8), filename: "synthetic-brief.txt", at: timestamp)
        let unreviewed = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(unreviewed.nextStep.destination == .agencySources)
        #expect(unreviewed.agencyWarnings.count == 1)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: first.id, reviewer: "Synthetic producer", note: "Reviewed exact text.", at: timestamp)
        _ = try ledger.draft.citeAgencyRevision(revisionID: first.id, firstLine: 1, lastLine: 1,
            targetKind: .deliverable, targetID: ledger.draft.deliverables[0].id, note: "Duration reference.", at: timestamp)
        let baseline = try ledger.freeze(name: "Reviewed source", document: document, at: timestamp)
        let current = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(current.agencyWarnings.isEmpty)
        #expect(current.nextStep.destination == .report)
        _ = try ledger.draft.importAgencyText(data: Data("Hero is 45 seconds.\n".utf8), filename: "synthetic-brief-v2.txt", revisingDocumentID: first.documentID, at: timestamp)
        let revised = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(revised.nextStep.destination == .agencySources)
        #expect(revised.agencyWarnings.count == 2)
        #expect(revised.agencyWarnings == ledger.draft.agency?.warnings(draft: ledger.draft))
        #expect(revised.unresolvedCount == 2)
        #expect(revised.trackedChangeCount == 1)
        #expect(revised.decisionRecords?.isHistorical == true)
        document.screenplay.elements[0].text += " Updated."
        let changed = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(changed.changes == (try ledger.compare(baselineID: baseline.id, document: document)))
    }

    @Test func targetNormalizationEditKeepsExactCitationWarningAndSourceBytes() throws {
        var (document, ledger) = fixture()
        ledger.draft.deliverables[0].name = "Café"
        let text = "\u{FEFF}Café\r\nApproved duration.\n"
        let revision = try ledger.draft.importAgencyText(data: Data(text.utf8), filename: "synthetic-unicode.txt", at: timestamp)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: revision.id, reviewer: "Producer", note: "Compared text.", at: timestamp)
        _ = try ledger.draft.citeAgencyRevision(revisionID: revision.id, firstLine: 1, lastLine: 1,
            targetKind: .deliverable, targetID: ledger.draft.deliverables[0].id, note: "Exact name.", at: timestamp)
        let baseline = try ledger.freeze(name: "Café", document: document, at: timestamp)
        ledger.draft.deliverables[0].name = "Cafe\u{0301}"
        let before = try bytes(ledger)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(result.nextStep.destination == .agencySources)
        #expect(result.agencyWarnings.count == 1)
        #expect(result.agencyWarnings[0].message.contains("target changed"))
        #expect(result.decisionRecords?.isHistorical == true)
        #expect(result.selectedBaseline?.name.utf8.elementsEqual("Café".utf8) == true)
        #expect(ledger.draft.agency?.revisions[0].bytes == Data(text.utf8))
        #expect(try bytes(ledger) == before)
        // Reading the assessment never copies normalized target text into sources.
        document.screenplay.elements[0].text = "Independent script edit."
        #expect(ledger.draft.agency?.revisions[0].bytes == Data(text.utf8))
    }

    @Test func selectedBaselineIdentitySeparatesSameContentDecisionScopes() throws {
        var (document, ledger) = fixture()
        let first = try ledger.freeze(name: "Same scope", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: first.id, scope: .creative, approver: "Director", evidence: "Synthetic review.", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: first.id, scope: .spend, approver: "Producer", evidence: "Synthetic ceiling.", document: document, spendCeilingMinorUnits: 25000, currencyCode: "USD", at: timestamp)
        let second = try ledger.freeze(name: "Same scope", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: second.id, scope: .production, approver: "Producer", evidence: "Synthetic approach review.", document: document, at: timestamp)
        let firstResult = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: first.id)
        let secondResult = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: second.id)
        #expect(firstResult.selectedBaseline?.id == first.id)
        #expect(secondResult.selectedBaseline?.id == second.id)
        #expect(firstResult.decisionRecords?.baselineID == first.id)
        #expect(firstResult.decisionRecords?.creativeCount == 1)
        #expect(firstResult.decisionRecords?.productionCount == 0)
        #expect(firstResult.decisionRecords?.spendCount == 1)
        #expect(secondResult.decisionRecords?.creativeCount == 0)
        #expect(secondResult.decisionRecords?.productionCount == 1)
        #expect(secondResult.decisionRecords?.spendCount == 0)
        #expect(firstResult.decisionRecords?.isHistorical == false)
        #expect(firstResult.nextStep.destination == .report)
        #expect(secondResult.nextStep.destination == .report)
        #expect(try !item(.decisions, in: secondResult).needsAttention)
        document.shots[0].notes = "New production setup."
        let revised = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: first.id)
        #expect(revised.nextStep.destination == .baseline)
        #expect(revised.decisionRecords?.isHistorical == true)
        #expect(revised.decisionRecords?.spendCount == 1)
        #expect(try item(.decisions, in: revised).details.contains { $0.contains("do not carry forward") })
    }

    @Test func noDecisionRecordsDoesNotRequireAnyScopeBeforeReportReview() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Scope only", document: document, at: timestamp)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(result.nextStep.destination == .report)
        #expect(result.changes?.isEmpty == true)
        #expect(result.changeCount == 0)
        #expect(result.decisionRecords?.creativeCount == 0)
        #expect(result.decisionRecords?.productionCount == 0)
        #expect(result.decisionRecords?.spendCount == 0)
        #expect(try !item(.decisions, in: result).needsAttention)
        #expect(CampaignReviewChecklist.decisionBoundary.contains("do not verify identity"))
        #expect(CampaignReviewChecklist.decisionBoundary.contains("No requirement"))
        document.shots[0].notes = "Changed setup."
        #expect(try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id).nextStep.destination == .baseline)
    }

    @Test func normalizationOnlyScriptEditIsTrackedAndDoesNotRewriteEitherInput() throws {
        var (document, ledger) = fixture()
        document.screenplay.elements[0].text = "Café"
        let baseline = try ledger.freeze(name: "Exact script", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Director", evidence: "Original text.", document: document, at: timestamp)
        document.screenplay.elements[0].text = "Cafe\u{0301}"
        let ledgerBefore = try bytes(ledger)
        let documentBefore = try bytes(document)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(result.trackedChangeCount == 1)
        #expect(result.decisionRecords?.isHistorical == true)
        let change = try #require(result.changes?.first { $0.sourceKind == .script })
        #expect(change.before.utf8.contains(0xC3))
        #expect(change.after.utf8.contains(0xCC))
        #expect(try bytes(ledger) == ledgerBefore)
        #expect(try bytes(document) == documentBefore)
    }

    @Test func missingDeliverableShotLinksAreConcreteBeforeAndAfterFreezing() throws {
        var (document, ledger) = fixture()
        let missingID = UUID()
        ledger.draft.deliverables[0].linkedShotIDs.append(missingID)
        let before = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(before.missingShotLinkCount == 1)
        #expect(before.nextStep.destination == .coverage)
        #expect(try item(.coverage, in: before).details.contains { $0.contains(missingID.uuidString) })
        #expect(before.unresolvedCount == nil)
        let baseline = try ledger.freeze(name: "Unresolved links", document: document, at: timestamp)
        let after = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(after.trackedChangeCount == 0)
        #expect(after.unresolvedCount == 1)
        #expect(after.decisionRecords?.isHistorical == false)
        #expect(after.decisionRecords?.hasUnresolvedReview == true)
        #expect(try item(.decisions, in: after).details.contains { $0.contains("Existing records do not resolve") })
        document.shots.removeAll()
        #expect(try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id).missingShotLinkCount == 2)
    }

    @Test func preBaselineScopeDoesNotInventFullSourceReconciliation() throws {
        var (document, ledger) = fixture()
        document.shots[0].sourceRefs = [.init(screenplayElementID: UUID())]
        let before = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(before.missingShotLinkCount == 0)
        #expect(before.changes == nil)
        #expect(before.nextStep.destination == .baseline)
        #expect(try item(.coverage, in: before).details.contains { $0.contains("after selecting a frozen baseline") })
        let baseline = try ledger.freeze(name: "Unresolved script link", document: document, at: timestamp)
        let after = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        #expect(after.nextStep.destination == .baseline)
        #expect(after.unresolvedCount == 1)
        #expect(after.changes?.contains { $0.unresolved && $0.sourceKind == .shot } == true)
    }

    @Test func unlinkedScriptChangeRemainsVisibleWithoutClaimingImpactCoverage() throws {
        var (document, ledger) = fixture(linked: false)
        let baseline = try ledger.freeze(name: "Manual coverage", document: document, at: timestamp)
        document.screenplay.elements[0].text += " A second action."
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id)
        let change = try #require(result.changes?.first { $0.sourceKind == .script })
        #expect(change.affectedDeliverableIDs.isEmpty)
        #expect(result.nextStep.destination == .baseline)
        #expect(result.unlinkedDeliverableCount == 1)
        #expect(try item(.coverage, in: result).details.contains { $0.contains("unlinked script changes") })
    }

    @Test func absentSelectionDoesNotPickABaselineOrCombineHistoricalRecords() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Saved baseline", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Director", evidence: "Synthetic decision.", document: document, at: timestamp)
        let result = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(result.selectedBaseline == nil)
        #expect(result.decisionRecords == nil)
        #expect(result.nextStep.title == "Select a baseline to compare")
        #expect(result.changes == nil)
        document.shots[0].notes = "A later scope."
        #expect(try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil).decisionRecords == nil)
    }

    @Test func wrongProjectUnknownBaselineAndInvalidDraftFailClosed() throws {
        var (document, ledger) = fixture()
        let wrongLedger = CampaignLedger(projectID: UUID(), draft: ledger.draft)
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: wrongLedger, document: document, selectedBaselineID: nil) }
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: UUID()) }
        ledger.draft.deliverables[0].durationSeconds = 0
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil) }
        ledger.draft.deliverables[0].durationSeconds = 30
        ledger.draft.deliverables.append(ledger.draft.deliverables[0])
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil) }
        document.screenplay.elements[0].text = "Still unchanged by failed reads."
        #expect(ledger.baselines.isEmpty)
        #expect(ledger.decisions.isEmpty)
    }

    @Test func invalidCanonicalSourceStructureFailsClosedForSelectedComparison() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Valid sources", document: document, at: timestamp)
        document.shots.append(document.shots[0])
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id) }
        document.shots.removeLast()
        document.screenplay.elements.append(document.screenplay.elements[0])
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id) }
        document.screenplay.elements.removeLast()
        var board = BoardFrame(shotID: document.shots[0].id, sceneSpineID: "", frameNumber: 1, label: "Malformed duration")
        board.durationSeconds = 0
        document.boardFrames = [board]
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id) }
        #expect(ledger.baselines.count == 1)
    }

    @Test func mismatchedScreenplayIdentityAndInvalidBaselineTimeFailClosed() throws {
        var (document, ledger) = fixture()
        let baseline = try ledger.freeze(name: "Invalid time", document: document,
            at: Date(timeIntervalSince1970: .infinity))
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: baseline.id) }
        document.screenplay = Screenplay(metadata: .init(title: "Unrelated screenplay"), elements: [])
        #expect(throws: CampaignError.self) { try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil) }
    }

    @Test func repeatedAssessmentIsDeterministicAndDoesNotCreateHistory() throws {
        let (document, ledger) = fixture()
        let first = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        let second = try CampaignReviewChecklist(ledger: ledger, document: document, selectedBaselineID: nil)
        #expect(first.items.map(\.id) == second.items.map(\.id))
        #expect(first.items.map(\.details) == second.items.map(\.details))
        #expect(first.nextStep.id == second.nextStep.id)
        #expect(first.selectedBaseline == nil)
        #expect(ledger.baselines.isEmpty)
        #expect(ledger.decisions.isEmpty)
        #expect(ledger.draft.agency == nil)
    }
}
