import AppKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

extension CampaignPanelLifecycleTests {
    /// Connected producer journeys in the real hosted Campaign sheet. The first
    /// begins with an absent campaign ledger; the second explicitly seeds only
    /// earlier V1 history so revision, reconciliation and report review stay bounded.
    /// Source selection uses the existing lifecycle seam with real synthetic DOCX
    /// files, and report destination selection is injected. These tests do not drive
    /// system file panels, physical keystrokes, an installed app or a screen reader.
    @Suite("Campaign connected producer journeys", .serialized)
    @MainActor
    struct CampaignProducerJourneyTests {
        @Test func blankCampaignToReviewedScopeAndLocalDecisionSurvivesReopen() async throws {
            let imports = CampaignAgencyImportLifecycle()
            let fixture = try CampaignPanelFixture(importLifecycle: imports)
            defer { fixture.close() }
            let script = try await fixture.scriptEditor()
            let selection = NSRange(location: 5, length: 4)
            script.setSelectedRange(selection)
            #expect(fixture.window.makeFirstResponder(script))
            let document = try #require(fixture.model.document)
            let screenplayURL = try #require(fixture.model.saveURL)
            let screenplayBytes = try Data(contentsOf: screenplayURL)
            let campaignURL = try fixture.campaignURL(projectID: document.project.id)
            #expect(!FileManager.default.fileExists(atPath: campaignURL.path))

            _ = try await fixture.open()
            // Guidance is navigation, including for a campaign with no saved file.
            try await fixture.press("campaign.review.nextStep")
            try await expectTab("Brief & Deliverables", fixture: fixture)
            #expect(!FileManager.default.fileExists(atPath: campaignURL.path))
            try await fixture.replaceText("campaign.field.Brand", with: "Oat & Ember")
            try await fixture.replaceText("campaign.field.Objective", with: "Synthetic campaign: a better morning")
            try await fixture.press("campaign.deliverable.add")
            try await fixture.expectLedger { $0.draft.deliverables.count == 1 }
            let heroID = try #require(try fixture.ledger().draft.deliverables.first?.id)
            try await fixture.replaceText("campaign.deliverable.name.\(heroID)", with: "Synthetic hero film")
            try await fixture.expectLedger { $0.draft.deliverables.first?.name == "Synthetic hero film" }

            try await fixture.press("campaign.review.details")
            // Make a required field missing deliberately, rather than relying
            // on a default value as evidence that the guide explains the gap.
            try await fixture.replaceText("campaign.field.Ratio", with: "")
            try await fixture.expectLedger { $0.draft.deliverables.first?.aspectRatio == "" }
            try await expectText("campaign.review.row.brief.details", contains: ["enter an aspect ratio"], fixture: fixture)
            try await fixture.replaceText("campaign.field.Ratio", with: "16:9")
            try await expectText("campaign.review.row.brief.summary", contains: ["Required baseline fields are present"], fixture: fixture)
            try await fixture.replaceText("campaign.field.Market", with: "US + UK")
            try await fixture.replaceText("campaign.field.Language", with: "en-US")
            try await route("assumptions", to: "Bid Assumptions", fixture: fixture)
            try await fixture.press("campaign.assumption.add")
            try await fixture.expectLedger { $0.draft.assumptions.count == 1 }
            let assumptionID = try #require(try fixture.ledger().draft.assumptions.first?.id)
            try await fixture.replaceText("campaign.assumption.text.\(assumptionID)", with: "One studio; no location travel")
            try await fixture.replaceText("campaign.assumption.sourceLabel.\(assumptionID)", with: "Synthetic producer bid basis")
            try await fixture.replaceText("campaign.assumption.sourceReference.\(assumptionID)", with: "Working assumption, not client approval")
            try await fixture.expectLedger { $0.draft.assumptions.first?.sourceReference == "Working assumption, not client approval" }

            try await route("agencySources", to: "Agency Sources", fixture: fixture)
            let source = try materialize("deliverables-v1", fixture: fixture)
            let beforeImport = try ledgerBytes(fixture)
            try await chooseSource(source, revising: nil, lifecycle: imports, fixture: fixture)
            #expect(try ledgerBytes(fixture) == beforeImport, "Reading and showing a source must not import it.")
            try await fixture.press("campaign.agency.import.confirm")
            try await fixture.expectLedger { $0.draft.agency?.revisions.count == 1 }
            let revision = try #require(try fixture.ledger().draft.agency?.revisions.first)
            #expect(revision.origin?.originalBytes == source.bytes)
            #expect(revision.text == source.text)
            #expect(try fixture.ledger().draft.agency?.reviews.isEmpty == true)
            #expect(try fixture.ledger().decisions.isEmpty)
            try await reviewSource(fixture, note: "Checked the fictional V1 original and exact extracted hero lines.")
            try await fixture.replaceText("campaign.agency.citation.firstLine", with: "19")
            try await fixture.replaceText("campaign.agency.citation.lastLine", with: "29")
            try await selectMenu("campaign.agency.citation.target", fixture: fixture) { $0 == "Synthetic hero film" }
            try await fixture.replaceText("campaign.agency.citation.note", with: "V1 supports this 30-second hero; no spend authority.")
            try await fixture.press("campaign.agency.citation.add")
            try await fixture.expectLedger { $0.draft.agency?.citations.count == 1 }
            let citation = try #require(try fixture.ledger().draft.agency?.citations.first)
            #expect(citation.revisionID == revision.id && citation.targetID == heroID)
            #expect(citation.firstLine == 19 && citation.lastLine == 29)

            try await route("baseline", to: "Baseline & Changes", fixture: fixture)
            try await freeze("Synthetic reviewed V1", fixture: fixture)
            let baseline = try #require(try fixture.ledger().baselines.last)
            #expect(baseline.draft.agency?.citations == [citation])
            #expect(try fixture.ledger().decisions.isEmpty, "A frozen baseline is not approval.")
            try await fixture.replaceText("campaign.approval.approver", with: "Synthetic Client")
            let evidence = "Synthetic creative-only message C-17. No spending authority."
            try await fixture.replaceText("campaign.approval.evidence", with: evidence)
            let beforeDecision = try ledgerBytes(fixture)
            try await fixture.press("campaign.approval.preview")
            let preview = try await readOnlyText("campaign.approval.preview.evidence", fixture: fixture)
            #expect(preview == evidence)
            try await expectText("campaign.approval.preview.baseline.id", contains: [baseline.id.uuidString], fixture: fixture)
            #expect(try ledgerBytes(fixture) == beforeDecision, "Preview is not the confirmation boundary.")
            try await fixture.press("campaign.approval.confirm")
            try await fixture.expectLedger { $0.decisions.count == 1 }
            let saved = try fixture.ledger()
            let decision = try #require(saved.decisions.first)
            #expect(decision.baselineID == baseline.id && decision.scope == .creative)
            #expect(decision.evidence == evidence && decision.approver == "Synthetic Client")
            #expect(decision.spendCeilingMinorUnits == nil && decision.currencyCode == nil)
            #expect(saved.draft.agency?.warnings(draft: saved.draft).isEmpty == true)
            #expect(fixture.model.document == document)
            #expect(try Data(contentsOf: screenplayURL) == screenplayBytes)
            #expect(try Data(contentsOf: source.url) == source.bytes)

            let savedBytes = try ledgerBytes(fixture)
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            #expect(fixture.window.firstResponder === script && script.selectedRange() == selection)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            #expect(try fixture.ledger() == saved && ledgerBytes(fixture) == savedBytes)
            try await expectText("campaign.approval.history.\(decision.id).evidence", contains: [evidence], fixture: fixture)
            let undo = try await fixture.control("campaign.undo")
            #expect(undo.isAccessibilityEnabled?() == false, "Reopen retains the ledger, not the former session's draft undo stack.")
            #expect(fixture.model.document == document)
        }

