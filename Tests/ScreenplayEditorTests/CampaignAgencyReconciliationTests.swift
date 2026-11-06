import Foundation
import Testing
import ScreenplayDomain

@Suite("Campaign atomic agency reconciliation")
struct CampaignAgencyReconciliationTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Fixture {
        let document: ScreenplayOSDocument
        var ledger: CampaignLedger
        let original: CampaignAgencyRevision
        let current: CampaignAgencyRevision
        let citation: CampaignAgencyCitation
    }

    private func fixture() throws -> Fixture {
        let screenplay = Screenplay(metadata: .init(title: "Synthetic reconciliation"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic reconciliation", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay)
        var ledger = CampaignLedger(projectID: document.project.id, draft: CampaignDraft(
            brief: .init(brand: "Synthetic brand", objective: "Reconcile exact evidence"),
            deliverables: [.init(name: "Café hero"), .init(name: "Synthetic cutdown", durationSeconds: 15)],
            assumptions: [.init(text: "Café location")]))
        let original = try ledger.draft.importAgencyText(data: Data("\u{FEFF}Cafe\u{0301}\r\n30 seconds 😀\n".utf8),
            filename: "Café-v1.txt", at: timestamp)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: original.id, reviewer: "Synthetic Producer", note: "Café", at: timestamp)
        let citation = try ledger.draft.citeAgencyRevision(revisionID: original.id, firstLine: 1, lastLine: 2,
            targetKind: .deliverable, targetID: ledger.draft.deliverables[0].id, note: "Café", at: timestamp)
        let baseline = try ledger.freeze(name: "Original evidence", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Synthetic Director",
            evidence: "Synthetic creative decision", document: document, at: timestamp)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .spend, approver: "Synthetic Client",
            evidence: "Separate synthetic ceiling", document: document, spendCeilingMinorUnits: 12500,
            currencyCode: "USD", at: timestamp)
        let current = try ledger.draft.importAgencyText(data: Data("Current Café\r\n45 seconds 👩🏽‍🎨\nCafe\u{0301}\u{2028}literal\r".utf8),
            filename: "Café-v2.txt", revisingDocumentID: original.documentID, at: timestamp)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: current.id, reviewer: "Synthetic Producer", note: "Café", at: timestamp)
        return .init(document: document, ledger: ledger, original: original, current: current, citation: citation)
    }

    private func preview(_ fixture: Fixture) throws -> CampaignAgencyCitationReplacementPreview {
        try fixture.ledger.draft.previewAgencyCitationReplacement(citationID: fixture.citation.id,
            revisionID: fixture.current.id, firstLine: 2, lastLine: 3, targetKind: .deliverable,
            targetID: fixture.citation.targetID, note: "Human chose the current lines and existing authored target.")
    }

    private func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Simulate a separately loaded, otherwise valid workspace with the same IDs.
    private func rewrite(_ draft: inout CampaignDraft, collection: String,
                         _ edit: (inout [[String: Any]]) throws -> Void) throws {
        let workspace = try #require(draft.agency)
        var object = try #require(JSONSerialization.jsonObject(with: bytes(workspace)) as? [String: Any])
        var rows = try #require(object[collection] as? [[String: Any]])
        try edit(&rows)
        object[collection] = rows
        draft.agency = try JSONDecoder().decode(CampaignAgencyWorkspace.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func previewShowsExactOriginalAndCurrentEvidenceWithoutMutatingAnything() throws {
        let f = try fixture(), before = try bytes(f.ledger)
        let result = try preview(f)
        #expect(try bytes(f.ledger) == before)
        #expect(result.originalCitation.id == f.citation.id)
        #expect(result.originalRevision.bytes == f.original.bytes)
        #expect(result.replacementRevision.bytes == f.current.bytes)
        #expect(Data(result.originalExcerpt.utf8) == Data("\u{FEFF}Cafe\u{0301}\n30 seconds 😀".utf8))
        #expect(Data(result.replacementExcerpt.utf8) == Data("45 seconds 👩🏽‍🎨\nCafe\u{0301}\u{2028}literal\r".utf8))
        #expect(result.replacementReview.revisionID == f.current.id)
        #expect(result.targetSnapshot.utf8.elementsEqual(f.citation.targetSnapshot.utf8))
        try f.ledger.draft.validateAgencyCitationReplacement(result)
    }

    @Test func oneReplacementPreservesHistoryTargetsBaselinesAndSeparateDecisions() throws {
        var f = try fixture()
        let before = f.ledger, result = try preview(f)
        let replacement = try f.ledger.draft.replaceAgencyCitation(result, at: timestamp)
        #expect(replacement.id != f.citation.id)
        #expect(f.ledger.draft.agency?.citations == [replacement])
        #expect(replacement.revisionID == f.current.id)
        #expect(replacement.targetSnapshot.utf8.elementsEqual(result.targetSnapshot.utf8))
        #expect(try bytes(f.ledger.draft.agency?.revisions) == bytes(before.draft.agency?.revisions))
        #expect(try bytes(f.ledger.draft.agency?.reviews) == bytes(before.draft.agency?.reviews))
        #expect(try bytes(f.ledger.baselines) == bytes(before.baselines))
        #expect(try bytes(f.ledger.decisions) == bytes(before.decisions))
        #expect(f.ledger.draft.deliverables == before.draft.deliverables)
        #expect(f.ledger.draft.assumptions == before.draft.assumptions)
        #expect(f.ledger.decisions.map(\.scope) == [.creative, .spend])
        #expect(f.ledger.decisions[0].spendCeilingMinorUnits == nil)
        #expect(f.ledger.decisions[1].spendCeilingMinorUnits == 12500)
        #expect(f.ledger.draft.agency?.warnings(draft: f.ledger.draft).isEmpty == true)
        #expect(f.ledger.baselines[0].draft.agency?.citations == [f.citation])
        #expect(throws: CampaignError.self) {
            try f.ledger.recordDecision(baselineID: before.baselines[0].id, scope: .production,
                approver: "Synthetic Producer", evidence: "Old baseline cannot carry forward", document: f.document)
        }
        let encoded = try bytes(f.ledger)
        #expect(try bytes(JSONDecoder().decode(CampaignLedger.self, from: encoded)) == encoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let draft = try #require(object["draft"] as? [String: Any])
        let agency = try #require(draft["agency"] as? [String: Any])
        #expect(Set(agency.keys) == Set(["revisions", "reviews", "citations"]))
    }

    @Test func replacementAtLimitPreservesPositionAndEveryUntouchedCitation() throws {
        var f = try fixture()
        let replacedIndex = 127
        try rewrite(&f.ledger.draft, collection: "citations") { rows in
            let original = rows[0]
            rows = (0..<CampaignAgencyWorkspace.maximumAnnotations).map { index in
                var copy = original
                if index != replacedIndex { copy["id"] = UUID().uuidString }
                return copy
            }
        }
        let before = try #require(f.ledger.draft.agency).citations
        let pending = try preview(f)
        let replacement = try f.ledger.draft.replaceAgencyCitation(pending, at: timestamp)
        let after = try #require(f.ledger.draft.agency).citations
        #expect(after.count == CampaignAgencyWorkspace.maximumAnnotations)
        #expect(after[replacedIndex].id == replacement.id)
        for index in after.indices where index != replacedIndex {
            #expect(try bytes(after[index]) == bytes(before[index]))
        }
    }

    @Test func changedOrRemovedOriginalTargetRequiresAnExplicitExistingReplacementTarget() throws {
        var f = try fixture()
        f.ledger.draft.deliverables[0].durationSeconds = 45
        let unchanged = try bytes(f.ledger.draft)
        let changed = try preview(f)
        #expect(!changed.targetSnapshot.utf8.elementsEqual(f.citation.targetSnapshot.utf8))
        #expect(changed.originalCitation.targetSnapshot.utf8.elementsEqual(f.citation.targetSnapshot.utf8))
        #expect(try bytes(f.ledger.draft) == unchanged)
        f.ledger.draft.deliverables.removeFirst()
        #expect(throws: CampaignError.self) { try preview(f) }
        let chosenAssumption = f.ledger.draft.assumptions[0]
        let explicit = try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
            revisionID: f.current.id, firstLine: 1, lastLine: 1, targetKind: .assumption,
            targetID: chosenAssumption.id, note: "Human explicitly chose the surviving assumption.")
        let replacement = try f.ledger.draft.replaceAgencyCitation(explicit, at: timestamp)
        #expect(replacement.targetKind == .assumption)
        #expect(replacement.targetID == chosenAssumption.id)
        #expect(f.ledger.draft.deliverables.count == 1)
        #expect(f.ledger.draft.assumptions == [chosenAssumption])
    }

    @Test func targetOnlyReconciliationCanKeepTheSameReviewedSourceRevision() throws {
        let f = try fixture()
        var draft = f.ledger.baselines[0].draft
        draft.deliverables[0].durationSeconds = 45
        #expect(draft.agency?.warnings(draft: draft).count == 1)
        let pending = try draft.previewAgencyCitationReplacement(citationID: f.citation.id,
            revisionID: f.original.id, firstLine: 1, lastLine: 2, targetKind: .deliverable,
            targetID: f.citation.targetID, note: "Human reviewed the target change against the unchanged source.")
        let replacement = try draft.replaceAgencyCitation(pending, at: timestamp)
        #expect(replacement.revisionID == f.original.id)
        #expect(replacement.targetID == f.citation.targetID)
        #expect(replacement.id != f.citation.id)
        #expect(draft.deliverables[0].durationSeconds == 45)
        #expect(draft.agency?.warnings(draft: draft).isEmpty == true)
    }

    @Test func invalidRangesNotesUnknownCitationAndWrongDocumentNeverCreateAPreview() throws {
        var f = try fixture()
        let other = try f.ledger.draft.importAgencyText(data: Data("Other document".utf8), filename: "other.txt", at: timestamp)
        _ = try f.ledger.draft.reviewAgencyRevision(revisionID: other.id, reviewer: "Synthetic Producer", note: "Reviewed", at: timestamp)
        let before = try bytes(f.ledger)
        for range in [(0, 1), (2, 1), (1, 4), (1, Int.max)] {
            #expect(throws: CampaignError.self) {
                try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
                    revisionID: f.current.id, firstLine: range.0, lastLine: range.1, targetKind: .deliverable,
                    targetID: f.citation.targetID, note: "Invalid range")
            }
        }
        for revisionID in [f.original.id, other.id, UUID()] {
            #expect(throws: CampaignError.self) {
                try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
                    revisionID: revisionID, firstLine: 1, lastLine: 1, targetKind: .deliverable,
                    targetID: f.citation.targetID, note: "Must be the current revision of the same document")
            }
        }
        for note in [" \n", String(repeating: "x", count: 16 * 1024 + 1)] {
            #expect(throws: CampaignError.self) {
                try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
                    revisionID: f.current.id, firstLine: 1, lastLine: 1, targetKind: .deliverable,
                    targetID: f.citation.targetID, note: note)
            }
        }
        #expect(throws: CampaignError.self) {
            try f.ledger.draft.previewAgencyCitationReplacement(citationID: UUID(), revisionID: f.current.id,
                firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: f.citation.targetID, note: "Missing")
        }
        #expect(try bytes(f.ledger) == before)
    }

    @Test func newerRevisionEvenWithIdenticalBytesRequiresFreshReviewAndPreview() throws {
        var f = try fixture()
        let pending = try preview(f)
        let newer = try f.ledger.draft.importAgencyText(data: f.current.bytes, filename: f.current.filename,
            revisingDocumentID: f.current.documentID, at: timestamp)
        let unreviewed = try bytes(f.ledger)
        #expect(throws: CampaignError.self) { try f.ledger.draft.replaceAgencyCitation(pending) }
        #expect(throws: CampaignError.self) {
            try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id, revisionID: newer.id,
                firstLine: 1, lastLine: 1, targetKind: .deliverable, targetID: f.citation.targetID, note: "Unreviewed")
        }
        #expect(try bytes(f.ledger) == unreviewed)
        _ = try f.ledger.draft.reviewAgencyRevision(revisionID: newer.id, reviewer: "Synthetic Producer", note: "Fresh review", at: timestamp)
        let reviewed = try bytes(f.ledger)
        #expect(throws: CampaignError.self) { try f.ledger.draft.validateAgencyCitationReplacement(pending) }
        #expect(throws: CampaignError.self) { try f.ledger.draft.replaceAgencyCitation(pending) }
        #expect(throws: CampaignError.self) { try preview(f) }
        #expect(try bytes(f.ledger) == reviewed)
    }

    @Test func newerReviewMissingEvidenceAndMissingOrChangedTargetRejectPendingPreview() throws {
        let f = try fixture(), pending = try preview(f)
        let mutations: [(inout CampaignDraft) throws -> Void] = [
            { draft in _ = try draft.reviewAgencyRevision(revisionID: f.current.id, reviewer: "Synthetic Producer", note: "New review") },
            { draft in draft.agency = nil },
            { draft in try draft.removeAgencyCitation(id: f.citation.id) },
            { draft in draft.deliverables.removeFirst() },
            { draft in draft.deliverables[0].durationSeconds = 45 }
        ]
        for mutate in mutations {
            var draft = f.ledger.draft
            try mutate(&draft)
            let before = try bytes(draft)
            #expect(throws: CampaignError.self) { try draft.validateAgencyCitationReplacement(pending) }
            #expect(throws: CampaignError.self) { try draft.replaceAgencyCitation(pending) }
            #expect(try bytes(draft) == before)
        }
    }

    @Test func canonicallyEquivalentUnicodeChangesToEveryPreviewedEndpointFailClosed() throws {
        let f = try fixture(), pending = try preview(f)
        // Swift String and synthesized Equatable consider these equal. Evidence does not.
        #expect("Café" == "Cafe\u{0301}")
        let mutations: [(inout CampaignDraft) throws -> Void] = [
            { draft in draft.deliverables[0].name = "Cafe\u{0301} hero" },
            { draft in try self.rewrite(&draft, collection: "citations") { $0[0]["note"] = "Cafe\u{0301}" } },
            { draft in try self.rewrite(&draft, collection: "reviews") { $0[1]["note"] = "Cafe\u{0301}" } },
            { draft in try self.rewrite(&draft, collection: "revisions") { $0[0]["filename"] = "Cafe\u{0301}-v1.txt" } },
            { draft in try self.rewrite(&draft, collection: "revisions") { $0[1]["filename"] = "Cafe\u{0301}-v2.txt" } }
        ]
        for mutate in mutations {
            var draft = f.ledger.draft
            try mutate(&draft)
            let before = try bytes(draft)
            #expect(draft == f.ledger.draft)
            #expect(before != (try bytes(f.ledger.draft)))
            #expect(throws: CampaignError.self) { try draft.replaceAgencyCitation(pending) }
            #expect(try bytes(draft) == before)
        }
    }

    @Test func assumedTargetUnicodeChangesAndReplayedPreviewAreRejectedAtomically() throws {
        var f = try fixture()
        let target = f.ledger.draft.assumptions[0].id
        let pending = try f.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
            revisionID: f.current.id, firstLine: 1, lastLine: 1, targetKind: .assumption, targetID: target,
            note: "Human chose a different target explicitly")
        f.ledger.draft.assumptions[0].text = "Cafe\u{0301} location"
        let stale = try bytes(f.ledger)
        #expect(throws: CampaignError.self) { try f.ledger.draft.replaceAgencyCitation(pending) }
        #expect(try bytes(f.ledger) == stale)
        f.ledger.draft.assumptions[0].text = "Café location"
        _ = try f.ledger.draft.replaceAgencyCitation(pending, at: timestamp)
        let replaced = try bytes(f.ledger)
        #expect(throws: CampaignError.self) { try f.ledger.draft.replaceAgencyCitation(pending) }
        #expect(try bytes(f.ledger) == replaced)
    }

    @Test func invalidCommitDateLeavesOldCitationAndHistoryUntouched() throws {
        var f = try fixture()
        let pending = try preview(f), before = try bytes(f.ledger)
        #expect(throws: CampaignError.self) {
            try f.ledger.draft.replaceAgencyCitation(pending, at: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        #expect(try bytes(f.ledger) == before)
    }
}
