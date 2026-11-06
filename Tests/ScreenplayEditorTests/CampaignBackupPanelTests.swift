import AppKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

extension CampaignPanelLifecycleTests {
    /// Hosted native controls and sheet lifecycle with injected local choosers.
    /// These tests do not claim NSOpenPanel/NSSavePanel interaction coverage.
    @Suite("Campaign safe backup and restore", .serialized)
    @MainActor
    struct CampaignBackupPanelTests {
        @Test func nativeRestorePreviewsCountsCancelsAndRequiresExplicitConfirmation() async throws {
            let probe = RestoreProbe()
            let fixture = try CampaignPanelFixture(backupRestoreLifecycle: probe.lifecycle)
            defer { fixture.close() }
            let seed = try makeBackup(fixture)
            probe.source = seed.url
            let sourceURL = try #require(fixture.model.saveURL)
            let sourceBytes = try Data(contentsOf: sourceURL)
            let document = fixture.model.document
            _ = try await fixture.open()

            for confirm in [false, true] {
                try await fixture.press("campaign.backup.restore")
                _ = try await fixture.control("campaign.backup.confirm")
                #expect(try await text("campaign.backup.filename", fixture).contains(seed.url.lastPathComponent))
                #expect(try await text("campaign.backup.project", fixture).contains(seed.ledger.projectID.uuidString))
                let history = try await text("campaign.backup.history", fixture)
                #expect(history.contains("1 deliverables") && history.contains("1 assumptions"))
                #expect(history.contains("1 baselines") && history.contains("1 decisions"))
                let sources = try await text("campaign.backup.sources", fixture)
                #expect(sources.contains("1 source documents") && sources.contains("1 source revisions"))
                #expect(sources.contains("1 retained originals"))
                let disclosure = try await text("campaign.backup.disclosure", fixture).lowercased()
                #expect(disclosure.contains("screenplay") && disclosure.contains("media"))
                #expect(disclosure.contains("confidential"))
                #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: seed.ledger.projectID).path))
                #expect(probe.restoreCount == 0)
                try await fixture.press(confirm ? "campaign.backup.confirm" : "campaign.backup.cancel")
                try await expectAbsent(fixture, "campaign.backup.confirm")
                if !confirm {
                    #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: seed.ledger.projectID).path))
                }
            }
            #expect(probe.chooseCount == 2 && probe.restoreCount == 1)
            try await fixture.expectLedger { $0 == seed.ledger }
            #expect(try Data(contentsOf: seed.url) == seed.bytes)
            #expect(fixture.model.document == document)
            #expect(try Data(contentsOf: sourceURL) == sourceBytes)
            let restore = try await fixture.control("campaign.backup.restore")
            #expect(restore.isAccessibilityEnabled?() == false)
            let undo = try await fixture.control("campaign.undo")
            #expect(undo.isAccessibilityEnabled?() == false)
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            try await expectAbsent(fixture, "campaign.backup.confirm")
            #expect(try fixture.ledger() == seed.ledger)
        }

        @Test func tabCloseEscapeAndProjectReplacementDiscardReview() async throws {
            let probe = RestoreProbe()
            let fixture = try CampaignPanelFixture(backupRestoreLifecycle: probe.lifecycle)
            defer { fixture.close() }
            let seed = try makeBackup(fixture)
            probe.source = seed.url
            _ = try await fixture.open()
            for interruption in [Interruption.tab, .close, .escape, .project] {
                try await fixture.press("campaign.backup.restore")
                _ = try await fixture.control("campaign.backup.confirm")
                switch interruption {
                case .tab:
                    try await fixture.selectTab("Bid Assumptions")
                    try await fixture.selectTab("Brief & Deliverables")
                case .close: try await fixture.press("campaign.close")
                case .escape: try escape(fixture)
                case .project: fixture.model.newDocument()
                }
                if interruption != .tab {
                    try await fixture.expectDismissed()
                    _ = try await fixture.open()
                }
                try await expectAbsent(fixture, "campaign.backup.confirm")
                #expect(probe.restoreCount == 0)
                #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: seed.ledger.projectID).path))
            }
            let replacementID = try #require(fixture.model.document?.project.id)
            #expect(replacementID != seed.ledger.projectID)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))
            #expect(try Data(contentsOf: seed.url) == seed.bytes)
        }

        @Test func chooserCancellationAndInterruptedSelectionNeverCreateAReview() async throws {
            for replaceProject in [false, true] {
                let probe = RestoreProbe()
                let fixture = try CampaignPanelFixture(backupRestoreLifecycle: probe.lifecycle)
                defer { probe.beforeChoosing = nil; fixture.close() }
                let seed = try makeBackup(fixture)
                _ = try await fixture.open()
                // Native Restore action with a cancelled injected chooser.
                try await fixture.press("campaign.backup.restore")
                try await expectAbsent(fixture, "campaign.backup.confirm")
                #expect(probe.readCount == 0 && probe.restoreCount == 0)
                probe.source = seed.url
                probe.beforeChoosing = {
                    if replaceProject { fixture.model.newDocument() }
                    else { fixture.model.campaignPresented = false }
                }
                try await fixture.press("campaign.backup.restore")
                try await fixture.expectDismissed()
                #expect(probe.chooseCount == 2 && probe.readCount == 0 && probe.restoreCount == 0)
                probe.beforeChoosing = nil
                _ = try await fixture.open()
                try await expectAbsent(fixture, "campaign.backup.confirm")
                #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: seed.ledger.projectID).path))
            }
        }