        @Test func savedScopeToRevisedEvidenceAndReviewedReportPreservesHistory() async throws {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Synthetic-producer-journey-\(UUID()).txt")
            defer { try? FileManager.default.removeItem(at: destination) }
            var selections = 0
            let exports = CampaignReportExportLifecycle(chooseDestination: {
                selections += 1
                return selections == 1 ? nil : destination
            }, write: CampaignReportExportLifecycle.live.write)
            let imports = CampaignAgencyImportLifecycle()
            let fixture = try CampaignPanelFixture(importLifecycle: imports, reportExportLifecycle: exports)
            defer { fixture.close() }
            let seed = try seedReviewedV1(fixture)
            _ = try await fixture.scriptEditor()
            _ = try await fixture.open()
            try await fixture.press("campaign.review.details")

            // Two byte-identical snapshots still have different approval scopes.
            // Exercise every checklist route without creating records or files.
            for (row, tab) in [("brief", "Brief & Deliverables"), ("assumptions", "Bid Assumptions"),
                               ("agencySources", "Agency Sources"),
                               ("coverage", "Brief & Deliverables"), ("baseline", "Baseline & Changes"),
                               ("decisions", "Baseline & Changes"), ("report", "Baseline & Changes")] {
                try await route(row, to: tab, fixture: fixture)
                #expect(try fixture.ledger() == seed.ledger)
                #expect(try ledgerBytes(fixture) == seed.bytes)
                #expect(!FileManager.default.fileExists(atPath: destination.path))
            }
            try await expectDecisionSummary(for: seed.unapproved, creativeCount: 0, historical: false, fixture: fixture)
            try await selectBaseline(seed.approved, fixture: fixture)
            try await expectDecisionSummary(for: seed.approved, creativeCount: 1, historical: false, fixture: fixture)
            #expect(try ledgerBytes(fixture) == seed.bytes)

            try await route("agencySources", to: "Agency Sources", fixture: fixture)
            let revised = try materialize("deliverables-v2", fixture: fixture)
            try await chooseSource(revised, revising: seed.revision.documentID, lifecycle: imports, fixture: fixture)
            #expect(try ledgerBytes(fixture) == seed.bytes)
            try await fixture.press("campaign.agency.import.confirm")
            try await fixture.expectLedger { $0.draft.agency?.revisions.count == 2 }
            let current = try #require(try fixture.ledger().draft.agency?.revisions.last)
            #expect(current.priorRevisionID == seed.revision.id)
            #expect(try fixture.ledger().draft.agency?.currentReview(revisionID: current.id) == nil)
            #expect(try fixture.ledger().draft.deliverables.first?.durationSeconds == 30,
                    "Import must not adopt the revised 45-second scope automatically.")
            #expect(try fixture.ledger().draft.agency?.citations == [seed.citation])
            #expect(try fixture.ledger().decisions == seed.ledger.decisions)
            try await expectText("campaign.review.row.agencySources.summary", contains: ["review"], fixture: fixture)
            let withWarnings = try ledgerBytes(fixture)
            try await fixture.press("campaign.review.nextStep")
            try await expectTab("Agency Sources", fixture: fixture)
            #expect(try ledgerBytes(fixture) == withWarnings)
            try await reviewSource(fixture, note: "Checked V2 against V1: the hero now runs 45 seconds.")

