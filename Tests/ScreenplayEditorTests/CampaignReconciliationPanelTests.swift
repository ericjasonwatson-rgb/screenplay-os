import AppKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

extension CampaignPanelLifecycleTests {
    /// Nest under the existing serialized Campaign suite so both sets of hosted
    /// windows share its serialization and one-time AppKit launch/AX setup.
    /// The full native test run still uses --no-parallel for unrelated UI suites.
    @Suite("Campaign guided citation reconciliation", .serialized)
    @MainActor
    struct CampaignReconciliationPanelTests {
        @Test func explicitPreviewAndConfirmPersistReplacementAndOneUndoRestoresExactEvidence() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let evidence = try seed(fixture)
            _ = try await fixture.scriptEditor()
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")
            try await begin(fixture, evidence: evidence)
            try await expectBlankDraft(fixture)

            let note = "Checked the revised matrix: 45 seconds replaces the original 30-second hero."
            try await prepare(fixture, note: note)
            try await fixture.press("campaign.reconciliation.preview")
            _ = try await fixture.control("campaign.reconciliation.confirm")
            try await expectPreviewEvidence(fixture, evidence: evidence, note: note)
            #expect(try fixture.ledger() == evidence.ledger)
            #expect(try savedBytes(fixture) == evidence.bytes,
                    "Preview must not remove the old citation or save a replacement.")
            try await expectDisabled(fixture, "campaign.undo")