        @Test func failedRestoreRetainsValidReviewForExplicitRetry() async throws {
            let probe = RestoreProbe()
            probe.remainingFailures = 1
            let fixture = try CampaignPanelFixture(backupRestoreLifecycle: probe.lifecycle)
            defer { fixture.close() }
            let seed = try makeBackup(fixture)
            probe.source = seed.url
            _ = try await fixture.open()
            try await fixture.press("campaign.backup.restore")
            try await fixture.press("campaign.backup.confirm")
            #expect(probe.restoreCount == 1)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: seed.ledger.projectID).path))
            _ = try await fixture.control("campaign.backup.confirm")
            #expect(try await text("campaign.backup.filename", fixture).contains(seed.url.lastPathComponent))
            try await fixture.press("campaign.backup.confirm")
            try await fixture.expectLedger { $0 == seed.ledger }
            try await expectAbsent(fixture, "campaign.backup.confirm")
            #expect(probe.chooseCount == 1 && probe.restoreCount == 2)
        }

        @Test func existingHistoryDisablesRestoreAndNativeBackupWritesExactLedger() async throws {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-backup-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: destination) }
            let restore = RestoreProbe()
            var writeCount = 0
            let export = CampaignPrivateExportLifecycle(chooseDestination: { destination }, write: { data, url, previous in
                writeCount += 1
                #expect(previous == nil)
                try DocumentFileWriter.write(data, to: url, overwriteExisting: false, expectedExistingData: nil)
            })
            let fixture = try CampaignPanelFixture(backupRestoreLifecycle: restore.lifecycle, privateExportLifecycle: export)
            defer { fixture.close() }
            let seed = try makeBackup(fixture)
            _ = try CampaignWorkspaceStore.save(seed.ledger, to: fixture.campaignURL(projectID: seed.ledger.projectID), expected: nil)
            restore.source = seed.url
            _ = try await fixture.open()
            let button = try await fixture.control("campaign.backup.restore")
            #expect(button.isAccessibilityEnabled?() == false)
            try await fixture.press("campaign.backup.export")
            #expect(writeCount == 1 && restore.chooseCount == 0)
            #expect(try Data(contentsOf: destination) == seed.bytes)
            #expect(try fixture.ledger() == seed.ledger)
        }

        @Test func nativePrivateExportsRejectCloseAndProjectReplacementDuringChooser() async throws {
            for (original, replaceProject) in [(false, false), (false, true), (true, false), (true, true)] {
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-revoked-\(UUID()).data")
                defer { try? FileManager.default.removeItem(at: destination) }
                var owner: CampaignPanelFixture?
                var writeCount = 0
                let export = CampaignPrivateExportLifecycle(chooseDestination: {
                    if replaceProject { owner?.model.newDocument() }
                    else { owner?.model.campaignPresented = false }
                    return destination
                }, write: { _, _, _ in writeCount += 1 })
                let fixture = try CampaignPanelFixture(privateExportLifecycle: export)
                owner = fixture
                defer { owner = nil; fixture.close() }
                let seed = try makeBackup(fixture)
                let saved = try CampaignWorkspaceStore.save(seed.ledger,
                    to: fixture.campaignURL(projectID: seed.ledger.projectID), expected: nil)
                let document = try #require(fixture.model.document)
                let sourceURL = try #require(fixture.model.saveURL)
                let sourceBytes = try Data(contentsOf: sourceURL)
                _ = try await fixture.open()
                if original {
                    try await fixture.selectTab("Agency Sources")
                    let revision = try #require(seed.ledger.draft.agency?.revisions.first)
                    try await fixture.press("campaign.agency.exportOriginal.\(revision.id)")
                } else {
                    try await fixture.press("campaign.backup.export")
                }
                try await fixture.expectDismissed()
                #expect(writeCount == 0 && !FileManager.default.fileExists(atPath: destination.path))
                #expect((fixture.model.document?.project.id != document.project.id) == replaceProject)
                #expect(try Data(contentsOf: sourceURL) == sourceBytes)
                #expect(try Data(contentsOf: fixture.campaignURL(projectID: seed.ledger.projectID)) == saved)
                _ = try await fixture.open()
                try await expectAbsent(fixture, "campaign.backup.confirm")
            }
        }

        @Test func nativePrivateExportsCannotReplaceTheActiveScreenplay() async throws {
            var owner: CampaignPanelFixture?
            var chooseCount = 0
            var writeCount = 0
            let export = CampaignPrivateExportLifecycle(chooseDestination: {
                chooseCount += 1
                return owner?.model.saveURL
            }, write: { _, _, _ in writeCount += 1 })
            let fixture = try CampaignPanelFixture(privateExportLifecycle: export)
            owner = fixture
            defer { owner = nil; fixture.close() }
            let seed = try makeBackup(fixture)
            _ = try CampaignWorkspaceStore.save(seed.ledger,
                to: fixture.campaignURL(projectID: seed.ledger.projectID), expected: nil)
            let sourceURL = try #require(fixture.model.saveURL)
            let sourceBytes = try Data(contentsOf: sourceURL)
            _ = try await fixture.open()
            try await fixture.press("campaign.backup.export")
            try await fixture.selectTab("Agency Sources")
            let revision = try #require(seed.ledger.draft.agency?.revisions.first)
            try await fixture.press("campaign.agency.exportOriginal.\(revision.id)")
            #expect(chooseCount == 2 && writeCount == 0)
            #expect(try Data(contentsOf: sourceURL) == sourceBytes)
            #expect(try fixture.ledger() == seed.ledger)
        }

        @Test func nativeOriginalExportSavesRetainedBytesWithoutChangingCampaign() async throws {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Synthetic-original-\(UUID()).docx")
            defer { try? FileManager.default.removeItem(at: destination) }
            let export = CampaignPrivateExportLifecycle(chooseDestination: { destination }, write: { data, url, previous in
                #expect(previous == nil)
                try DocumentFileWriter.write(data, to: url, overwriteExisting: false, expectedExistingData: nil)
            })
            let fixture = try CampaignPanelFixture(privateExportLifecycle: export)
            defer { fixture.close() }
            let seed = try makeBackup(fixture)
            let revision = try #require(seed.ledger.draft.agency?.revisions.first)
            let original = try #require(revision.origin?.originalBytes)
            _ = try CampaignWorkspaceStore.save(seed.ledger,
                to: fixture.campaignURL(projectID: seed.ledger.projectID), expected: nil)
            let document = fixture.model.document
            _ = try await fixture.open()
            try await fixture.selectTab("Agency Sources")
            try await fixture.press("campaign.agency.exportOriginal.\(revision.id)")
            #expect(try Data(contentsOf: destination) == original)
            #expect(try fixture.ledger() == seed.ledger)
            #expect(fixture.model.document == document)
        }

        private enum Interruption { case tab, close, escape, project }

        private struct Seed {
            let ledger: CampaignLedger
            let url: URL
            let bytes: Data
        }

        private func makeBackup(_ fixture: CampaignPanelFixture) throws -> Seed {
            let document = try #require(fixture.model.document)
            var ledger = CampaignLedger(projectID: document.project.id,
                draft: CampaignDraft(brief: .init(brand: "Synthetic recovery", objective: "Review before restore"),
                    deliverables: [.init(name: "Synthetic hero")], assumptions: [.init(text: "Synthetic assumption")]))
            let baseline = try ledger.freeze(name: "Synthetic saved baseline", document: document)
            _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative,
                approver: "Synthetic producer", evidence: "Synthetic local record", document: document)
            // Synthetic provenance bytes, not an extraction or Word-compatibility test.
            let origin = try CampaignAgencyDocumentOrigin(format: "docx",
                originalBytes: Data([0x50, 0x4b, 0x03, 0x04]) + Data("Synthetic original fixture".utf8),
                sections: ["Synthetic confidential agency text"], extractor: "docx-body-text-v1",
                notices: ["Synthetic extraction needs original-document review."])
            _ = try ledger.draft.importAgencyDocument(origin: origin, filename: "Synthetic.docx")
            let bytes = try CampaignWorkspaceStore.encoded(ledger)
            let url = fixture.root.appendingPathComponent("Synthetic-campaign-backup.json")
            try bytes.write(to: url)
            return Seed(ledger: ledger, url: url, bytes: bytes)
        }

        private func text(_ identifier: String, _ fixture: CampaignPanelFixture) async throws -> String {
            let control = try await fixture.control(identifier)
            let getter: (() -> Any?)? = control.accessibilityValue
            return (getter?() as? String) ?? control.accessibilityLabel?() ?? ""
        }

        private func expectAbsent(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            #expect(try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } == nil
            })
        }

        private func escape(_ fixture: CampaignPanelFixture) throws {
            let sheet = try #require(fixture.window.attachedSheet)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            #expect(sheet.performKeyEquivalent(with: event))
        }

        @MainActor
        private final class RestoreProbe {
            var source: URL?
            var beforeChoosing: (() -> Void)?
            var chooseCount = 0
            var readCount = 0
            var restoreCount = 0
            var remainingFailures = 0

            var lifecycle: CampaignBackupRestoreLifecycle {
                CampaignBackupRestoreLifecycle(chooseSource: {
                    self.chooseCount += 1
                    self.beforeChoosing?()
                    return self.source
                }, read: {
                    self.readCount += 1
                    return try CampaignWorkspaceStore.readBackup($0)
                }, restore: { ledger, url in
                    self.restoreCount += 1
                    if self.remainingFailures > 0 {
                        self.remainingFailures -= 1
                        throw CampaignError.invalid("Synthetic restore failure; retry explicitly.")
                    }
                    return try CampaignBackupRestoreLifecycle.live.restore(ledger, url)
                })
            }
        }
    }
}