            try await route("brief", to: "Brief & Deliverables", fixture: fixture)
            try await setDuration(45, deliverableID: seed.citation.targetID, fixture: fixture)
            try await fixture.expectLedger { $0.draft.deliverables.first?.durationSeconds == 45 }
            try await route("baseline", to: "Baseline & Changes", fixture: fixture)
            try await routeChange("deliverable", id: seed.citation.targetID, to: "Brief & Deliverables", fixture: fixture)
            let assumption = try #require(seed.ledger.draft.assumptions.first)
            try await route("assumptions", to: "Bid Assumptions", fixture: fixture)
            try await fixture.replaceText("campaign.assumption.sourceReference.\(assumption.id)",
                with: "Synthetic V2 scope note: one studio retained")
            try await fixture.expectLedger { $0.draft.assumptions.first?.sourceReference == "Synthetic V2 scope note: one studio retained" }
            try await route("baseline", to: "Baseline & Changes", fixture: fixture)
            try await routeChange("assumption", id: assumption.id, to: "Bid Assumptions", fixture: fixture)
            try await route("agencySources", to: "Agency Sources", fixture: fixture)
            try await fixture.press("campaign.agency.reconcile.\(seed.citation.id)")
            try await fixture.replaceText("campaign.reconciliation.firstLine", with: "19")
            try await fixture.replaceText("campaign.reconciliation.lastLine", with: "29")
            let reconciliationNote = "Adopted the V2 45-second hero explicitly; all other deliverables still need producer review."
            try await fixture.replaceText("campaign.reconciliation.note", with: reconciliationNote)
            try await fixture.press("campaign.reconciliation.keepTarget")
            let beforeReconciliation = try ledgerBytes(fixture)
            try await fixture.press("campaign.reconciliation.preview")
            _ = try await fixture.control("campaign.reconciliation.confirm")
            #expect(try ledgerBytes(fixture) == beforeReconciliation)
            try await fixture.press("campaign.reconciliation.confirm")
            try await fixture.expectLedger {
                $0.draft.agency?.citations.count == 1 && $0.draft.agency?.citations.first?.id != seed.citation.id
            }
            let reconciled = try fixture.ledger()
            let replacement = try #require(reconciled.draft.agency?.citations.first)
            #expect(replacement.revisionID == current.id && replacement.targetID == seed.citation.targetID)
            #expect(replacement.note == reconciliationNote && replacement.targetSnapshot != seed.citation.targetSnapshot)
            #expect(reconciled.draft.agency?.warnings(draft: reconciled.draft).isEmpty == true)
            #expect(reconciled.baselines == seed.ledger.baselines && reconciled.decisions == seed.ledger.decisions)
            #expect(reconciled.baselines.first?.draft.agency?.citations == [seed.citation])