            try await fixture.press("campaign.reconciliation.confirm")
            try await fixture.expectLedger {
                $0.draft.agency?.citations.count == 1 &&
                $0.draft.agency?.citations.first?.id != evidence.citation.id
            }
            let replaced = try fixture.ledger()
            let citation = try #require(replaced.draft.agency?.citations.first)
            #expect(citation.id != evidence.citation.id)
            #expect(citation.documentID == evidence.current.documentID)
            #expect(citation.revisionID == evidence.current.id)
            #expect(citation.firstLine == 19 && citation.lastLine == 29)
            #expect(citation.targetKind == .deliverable)
            #expect(citation.targetID == evidence.citation.targetID)
            #expect(citation.targetSnapshot != evidence.citation.targetSnapshot)
            #expect(citation.note == note)
            #expect(replaced.draft.deliverables == evidence.ledger.draft.deliverables)
            #expect(replaced.draft.agency?.revisions == evidence.ledger.draft.agency?.revisions)
            #expect(replaced.draft.agency?.reviews == evidence.ledger.draft.agency?.reviews)
            #expect(replaced.baselines == evidence.ledger.baselines)
            #expect(replaced.decisions == evidence.ledger.decisions)
            #expect(replaced.baselines.first?.draft.agency?.citations == [evidence.citation])
            #expect(replaced.draft.agency?.warnings(draft: replaced.draft).isEmpty == true)
            #expect(fixture.model.document == evidence.document)
            try await expectAbsent(fixture, "campaign.reconciliation.confirm")
            let reopened = CampaignWorkspaceSession(projectID: replaced.projectID, root: fixture.root)
            #expect(reopened.problem == nil)
            #expect(reopened.ledger == replaced, "The replacement must survive an independent disk reload.")
            #expect(!reopened.canUndoDraft)

            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == evidence.ledger }
            #expect(try fixture.ledger().draft.agency?.citations == [evidence.citation])
            #expect(try savedBytes(fixture) == evidence.bytes,
                    "One native Undo must restore the exact old ID, evidence and saved bytes.")
            try await expectDisabled(fixture, "campaign.undo")
            try assertOriginalsUnchanged(evidence)
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            #expect(try fixture.ledger() == evidence.ledger)
            #expect(try savedBytes(fixture) == evidence.bytes)
            try await expectDisabled(fixture, "campaign.undo")
        }

        @Test func cancelTabSwitchAndCloseDiscardPendingReconciliation() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let evidence = try seed(fixture)
            _ = try await fixture.scriptEditor()
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")

            for dismissal in [Dismissal.cancel, .tab, .close] {
                try await begin(fixture, evidence: evidence)
                try await prepare(fixture, note: "Unconfirmed synthetic replacement: \(dismissal.rawValue)")
                try await fixture.press("campaign.reconciliation.preview")
                _ = try await fixture.control("campaign.reconciliation.confirm")
                #expect(try savedBytes(fixture) == evidence.bytes)
                switch dismissal {
                case .cancel:
                    try await fixture.press("campaign.reconciliation.cancel")
                case .tab:
                    try await fixture.selectTab("Brief & Deliverables")
                    try await expectAbsent(fixture, "campaign.reconciliation.confirm")
                    try await fixture.selectTab("Agency Sources")
                case .close:
                    try await fixture.press("campaign.close")
                    try await fixture.expectDismissed()
                    _ = try await fixture.open()
                    try await fixture.selectTab("Agency Sources")
                }
                try await expectAbsent(fixture, "campaign.reconciliation.confirm")
                try await expectAbsent(fixture, "campaign.reconciliation.firstLine")
                #expect(try fixture.ledger() == evidence.ledger)
                #expect(try savedBytes(fixture) == evidence.bytes)
                try await expectDisabled(fixture, "campaign.undo")
                // Re-enter through the original citation's stable identity. A
                // dismissed draft must not silently retain its range or target.
                try await begin(fixture, evidence: evidence)
                try await expectBlankDraft(fixture)
                try await fixture.press("campaign.reconciliation.cancel")
                try await expectAbsent(fixture, "campaign.reconciliation.firstLine")
            }
            #expect(fixture.model.document == evidence.document)
            try assertOriginalsUnchanged(evidence)
        }

        @Test func changingFieldsInvalidatesPreviewAndRequiresAnotherExplicitPreview() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let evidence = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")
            try await begin(fixture, evidence: evidence)
            try await prepare(fixture, note: "First unconfirmed reconciliation note")
            try await fixture.press("campaign.reconciliation.preview")
            _ = try await fixture.control("campaign.reconciliation.confirm")

            let revisedNote = "Producer rechecked the changed hero duration against the retained original."
            try await fixture.replaceText("campaign.reconciliation.note", with: revisedNote)
            try await expectAbsent(fixture, "campaign.reconciliation.confirm")
            #expect(try savedBytes(fixture) == evidence.bytes)
            try await fixture.replaceText("campaign.reconciliation.firstLine", with: "0")
            try await expectDisabled(fixture, "campaign.reconciliation.preview")
            #expect(try fixture.ledger() == evidence.ledger)
            try await fixture.replaceText("campaign.reconciliation.firstLine", with: "19")
            try await fixture.press("campaign.reconciliation.preview")
            try await fixture.press("campaign.reconciliation.confirm")
            try await fixture.expectLedger {
                $0.draft.agency?.citations.first?.note == revisedNote &&
                $0.draft.agency?.citations.first?.id != evidence.citation.id
            }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == evidence.ledger }
            #expect(try savedBytes(fixture) == evidence.bytes)
            try await expectDisabled(fixture, "campaign.undo")
        }

        @Test func revisedSourceRequiresAnExplicitNativeReviewBeforeReconciliation() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let evidence = try seed(fixture, reviewCurrent: false)
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")
            try await expectDisabled(fixture, "campaign.agency.reconcile.\(evidence.citation.id)")
            try await expectAbsent(fixture, "campaign.reconciliation.confirm")
            try await expectDisabled(fixture, "campaign.agency.review")
            #expect(try fixture.ledger().draft.agency?.currentReview(revisionID: evidence.current.id) == nil)
            #expect(try savedBytes(fixture) == evidence.bytes)

            try await fixture.replaceText("campaign.agency.reviewer", with: "Synthetic Producer")
            try await expectDisabled(fixture, "campaign.agency.review")
            let reviewNote = "Compared the original DOCX and extracted table cells; the revised hero is 45 seconds."
            try await fixture.replaceText("campaign.agency.reviewNote", with: reviewNote)
            try await fixture.press("campaign.agency.review")
            try await fixture.expectLedger {
                $0.draft.agency?.currentReview(revisionID: evidence.current.id)?.note == reviewNote
            }
            let reviewed = try fixture.ledger()
            #expect(reviewed.draft.agency?.citations == [evidence.citation],
                    "Source review alone must not reconcile an outdated citation.")
            #expect(reviewed.baselines == evidence.ledger.baselines)
            #expect(reviewed.decisions == evidence.ledger.decisions)
            try await begin(fixture, evidence: evidence)
            try await expectBlankDraft(fixture)
            try await prepare(fixture, note: "Explicitly reconciled after recording the new source review.")
            try await fixture.press("campaign.reconciliation.preview")
            try await fixture.press("campaign.reconciliation.confirm")
            try await fixture.expectLedger {
                $0.draft.agency?.citations.first?.revisionID == evidence.current.id
            }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == reviewed }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == evidence.ledger }
            #expect(try savedBytes(fixture) == evidence.bytes)
            try await expectDisabled(fixture, "campaign.undo")
            #expect(fixture.model.document == evidence.document)
        }

        @Test func nativeUndoInvalidatesOpenPreviewWhenTargetOrSourceReviewChanges() async throws {
            for changeReview in [false, true] {
                let fixture = try CampaignPanelFixture()
                defer { fixture.close() }
                let evidence = try seed(fixture, reviewCurrent: !changeReview)
                _ = try await fixture.open()
                if changeReview {
                    try await fixture.selectTab("Agency Sources")
                    try await fixture.replaceText("campaign.agency.reviewer", with: "Synthetic Producer")
                    try await fixture.replaceText("campaign.agency.reviewNote", with: "Fresh review before a native Undo interruption.")
                    try await fixture.press("campaign.agency.review")
                    try await fixture.expectLedger {
                        $0.draft.agency?.currentReview(revisionID: evidence.current.id) != nil
                    }
                } else {
                    try await fixture.replaceText("campaign.deliverable.name.\(evidence.citation.targetID)",
                        with: "Explicitly renamed synthetic hero")
                    try await fixture.expectLedger { $0.draft.deliverables.first?.name == "Explicitly renamed synthetic hero" }
                    try await fixture.selectTab("Agency Sources")
                }
                try await begin(fixture, evidence: evidence)
                try await prepare(fixture, note: "Preview tied to the current source review and selected target.")
                try await fixture.press("campaign.reconciliation.preview")
                _ = try await fixture.control("campaign.reconciliation.confirm")
                try await fixture.press("campaign.undo")
                try await fixture.expectLedger { $0 == evidence.ledger }
                try await expectAbsent(fixture, "campaign.reconciliation.confirm")
                try await expectDisabled(fixture, "campaign.reconciliation.preview")
                let problem = try await fixture.control("campaign.reconciliation.problem")
                let message = try accessibilityText(problem)
                #expect(message.contains(changeReview ? "source, review, or citation changed" : "target changed or was removed"))
                #expect(try savedBytes(fixture) == evidence.bytes)
                #expect(try fixture.ledger().draft.agency?.citations == [evidence.citation])
                try await expectDisabled(fixture, "campaign.undo")
                try await fixture.press("campaign.reconciliation.cancel")
                if changeReview {
                    try await expectDisabled(fixture, "campaign.agency.reconcile.\(evidence.citation.id)")
                } else {
                    try await begin(fixture, evidence: evidence)
                    try await expectBlankDraft(fixture)
                }
                #expect(fixture.model.document == evidence.document)
            }
        }

        @Test func concurrentRevisionChangedTargetAndRemovedTargetRefuseOpenPreviewCommit() async throws {
            for change in [ExternalChange.revision, .targetChanged, .targetRemoved] {
                let fixture = try CampaignPanelFixture()
                defer { fixture.close() }
                let evidence = try seed(fixture)
                _ = try await fixture.open()
                try await fixture.selectTab("Agency Sources")
                try await begin(fixture, evidence: evidence)
                try await prepare(fixture, note: "Frozen preview before a concurrent \(change.rawValue) change")
                try await fixture.press("campaign.reconciliation.preview")
                _ = try await fixture.control("campaign.reconciliation.confirm")

                // A second cooperating window changes the saved revision while
                // the real sheet still holds the first window's frozen preview.
                // This is deliberate race setup, not a substitute for pressing
                // the actual Confirm control in the first window.
                let writer = CampaignWorkspaceSession(projectID: evidence.ledger.projectID, root: fixture.root)
                try #require(writer.problem == nil)
                switch change {
                case .revision:
                    let source = try importInput("deliverables-v2-metadata-only", fixture: fixture)
                    try #require(writer.importAgencyText(source.preview, revisingDocumentID: evidence.current.documentID))
                    let newer = try #require(writer.ledger.draft.agency?.revisions.last)
                    #expect(newer.id != evidence.current.id)
                    #expect(newer.bytes == evidence.current.bytes)
                    #expect(newer.origin?.originalSHA256 != evidence.current.origin?.originalSHA256)
                case .targetChanged:
                    writer.updateDraft { $0.deliverables[0].name = "Concurrent revised hero target" }
                case .targetRemoved:
                    writer.updateDraft { $0.deliverables.removeAll { $0.id == evidence.citation.targetID } }
                }
                try #require(writer.problem == nil)
                let concurrent = writer.ledger
                let concurrentBytes = try savedBytes(fixture)
                #expect(concurrentBytes != evidence.bytes)
                #expect(concurrent.draft.agency?.citations == [evidence.citation])
                try await fixture.press("campaign.reconciliation.confirm")
                let problem = try await fixture.control("campaign.reconciliation.problem")
                #expect(try accessibilityText(problem).contains("Close and reopen"))
                #expect(try fixture.ledger() == concurrent)
                #expect(try savedBytes(fixture) == concurrentBytes,
                        "A stale native confirmation must not overwrite the other window's work.")
                try await expectDisabled(fixture, "campaign.undo")
                #expect(fixture.model.document == evidence.document)
                try await fixture.press("campaign.close")
                try await fixture.expectDismissed()
                _ = try await fixture.open()
                try await fixture.selectTab("Agency Sources")
                try await expectAbsent(fixture, "campaign.reconciliation.confirm")
                #expect(try fixture.ledger() == concurrent)
                #expect(try savedBytes(fixture) == concurrentBytes)
                #expect(try fixture.ledger().draft.agency?.citations == [evidence.citation])
                try assertOriginalsUnchanged(evidence)
            }
        }

        private enum Dismissal: String { case cancel, tab, close }
        private enum ExternalChange: String { case revision, targetChanged, targetRemoved }

        private struct Evidence {
            let original: CampaignAgencyRevision
            let current: CampaignAgencyRevision
            let citation: CampaignAgencyCitation
            let ledger: CampaignLedger
            let bytes: Data
            let document: ScreenplayOSDocument
            let originals: [URL: Data]
        }

        private struct Corpus: Decodable {
            let synthetic: Bool
            let fixtures: [Source]
            struct Source: Decodable {
                let name: String
                let filename: String
                let originalBase64: String
                let originalSHA256: String
                let expectedText: String?
            }
        }

        private func importInput(_ name: String, fixture: CampaignPanelFixture) throws
            -> (preview: CampaignAgencyImport.Preview, url: URL, bytes: Data) {
            let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures/CampaignAgency/corpus.json")
            let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
            try #require(corpus.synthetic)
            let source = try #require(corpus.fixtures.first { $0.name == name })
            let bytes = try #require(Data(base64Encoded: source.originalBase64))
            let url = fixture.root.appendingPathComponent(source.filename)
            try bytes.write(to: url)
            let preview = try CampaignAgencyImport.read(url)
            #expect(preview.text == source.expectedText)
            #expect(preview.origin?.originalSHA256 == source.originalSHA256)
            #expect(preview.origin?.originalBytes == bytes)
            return (preview, url, bytes)
        }

        /// Establish saved history before the UI session exists. The operation
        /// under test always goes through native controls, not these seed calls.
        private func seed(_ fixture: CampaignPanelFixture, reviewCurrent: Bool = true) throws -> Evidence {
            let document = try #require(fixture.model.document)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: fixture.root)
            try #require(session.problem == nil)
            let hero = CampaignDeliverable(name: "Synthetic hero film", durationSeconds: 30,
                aspectRatio: "16:9", market: "US + UK", language: "en-US")
            session.updateDraft {
                $0.brief = .init(brand: "Oat & Ember", objective: "Synthetic guided reconciliation acceptance")
                $0.deliverables = [hero]
            }
            try #require(session.problem == nil)
            let originalInput = try importInput("deliverables-v1", fixture: fixture)
            try #require(session.importAgencyText(originalInput.preview, revisingDocumentID: nil))
            let original = try #require(session.ledger.draft.agency?.revisions.last)
            try #require(session.reviewAgencyRevision(original.id, reviewer: "Synthetic Producer",
                note: "Checked the retained fictional V1 matrix against its exact extracted lines."))
            try #require(session.citeAgencyRevision(original.id, firstLine: 19, lastLine: 29,
                targetKind: .deliverable, targetID: hero.id, note: "V1 specifies the original 30-second hero."))
            let citation = try #require(session.ledger.draft.agency?.citations.first)
            let baselineID = try #require(session.freeze(name: "Synthetic reviewed V1 baseline", document: document))
            try #require(session.record(baselineID: baselineID, scope: .creative, approver: "Synthetic Client",
                evidence: "Fictional creative-only decision; not payment authority", document: document,
                amount: "", currency: ""))
            let currentInput = try importInput("deliverables-v2", fixture: fixture)
            try #require(session.importAgencyText(currentInput.preview, revisingDocumentID: original.documentID))
            let current = try #require(session.ledger.draft.agency?.revisions.last)
            if reviewCurrent {
                try #require(session.reviewAgencyRevision(current.id, reviewer: "Synthetic Producer",
                    note: "Checked the retained fictional V2 original. The revised hero is 45 seconds."))
            }
            session.updateDraft { $0.deliverables[0].durationSeconds = 45 }
            try #require(session.problem == nil)
            #expect(session.ledger.draft.agency?.citations == [citation])
            #expect(session.ledger.baselines.first?.draft.deliverables.first?.durationSeconds == 30)
            let ledger = try fixture.ledger()
            return Evidence(original: original, current: current, citation: citation, ledger: ledger,
                bytes: try savedBytes(fixture), document: document,
                originals: [originalInput.url: originalInput.bytes, currentInput.url: currentInput.bytes])
        }

        private func savedBytes(_ fixture: CampaignPanelFixture) throws -> Data {
            let projectID = try #require(fixture.model.document?.project.id)
            return try Data(contentsOf: fixture.campaignURL(projectID: projectID))
        }

        private func assertOriginalsUnchanged(_ evidence: Evidence) throws {
            for (url, bytes) in evidence.originals { #expect(try Data(contentsOf: url) == bytes) }
        }

        private func begin(_ fixture: CampaignPanelFixture, evidence: Evidence) async throws {
            try await fixture.press("campaign.agency.reconcile.\(evidence.citation.id)")
            _ = try await fixture.control("campaign.reconciliation.firstLine")
        }

        private func prepare(_ fixture: CampaignPanelFixture, note: String) async throws {
            try await fixture.replaceText("campaign.reconciliation.firstLine", with: "19")
            try await fixture.replaceText("campaign.reconciliation.lastLine", with: "29")
            try await fixture.replaceText("campaign.reconciliation.note", with: note)
            try await expectDisabled(fixture, "campaign.reconciliation.preview")
            try await fixture.press("campaign.reconciliation.keepTarget")
        }

        private func expectBlankDraft(_ fixture: CampaignPanelFixture) async throws {
            for identifier in ["firstLine", "lastLine", "note"] {
                let field = try await fixture.control("campaign.reconciliation.\(identifier)")
                #expect(try campaignAXValue(field) as? String == "")
            }
            try await expectDisabled(fixture, "campaign.reconciliation.preview")
            try await expectAbsent(fixture, "campaign.reconciliation.confirm")
        }

        private func expectPreviewEvidence(_ fixture: CampaignPanelFixture, evidence: Evidence, note: String) async throws {
            let oldExcerpt = try await readOnlyEvidence(fixture, "old.excerpt")
            let replacementExcerpt = try await readOnlyEvidence(fixture, "preview.excerpt")
            #expect(try Data(oldExcerpt.utf8) == Data(evidence.original.excerpt(firstLine: 19, lastLine: 29).utf8))
            #expect(try Data(replacementExcerpt.utf8) == Data(evidence.current.excerpt(firstLine: 19, lastLine: 29).utf8))
            let oldTarget = try await readOnlyEvidence(fixture, "old.target")
            let currentTarget = try await readOnlyEvidence(fixture, "current.target")
            let previewTarget = try await readOnlyEvidence(fixture, "preview.target")
            #expect(oldTarget == heroEvidence(duration: 30, id: evidence.citation.targetID))
            #expect(currentTarget == heroEvidence(duration: 45, id: evidence.citation.targetID))
            #expect(previewTarget == currentTarget)
            let previewNote = try await readOnlyEvidence(fixture, "preview.note")
            #expect(previewNote == note)
        }

        private func heroEvidence(duration: Int, id: UUID) -> String {
            ["Deliverable: Synthetic hero film", "Duration: \(duration) seconds",
             "Aspect ratio: 16:9", "Market: US + UK", "Language: en-US",
             "Target ID: \(id.uuidString)", "Linked shot IDs: "].joined(separator: "\n")
        }

        private func readOnlyEvidence(_ fixture: CampaignPanelFixture, _ identifier: String) async throws -> String {
            let control = try await fixture.control("campaign.reconciliation.\(identifier)")
            let view = try #require(control as? NSTextView,
                "Citation evidence must be a native selectable plain-text surface: \(identifier)")
            #expect(!view.isEditable && view.isSelectable && !view.isRichText)
            return view.string
        }

        private func expectDisabled(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            _ = try await fixture.control(identifier)
            let content = try #require(fixture.window.attachedSheet?.contentView)
            let disabled = try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier }?
                    .isAccessibilityEnabled?() == false
            }
            #expect(disabled, "Expected disabled native control: \(identifier)")
        }

        private func expectAbsent(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            let absent = try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } == nil
            }
            #expect(absent, "Dismissed or invalidated native control remains present: \(identifier)")
        }

        private func accessibilityText(_ element: AnyObject) throws -> String {
            let getter: (() -> Any?)? = element.accessibilityValue
            if let value = getter?() as? String { return value }
            return try #require(element.accessibilityLabel?(), "Native evidence has no readable text.")
        }
    }
}
