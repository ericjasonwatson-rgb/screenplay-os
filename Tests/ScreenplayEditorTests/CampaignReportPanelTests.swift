import AppKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

extension CampaignPanelLifecycleTests {
    /// Hosted native review acceptance. Synthetic setup creates saved context;
    /// every report option, preview, cancellation and save uses the real control.
    /// An injected destination chooser is not NSSavePanel acceptance coverage.
    @Suite("Campaign review before report export", .serialized)
    @MainActor
    struct CampaignReportPanelTests {
        private let sourceCanary = "SYNTHETIC_SOURCE_SECRET Cafe\u{0301}\r\nPrivate second line 🧪"
        private let reviewerCanary = "SYNTHETIC_REVIEWER_SECRET"
        private let reviewCanary = "SYNTHETIC_REVIEW_NOTE_SECRET"
        private let citationCanary = "SYNTHETIC_CITATION_SECRET"

        @Test func summaryDefaultsToNoPayloadAndFullEvidenceRequiresExplicitNativeChoice() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectFullEvidence(fixture, false)
            let summary = try await previewText(fixture)
            for secret in [sourceCanary, reviewerCanary, reviewCanary, citationCanary] {
                #expect(!summary.contains(secret))
            }
            #expect(!summary.contains("Before evidence (") && !summary.contains("After evidence ("))
            #expect(summary.contains(seed.second.id.uuidString))
            #expect(try savedBytes(fixture) == seed.bytes)
            try await fixture.press("campaign.report.includeFullEvidence")
            try await expectFullEvidence(fixture, true)
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            let full = try await previewText(fixture)
            for secret in [sourceCanary, reviewerCanary, reviewCanary, citationCanary] {
                #expect(Data(full.utf8).range(of: Data(secret.utf8)) != nil,
                        "Full evidence must retain exact synthetic UTF-8, including combining accents and CRLF.")
            }
            #expect(full.contains("Before evidence (") && full.contains("After evidence ("))
            #expect(try savedBytes(fixture) == seed.bytes)
            #expect(try fixture.ledger() == seed.ledger)
            #expect(fixture.model.document == seed.document)
        }

        @Test func cancelTabCloseEscapeAndReopenDiscardReportAndEvidenceOptIn() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            for dismissal in [Dismissal.cancel, .tab, .close, .escape] {
                try await expectFullEvidence(fixture, false)
                try await fixture.press("campaign.report.includeFullEvidence")
                _ = try await previewText(fixture)
                switch dismissal {
                case .cancel: try await fixture.press("campaign.report.cancel")
                case .tab:
                    try await fixture.selectTab("Brief & Deliverables")
                    try await fixture.selectTab("Baseline & Changes")
                case .close, .escape:
                    if dismissal == .close {
                        try await fixture.press("campaign.close")
                    } else {
                        let sheet = try #require(fixture.window.attachedSheet)
                        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                            modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                        #expect(sheet.performKeyEquivalent(with: event))
                    }
                    try await fixture.expectDismissed()
                    _ = try await fixture.open()
                    try await fixture.selectTab("Baseline & Changes")
                }
                try await expectAbsent(fixture, "campaign.report.save")
                try await expectAbsent(fixture, "campaign.report.text")
                try await expectFullEvidence(fixture, false)
                #expect(try savedBytes(fixture) == seed.bytes)
                #expect(try fixture.ledger() == seed.ledger)
            }
            #expect(fixture.model.document == seed.document)
        }

        @Test func nativeBaselineSelectionAndDraftOrCitationUndoRevokeReport() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            _ = try await previewText(fixture)
            try await selectBaseline(seed.first, fixture: fixture)
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            let earlier = try await previewText(fixture)
            #expect(earlier.contains(seed.first.id.uuidString))
            try await fixture.selectTab("Brief & Deliverables")
            try await fixture.replaceText("campaign.field.Brand", with: "Synthetic revised brand")
            try await fixture.expectLedger { $0.draft.brief.brand == "Synthetic revised brand" }
            try await fixture.selectTab("Baseline & Changes")
            try await expectAbsent(fixture, "campaign.report.save")
            _ = try await previewText(fixture)
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == seed.ledger }
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")

            try await fixture.selectTab("Agency Sources")
            let citation = try #require(seed.ledger.draft.agency?.citations.first)
            try await fixture.press("campaign.agency.removeCitation.\(citation.id)")
            try await fixture.expectLedger { $0.draft.agency?.citations.isEmpty == true }
            try await fixture.selectTab("Baseline & Changes")
            _ = try await previewText(fixture)
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == seed.ledger }
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            #expect(try savedBytes(fixture) == seed.bytes)
        }

        @Test func externalScreenplaySourceEditRevokesDisplayedReportWithoutChangingCampaign() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            _ = try await previewText(fixture)
            // External source-change event, not a replacement for any report
            // action. Preview and its invalidated controls are still native UI.
            fixture.model.replaceWritingText(
                in: NSRange(location: 0, length: (fixture.model.writingText as NSString).length),
                with: "INT. SYNTHETIC ROOM - NIGHT\nA revised source invalidates the reviewed report.")
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            #expect(fixture.model.document != seed.document)
            #expect(try savedBytes(fixture) == seed.bytes)
            #expect(try fixture.ledger() == seed.ledger)
            try await fixture.press("campaign.report.includeFullEvidence")
            let fresh = try await previewText(fixture)
            #expect(fresh.contains("A revised source invalidates the reviewed report."))
        }

        @Test func nativeSaveWritesExactlyDisplayedUTF8AndChooserCancelKeepsReview() async throws {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Synthetic-reviewed-report-\(UUID()).txt")
            defer { try? FileManager.default.removeItem(at: destination) }
            var chooseCount = 0
            var writeCount = 0
            var written: Data?
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: {
                chooseCount += 1
                return chooseCount == 1 ? nil : destination
            }, write: { data, url, previous in
                writeCount += 1
                #expect(url == destination && previous == nil)
                written = data
                try DocumentFileWriter.write(data, to: url, overwriteExisting: false, expectedExistingData: nil)
            })
            let fixture = try CampaignPanelFixture(reportExportLifecycle: lifecycle)
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await fixture.press("campaign.report.includeFullEvidence")
            let shown = try await previewText(fixture)
            let displayed = Data(shown.utf8)
            try await fixture.press("campaign.report.save")
            #expect(chooseCount == 1 && writeCount == 0)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            let remaining = try #require(try await fixture.control("campaign.report.text") as? NSTextView)
            #expect(Data(remaining.string.utf8) == displayed)
            try await fixture.press("campaign.report.save")
            #expect(chooseCount == 2 && writeCount == 1)
            #expect(written == displayed)
            #expect(try Data(contentsOf: destination) == displayed)
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            try await expectFullEvidence(fixture, false)
            #expect(try savedBytes(fixture) == seed.bytes)
            #expect(try fixture.ledger() == seed.ledger)
            #expect(fixture.model.document == seed.document)
        }

        @Test func projectReplacementDuringDestinationChoiceRevokesNativeSave() async throws {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Synthetic-revoked-report-\(UUID()).txt")
            defer { try? FileManager.default.removeItem(at: destination) }
            var owner: CampaignPanelFixture?
            var chooseCount = 0
            var writeCount = 0
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: {
                chooseCount += 1
                // Simulates an external lifecycle event during the modal chooser.
                // The real Save control is still the report action under test.
                owner?.model.newDocument()
                return destination
            }, write: { _, _, _ in writeCount += 1 })
            let fixture = try CampaignPanelFixture(reportExportLifecycle: lifecycle)
            owner = fixture
            defer { owner = nil; fixture.close() }
            let seed = try seed(fixture)
            let originalURL = try #require(fixture.model.saveURL)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            _ = try await previewText(fixture)
            try await fixture.press("campaign.report.save")
            #expect(chooseCount == 1 && writeCount == 0)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            let replacementID = try #require(fixture.model.document?.project.id)
            #expect(replacementID != seed.ledger.projectID)
            try await fixture.expectDismissed()
            #expect(try Data(contentsOf: fixture.campaignURL(projectID: seed.ledger.projectID)) == seed.bytes)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))
            fixture.model.loadScreenplayOSDocument(at: originalURL)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await expectAbsent(fixture, "campaign.report.save")
            try await expectAbsent(fixture, "campaign.report.text")
            try await expectFullEvidence(fixture, false)
            #expect(try savedBytes(fixture) == seed.bytes)
        }

        private enum Dismissal { case cancel, tab, close, escape }
        private struct Seed {
            let first: CampaignBaseline
            let second: CampaignBaseline
            let ledger: CampaignLedger
            let bytes: Data
            let document: ScreenplayOSDocument
        }

        private func seed(_ fixture: CampaignPanelFixture) throws -> Seed {
            let document = try #require(fixture.model.document)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: fixture.root)
            let hero = CampaignDeliverable(name: "Synthetic report hero", durationSeconds: 30)
            session.updateDraft {
                $0.brief = .init(brand: "Synthetic report campaign", objective: "Private local report review")
                $0.deliverables = [hero]
            }
            let firstID = try #require(session.freeze(name: "Synthetic report baseline A", document: document))
            let secondID = try #require(session.freeze(name: "Synthetic report baseline B", document: document))
            try #require(session.importAgencyText(.init(filename: "Synthetic.txt",
                bytes: Data(sourceCanary.utf8), text: sourceCanary), revisingDocumentID: nil))
            let revision = try #require(session.ledger.draft.agency?.revisions.last)
            try #require(session.reviewAgencyRevision(revision.id, reviewer: reviewerCanary, note: reviewCanary))
            try #require(session.citeAgencyRevision(revision.id, firstLine: 1, lastLine: 2,
                targetKind: .deliverable, targetID: hero.id, note: citationCanary))
            let first = try #require(session.ledger.baselines.first { $0.id == firstID })
            let second = try #require(session.ledger.baselines.first { $0.id == secondID })
            return .init(first: first, second: second, ledger: session.ledger,
                         bytes: try savedBytes(fixture), document: document)
        }

        private func savedBytes(_ fixture: CampaignPanelFixture) throws -> Data {
            let id = try #require(fixture.model.document?.project.id)
            return try Data(contentsOf: fixture.campaignURL(projectID: id))
        }

        private func previewText(_ fixture: CampaignPanelFixture) async throws -> String {
            try await fixture.press("campaign.report.preview")
            _ = try await fixture.control("campaign.report.save")
            let control = try await fixture.control("campaign.report.text")
            let text = try #require(control as? NSTextView)
            try #require(text.window === fixture.window.attachedSheet)
            #expect(!text.isEditable && text.isSelectable && !text.isRichText)
            return text.string
        }

        private func expectAbsent(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            #expect(try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } == nil
            })
        }

        private func expectFullEvidence(_ fixture: CampaignPanelFixture, _ selected: Bool) async throws {
            _ = try await fixture.control("campaign.report.includeFullEvidence")
            let content = try #require(fixture.window.attachedSheet?.contentView)
            try #require(try await waitForNativeUI(content) {
                guard let control = campaignAXElement(in: content, matching: {
                    $0.accessibilityIdentifier?() == "campaign.report.includeFullEvidence"
                }) else { return false }
                let getter: (() -> Any?)? = control.accessibilityValue
                return (getter?() as? NSNumber)?.boolValue == selected
            }, "The native evidence toggle must expose its actual selected state.")
        }

        private func selectBaseline(_ baseline: CampaignBaseline, fixture: CampaignPanelFixture) async throws {
            let element = try await fixture.control("campaign.baseline.picker")
            let popup: NSPopUpButton
            if let control = element as? NSPopUpButton { popup = control }
            else {
                let cell = try #require(element as? NSPopUpButtonCell)
                popup = try #require(cell.controlView as? NSPopUpButton)
                try #require(popup.cell === cell)
            }
            try #require(popup.window === fixture.window.attachedSheet && popup.isEnabled)
            let menu = try #require(popup.menu)
            menu.update()
            let matches = menu.items.filter { $0.title.hasPrefix(baseline.name + " · ") }
            let item = try #require(matches.count == 1 ? matches.first : nil)
            let index = try #require(menu.items.firstIndex { $0 === item })
            try #require(popup.menu === menu && item.menu === menu && menu.item(at: index) === item)
            try #require(item.isEnabled && item.action != nil)
            menu.performActionForItem(at: index)
            let content = try #require(fixture.window.attachedSheet?.contentView)
            try #require(try await waitForNativeUI(content) {
                guard let current = campaignAXElement(in: content, matching: {
                    $0.accessibilityIdentifier?() == "campaign.approval.baseline.id"
                }) else { return false }
                let getter: (() -> Any?)? = current.accessibilityValue
                return ((getter?() as? String) ?? current.accessibilityLabel?() ?? "").contains(baseline.id.uuidString)
            })
        }
    }
}