            try await route("decisions", to: "Baseline & Changes", fixture: fixture)
            try await expectDecisionSummary(for: seed.approved, creativeCount: 1, historical: true, fixture: fixture)
            let approval = try await fixture.control("campaign.approval.preview")
            #expect(approval.isAccessibilityEnabled?() == false)
            try await selectBaseline(seed.unapproved, fixture: fixture)
            try await expectDecisionSummary(for: seed.unapproved, creativeCount: 0, historical: true, fixture: fixture)
            try await selectBaseline(seed.approved, fixture: fixture)
            try await route("report", to: "Baseline & Changes", fixture: fixture)
            let beforeReport = try ledgerBytes(fixture)
            try await fixture.press("campaign.report.preview")
            let summary = try await readOnlyText("campaign.report.text", fixture: fixture)
            #expect(summary.contains(seed.approved.id.uuidString))
            #expect(!summary.contains(revised.text), "The initial report omits full source text.")
            try await fixture.press("campaign.report.includeFullEvidence")
            try await expectAbsent("campaign.report.save", fixture: fixture)
            try await fixture.press("campaign.report.preview")
            let displayed = try await readOnlyText("campaign.report.text", fixture: fixture)
            #expect(displayed.contains(seed.revision.text) && displayed.contains(revised.text))
            #expect(displayed.contains(reconciliationNote))
            #expect(try ledgerBytes(fixture) == beforeReport)
            try await fixture.press("campaign.report.save")
            #expect(selections == 1 && !FileManager.default.fileExists(atPath: destination.path))
            #expect(try await readOnlyText("campaign.report.text", fixture: fixture) == displayed)
            try await fixture.press("campaign.report.save")
            #expect(selections == 2)
            #expect(try Data(contentsOf: destination) == Data(displayed.utf8))
            try await expectAbsent("campaign.report.save", fixture: fixture)
            #expect(try fixture.ledger() == reconciled && ledgerBytes(fixture) == beforeReport)
            #expect(try Data(contentsOf: seed.source.url) == seed.source.bytes)
            #expect(try Data(contentsOf: revised.url) == revised.bytes)
            #expect(fixture.model.document == seed.document)

            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")
            #expect(try fixture.ledger() == reconciled)
            #expect(try ledgerBytes(fixture) == beforeReport)
            #expect(try fixture.ledger().draft.agency?.revisions.map(\.id) == [seed.revision.id, current.id])
            _ = try await fixture.control("campaign.agency.reconcile.\(replacement.id)")
            try await fixture.selectTab("Baseline & Changes")
            try await expectAbsent("campaign.report.save", fixture: fixture)
            try await expectAbsent("campaign.report.text", fixture: fixture)
            #expect(fixture.model.document == seed.document)
        }

        @Test func sourceRoutesRevealExactObjectsAndRetireInterruptedNavigation() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            // Navigation-only setup: multiple real objects make the last live
            // item offscreen initially. Removed items remain in baseline history.
            let document = try #require(fixture.model.document)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: fixture.root)
            let deliverables = (1...4).map { CampaignDeliverable(name: "Synthetic navigation film \($0)") }
            let assumptions = (1...4).map { CampaignAssumption(text: "Synthetic navigation assumption \($0)") }
            session.updateDraft {
                $0.brief = .init(brand: "Synthetic navigation campaign", objective: "Inspect changed objects")
                $0.deliverables = deliverables
                $0.assumptions = assumptions
            }
            _ = try #require(session.freeze(name: "Synthetic navigation baseline", document: document))
            session.updateDraft {
                $0.deliverables[2].name = "Synthetic revised navigation film"
                $0.assumptions[2].sourceReference = "Synthetic revised reference"
                $0.deliverables.removeLast()
                $0.assumptions.removeLast()
            }
            try #require(session.problem == nil)
            let saved = session.ledger
            let savedBytes = try ledgerBytes(fixture)
            let originalURL = try #require(fixture.model.saveURL)
            let originalBytes = try Data(contentsOf: originalURL)
            // Compare reopen with the saved format's decoded value, including
            // its existing ISO-8601 date precision, not an in-memory timestamp.
            let savedDocument = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: originalBytes)
            _ = try await fixture.open()
            try await fixture.press("campaign.review.details")

            for _ in 0..<2 {
                try await route("baseline", to: "Baseline & Changes", fixture: fixture)
                try await expectAbsent("campaign.change.source.deliverable.\(deliverables[3].id)", fixture: fixture)
                try await expectAbsent("campaign.change.source.assumption.\(assumptions[3].id)", fixture: fixture)
                try await routeChange("deliverable", id: deliverables[2].id, to: "Brief & Deliverables", fixture: fixture)
                try await route("baseline", to: "Baseline & Changes", fixture: fixture)
                try await routeChange("assumption", id: assumptions[2].id, to: "Bid Assumptions", fixture: fixture)
                // Repeating an already-selected tab must still scroll away from
                // the late item to the guide's first visible section.
                try await route("assumptions", to: "Bid Assumptions", fixture: fixture)
                try await expectVisible("campaign.assumption.add", fixture: fixture)
            }

            // Dispatch consecutive native actions without an intervening await.
            // Any queued older scroll must respect the latest requested tab.
            let earlier = try await fixture.control("campaign.review.row.assumptions")
            let later = try await fixture.control("campaign.review.row.brief")
            try pressImmediately(earlier)
            try pressImmediately(later)
            try await expectTab("Brief & Deliverables", fixture: fixture)
            try await expectVisible("campaign.field.Brand", fixture: fixture)
            #expect(try fixture.ledger() == saved && ledgerBytes(fixture) == savedBytes)

            let pending = try await fixture.control("campaign.review.row.assumptions")
            let close = try await fixture.control("campaign.close")
            try pressImmediately(pending)
            try pressImmediately(close)
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            try await expectTab("Brief & Deliverables", fixture: fixture)
            try await expectVisible("campaign.field.Brand", fixture: fixture)
            #expect(try fixture.ledger() == saved && ledgerBytes(fixture) == savedBytes)

            try await fixture.press("campaign.review.details")
            let replaced = try await fixture.control("campaign.review.row.assumptions")
            try pressImmediately(replaced)
            // External project replacement is setup for lifecycle invalidation,
            // not a stand-in for any Campaign navigation command.
            fixture.model.newDocument()
            let replacementID = try #require(fixture.model.document?.project.id)
            #expect(replacementID != document.project.id)
            try await fixture.expectDismissed()
            #expect(try Data(contentsOf: fixture.campaignURL(projectID: document.project.id)) == savedBytes)
            _ = try await fixture.open()
            try await expectTab("Brief & Deliverables", fixture: fixture)
            try await expectVisible("campaign.field.Brand", fixture: fixture)
            let brand = try await fixture.control("campaign.field.Brand")
            #expect(try campaignAXValue(brand) as? String == "")
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            fixture.model.loadScreenplayOSDocument(at: originalURL)
            _ = try await fixture.open()
            #expect(try fixture.ledger() == saved && ledgerBytes(fixture) == savedBytes)
            #expect(fixture.model.document == savedDocument)
            #expect(try Data(contentsOf: originalURL) == originalBytes)
        }

        private struct Source {
            let url: URL
            let bytes: Data
            let text: String
            let originalSHA256: String
        }

        private struct Seed {
            let document: ScreenplayOSDocument
            let source: Source
            let revision: CampaignAgencyRevision
            let citation: CampaignAgencyCitation
            let approved: CampaignBaseline
            let unapproved: CampaignBaseline
            let ledger: CampaignLedger
            let bytes: Data
        }

        private func materialize(_ name: String, fixture: CampaignPanelFixture) throws -> Source {
            struct Corpus: Decodable {
                let synthetic: Bool
                let fixtures: [Entry]
                struct Entry: Decodable {
                    let name: String
                    let filename: String
                    let originalBase64: String
                    let originalSHA256: String
                    let expectedText: String?
                }
            }
            let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures/CampaignAgency/corpus.json")
            let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
            try #require(corpus.synthetic)
            let entry = try #require(corpus.fixtures.first { $0.name == name })
            let bytes = try #require(Data(base64Encoded: entry.originalBase64))
            let text = try #require(entry.expectedText)
            let url = fixture.root.appendingPathComponent(entry.filename)
            try bytes.write(to: url)
            return .init(url: url, bytes: bytes, text: text, originalSHA256: entry.originalSHA256)
        }

        private func seedReviewedV1(_ fixture: CampaignPanelFixture) throws -> Seed {
            let document = try #require(fixture.model.document)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: fixture.root)
            let hero = CampaignDeliverable(name: "Synthetic hero film", durationSeconds: 30,
                aspectRatio: "16:9", market: "US + UK", language: "en-US")
            session.updateDraft {
                $0.brief = .init(brand: "Oat & Ember", objective: "Synthetic revision and report journey")
                $0.deliverables = [hero]
                $0.assumptions = [CampaignAssumption(text: "One studio; no location travel",
                    sourceLabel: "Synthetic bid basis", sourceReference: "V1 producer scope")]
            }
            let source = try materialize("deliverables-v1", fixture: fixture)
            try #require(session.importAgencyText(try CampaignAgencyImport.read(source.url), revisingDocumentID: nil))
            let revision = try #require(session.ledger.draft.agency?.revisions.last)
            try #require(session.reviewAgencyRevision(revision.id, reviewer: "Synthetic Producer", note: "Checked V1's fictional original."))
            try #require(session.citeAgencyRevision(revision.id, firstLine: 19, lastLine: 29,
                targetKind: .deliverable, targetID: hero.id, note: "V1's original 30-second hero."))
            let citation = try #require(session.ledger.draft.agency?.citations.first)
            let approvedID = try #require(session.freeze(name: "Synthetic approved V1", document: document))
            try #require(session.record(baselineID: approvedID, scope: .creative, approver: "Synthetic Client",
                evidence: "Synthetic creative-only V1 message. No spend authority.", document: document, amount: "", currency: ""))
            let unapprovedID = try #require(session.freeze(name: "Synthetic identical V1 without decisions", document: document))
            try #require(session.problem == nil)
            let approved = try #require(session.ledger.baselines.first { $0.id == approvedID })
            let unapproved = try #require(session.ledger.baselines.first { $0.id == unapprovedID })
            #expect(approved.draft == unapproved.draft)
            return .init(document: document, source: source, revision: revision, citation: citation,
                         approved: approved, unapproved: unapproved, ledger: session.ledger, bytes: try ledgerBytes(fixture))
        }

        private func chooseSource(_ source: Source, revising documentID: UUID?,
                                  lifecycle: CampaignAgencyImportLifecycle, fixture: CampaignPanelFixture) async throws {
            let reading = try #require(lifecycle.chooseSource(revising: documentID) { source.url })
            await reading.value
            let preview = try #require(lifecycle.preview)
            #expect(preview.text == source.text && preview.origin?.originalBytes == source.bytes)
            #expect(preview.origin?.originalSHA256 == source.originalSHA256)
            #expect(lifecycle.previewDocumentID == documentID)
            _ = try await fixture.control("campaign.agency.import.confirm")
        }

        private func reviewSource(_ fixture: CampaignPanelFixture, note: String) async throws {
            try await fixture.replaceText("campaign.agency.reviewer", with: "Synthetic Producer")
            try await fixture.replaceText("campaign.agency.reviewNote", with: note)
            try await fixture.press("campaign.agency.review")
            try await fixture.expectLedger { ledger in
                guard let revision = ledger.draft.agency?.revisions.last else { return false }
                return ledger.draft.agency?.currentReview(revisionID: revision.id)?.note == note
            }
        }

        private func freeze(_ name: String, fixture: CampaignPanelFixture) async throws {
            try await fixture.replaceText("campaign.baseline.name", with: name)
            try await fixture.press("campaign.baseline.freeze")
            try await fixture.expectLedger { $0.baselines.last?.name == name }
        }

        private func route(_ row: String, to tab: String, fixture: CampaignPanelFixture) async throws {
            let before = try ledgerBytes(fixture)
            try await fixture.press("campaign.review.row.\(row)")
            try await expectTab(tab, fixture: fixture)
            #expect(try ledgerBytes(fixture) == before, "Checklist routes must not mutate campaign data: \(row)")
        }

        private func routeChange(_ kind: String, id: UUID, to tab: String, fixture: CampaignPanelFixture) async throws {
            let before = try ledgerBytes(fixture)
            try await fixture.press("campaign.change.source.\(kind).\(id)")
            try await expectTab(tab, fixture: fixture)
            let field = kind == "deliverable" ? "campaign.deliverable.name.\(id)" : "campaign.assumption.text.\(id)"
            try await expectVisible(field, fixture: fixture)
            #expect(try ledgerBytes(fixture) == before, "Go to Source must reveal the changed object without editing it.")
        }

        private func expectTab(_ label: String, fixture: CampaignPanelFixture) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            func tabView(in view: NSView) -> NSTabView? {
                if let tabs = view as? NSTabView { return tabs }
                return view.subviews.lazy.compactMap { tabView(in: $0) }.first
            }
            try #require(try await waitForNativeUI(content) { tabView(in: content)?.selectedTabViewItem?.label == label })
        }

        private func pressImmediately(_ control: AnyObject) throws {
            try #require(control.isAccessibilityEnabled?() == true)
            try #require(control.accessibilityPerformPress?() == true)
        }

        /// Inspect the target's actual visible clip, not just its presence in the
        /// AX tree. Use a native view or its exact public NSCell.controlView when
        /// available; virtual SwiftUI nodes use their reported screen rectangle
        /// and only a scroll document whose AX tree contains this exact ID.
        private func expectVisible(_ identifier: String, fixture: CampaignPanelFixture) async throws {
            _ = try await fixture.control(identifier)
            let sheet = try #require(fixture.window.attachedSheet)
            let content = try #require(sheet.contentView)
            try #require(try await waitForNativeUI(content) {
                guard fixture.window.attachedSheet === sheet,
                      let element = campaignAXElement(in: content, matching: {
                          $0.accessibilityIdentifier?() == identifier
                      }) else { return false }
                func intersectsVisibleClip(_ rectangle: NSRect, scroll: NSScrollView) -> Bool {
                    guard scroll.window === sheet, !scroll.isHiddenOrHasHiddenAncestor,
                          !rectangle.isEmpty, [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].allSatisfy({ $0.isFinite }) else { return false }
                    let clip = scroll.contentView.visibleRect
                    // A one-pixel sliver is not useful navigation. The actual
                    // control's center must be inside the ancestor-clipped view.
                    return clip.intersects(rectangle) && clip.contains(NSPoint(x: rectangle.midX, y: rectangle.midY))
                }
                let native: NSView?
                if let view = element as? NSView { native = view }
                else if let cell = element as? NSCell { native = cell.controlView }
                else { native = nil }
                if let native, native.window === sheet, !native.isHiddenOrHasHiddenAncestor,
                   let scroll = native.enclosingScrollView {
                    return intersectsVisibleClip(native.convert(native.bounds, to: scroll.contentView), scroll: scroll)
                }
                guard let frame = element.accessibilityFrame?(), !frame.isEmpty else { return false }
                var remaining = 400
                func inspect(_ view: NSView, depth: Int = 0) -> Bool {
                    guard depth < 30, remaining > 0 else { return false }
                    remaining -= 1
                    if let scroll = view as? NSScrollView, let document = scroll.documentView,
                       campaignAXElement(in: document, matching: {
                           $0.accessibilityIdentifier?() == identifier
                       }) != nil {
                        let rectangle = scroll.contentView.convert(sheet.convertFromScreen(frame), from: nil)
                        if intersectsVisibleClip(rectangle, scroll: scroll) { return true }
                    }
                    return view.subviews.contains { inspect($0, depth: depth + 1) }
                }
                return inspect(content)
            }, "The requested native control is not visible in its scroll viewport: \(identifier)")
        }

        private func ledgerBytes(_ fixture: CampaignPanelFixture) throws -> Data {
            let projectID = try #require(fixture.model.document?.project.id)
            return try Data(contentsOf: fixture.campaignURL(projectID: projectID))
        }

        private func readOnlyText(_ identifier: String, fixture: CampaignPanelFixture) async throws -> String {
            let control = try await fixture.control(identifier)
            let view = try #require(control as? NSTextView)
            #expect(view.window === fixture.window.attachedSheet)
            #expect(!view.isEditable && view.isSelectable && !view.isRichText)
            return view.string
        }

        private func expectText(_ identifier: String, contains fragments: [String], fixture: CampaignPanelFixture) async throws {
            _ = try await fixture.control(identifier)
            let content = try #require(fixture.window.attachedSheet?.contentView)
            try #require(try await waitForNativeUI(content) {
                guard let element = campaignAXElement(in: content, matching: { $0.accessibilityIdentifier?() == identifier }) else { return false }
                let getter: (() -> Any?)? = element.accessibilityValue
                let text = (getter?() as? String) ?? element.accessibilityLabel?() ?? ""
                return fragments.allSatisfy { text.localizedCaseInsensitiveContains($0) }
            }, "Expected readable checklist evidence \(fragments) in \(identifier).")
        }

        private func expectAbsent(_ identifier: String, fixture: CampaignPanelFixture) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            #expect(try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } == nil
            })
        }

        private func selectMenu(_ identifier: String, fixture: CampaignPanelFixture,
                                matching: (String) -> Bool) async throws {
            let element = try await fixture.control(identifier)
            let popup: NSPopUpButton
            if let button = element as? NSPopUpButton { popup = button }
            else {
                let cell = try #require(element as? NSPopUpButtonCell)
                popup = try #require(cell.controlView as? NSPopUpButton)
                try #require(popup.cell === cell)
            }
            try #require(popup.window === fixture.window.attachedSheet && popup.isEnabled)
            let menu = try #require(popup.menu)
            menu.update()
            let matches = menu.items.filter { matching($0.title) }
            let item = try #require(matches.count == 1 ? matches.first : nil)
            let index = try #require(menu.items.firstIndex { $0 === item })
            try #require(popup.menu === menu && item.menu === menu && menu.item(at: index) === item)
            try #require(item.isEnabled && item.action != nil)
            menu.performActionForItem(at: index)
        }

        private func selectBaseline(_ baseline: CampaignBaseline, fixture: CampaignPanelFixture) async throws {
            try await selectMenu("campaign.baseline.picker", fixture: fixture) { $0.hasPrefix(baseline.name + " · ") }
            try await expectText("campaign.approval.baseline.id", contains: [baseline.id.uuidString], fixture: fixture)
        }

        private func setDuration(_ duration: Int, deliverableID: UUID, fixture: CampaignPanelFixture) async throws {
            let current = try #require(try fixture.ledger().draft.deliverables.first { $0.id == deliverableID }?.durationSeconds)
            try #require(duration >= current)
            for previous in current..<duration {
                let stepper = try await fixture.control("campaign.deliverable.duration.\(deliverableID)")
                try #require(stepper.isAccessibilityEnabled?() == true)
                try #require(stepper.accessibilityPerformIncrement?() == true,
                             "The identified duration stepper must accept its public native increment action.")
                try await fixture.expectLedger {
                    $0.draft.deliverables.first { $0.id == deliverableID }?.durationSeconds == previous + 1
                }
            }
        }

        private func expectDecisionSummary(for baseline: CampaignBaseline, creativeCount: Int,
                                           historical: Bool, fixture: CampaignPanelFixture) async throws {
            // Assert visible scope wording, never a universal 'approved' badge
            // or an assertion against only the domain model.
            try await expectText("campaign.review.row.decisions.summary",
                contains: ["selected baseline only", "creative \(creativeCount)", "production 0", "spend 0"], fixture: fixture)
            try await expectText("campaign.review.row.decisions.details", contains: [baseline.id.uuidString, "do not verify identity", "authorize spending"], fixture: fixture)
            if historical {
                try await expectText("campaign.review.row.decisions.details", contains: ["historical"], fixture: fixture)
            } else {
                let details = try await fixture.control("campaign.review.row.decisions.details")
                let getter: (() -> Any?)? = details.accessibilityValue
                let text = (getter?() as? String) ?? details.accessibilityLabel?() ?? ""
                #expect(!text.localizedCaseInsensitiveContains("Historical records"))
            }
        }
    }
}
