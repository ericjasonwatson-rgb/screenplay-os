import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign safe backup recovery commands")
struct CampaignBackupRecoverySessionTests {
    private struct Fixture {
        let root: URL
        let document: ScreenplayOSDocument
        let session: CampaignWorkspaceSession
        let ledgerURL: URL
        let backupURL: URL
        let context: CampaignRecoveryContext
    }

    @MainActor private func fixture() throws -> Fixture {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let screenplay = Screenplay(metadata: .init(title: "Synthetic recovery"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic recovery", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        let ledgerURL = try CampaignWorkspaceStore.url(projectID: document.project.id, root: root)
        let sourceURL = root.appendingPathComponent("source.screenplayos")
        try Data("Synthetic screenplay bytes".utf8).write(to: sourceURL)
        let backupURL = root.appendingPathComponent("chosen-backup.json")
        var backup = CampaignLedger(projectID: document.project.id)
        backup.draft.brief.brand = "Backup brand"
        backup.draft.brief.objective = "Backup objective"
        backup.draft.deliverables = [.init(name: "Backup hero")]
        let baseline = try backup.freeze(name: "Backup baseline", document: document)
        try backup.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Synthetic reviewer",
                                  evidence: "Synthetic historical evidence", document: document)
        try CampaignWorkspaceStore.encoded(backup).write(to: backupURL)
        return Fixture(root: root, document: document, session: session, ledgerURL: ledgerURL,
            backupURL: backupURL, context: .init(projectID: document.project.id,
                presentationID: UUID(), sourceURL: sourceURL))
    }

    @MainActor private func restoreLifecycle(_ f: Fixture) -> CampaignBackupRestoreLifecycle {
        .init(chooseSource: { f.backupURL }, read: CampaignWorkspaceStore.readBackup,
              restore: CampaignBackupRestoreLifecycle.live.restore)
    }

    @MainActor private func preview(_ f: Fixture) throws -> CampaignBackupRestorePreview {
        try #require(f.session.previewBackupRestore(lifecycle: restoreLifecycle(f)) { f.context })
    }

    @MainActor private func createLocalHistory(_ f: Fixture) throws {
        f.session.updateDraft {
            $0.brief.brand = "New local brand"; $0.brief.objective = "New local objective"
            $0.deliverables = [.init(name: "Local hero")]
        }
        let baseline = try #require(f.session.freeze(name: "New local baseline", document: f.document))
        try #require(f.session.record(baselineID: baseline, scope: .creative, approver: "Local reviewer",
            evidence: "Local evidence", document: f.document, amount: "", currency: ""))
    }

    @MainActor @Test func modalCreatedLocalHistoryCannotBeReplacedBySelectedBackup() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var reads = 0, writes = 0
        let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: {
            try? createLocalHistory(f)
            return f.backupURL
        }, read: { url in reads += 1; return try CampaignWorkspaceStore.readBackup(url) },
            restore: { ledger, url in writes += 1; return try CampaignBackupRestoreLifecycle.live.restore(ledger, url) })
        #expect(f.session.previewBackupRestore(lifecycle: lifecycle) { f.context } == nil)
        #expect(reads == 0 && writes == 0)
        #expect(f.session.ledger.draft.brief.brand == "New local brand")
        #expect(f.session.ledger.baselines.count == 1 && f.session.ledger.decisions.count == 1)
        #expect(f.session.canUndoDraft)
        let disk = try CampaignWorkspaceStore.load(projectID: f.document.project.id, from: f.ledgerURL)
        #expect(try CampaignWorkspaceStore.encoded(disk.ledger) == CampaignWorkspaceStore.encoded(f.session.ledger))
        let baselineID = f.session.ledger.baselines[0].id, decisionID = f.session.ledger.decisions[0].id
        f.session.undoDraft()
        #expect(f.session.ledger.baselines[0].id == baselineID)
        #expect(f.session.ledger.decisions[0].id == decisionID)
    }

    @MainActor @Test func previewDoesNotWriteAndConfirmationUsesFrozenSelectedBytes() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let selected = try CampaignWorkspaceStore.readBackup(f.backupURL)
        let pending = try preview(f)
        #expect(!FileManager.default.fileExists(atPath: f.ledgerURL.path))
        #expect(pending.filename == "chosen-backup.json")
        #expect(pending.projectID == f.document.project.id)
        #expect(pending.byteCount == selected.count)
        #expect(pending.baselineCount == 1 && pending.decisionCount == 1)
        #expect(!pending.disclosure.contains("Synthetic historical evidence"))
        try Data("Changed after preview".utf8).write(to: f.backupURL)
        #expect(f.session.confirmBackupRestore(pending) { f.context })
        let imported = try CampaignWorkspaceStore.decode(selected, projectID: f.document.project.id)
        #expect(try CampaignWorkspaceStore.encoded(f.session.ledger) == CampaignWorkspaceStore.encoded(imported))
        #expect(f.session.restorePreview == nil)
        #expect(!f.session.canUndoDraft)
        #expect(!f.session.confirmBackupRestore(pending) { f.context })
        #expect(try Data(contentsOf: f.context.sourceURL!) == Data("Synthetic screenplay bytes".utf8))
    }

    @MainActor @Test func cancelledInvalidAndWrongProjectBackupsNeverWriteOrKeepOldPreview() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        for input in [Data("{broken".utf8), try CampaignWorkspaceStore.encoded(CampaignLedger(projectID: UUID())),
                      Data(repeating: 32, count: CampaignWorkspaceStore.maximumBytes + 1)] {
            _ = try preview(f)
            let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: { f.backupURL }, read: { _ in input },
                restore: { _, _ in Issue.record("Invalid backup reached writer"); return Data() })
            #expect(f.session.previewBackupRestore(lifecycle: lifecycle) { f.context } == nil)
            #expect(f.session.restorePreview == nil)
            #expect(f.session.problem != nil)
        }
        _ = try preview(f)
        let cancelled = CampaignBackupRestoreLifecycle(chooseSource: { nil }, read: { _ in
            Issue.record("Cancelled chooser reached read"); return Data()
        }, restore: CampaignBackupRestoreLifecycle.live.restore)
        #expect(f.session.previewBackupRestore(lifecycle: cancelled) { f.context } == nil)
        #expect(f.session.restorePreview == nil)
        #expect(!FileManager.default.fileExists(atPath: f.ledgerURL.path))
    }

    @MainActor @Test func restoreContextReplacementAndRevocationDuringPickerOrReadFailClosed() throws {
        for change in 0..<5 {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            var context: CampaignRecoveryContext? = f.context
            var reads = 0
            let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: {
                switch change {
                case 0: context = nil
                case 1: context = .init(projectID: UUID(), presentationID: f.context.presentationID, sourceURL: f.context.sourceURL)
                case 2: context = .init(projectID: f.context.projectID, presentationID: UUID(), sourceURL: f.context.sourceURL)
                case 3: f.session.discardRestorePreview()
                default: break
                }
                return f.backupURL
            }, read: { url in
                reads += 1
                f.session.discardRestorePreview()
                return try CampaignWorkspaceStore.readBackup(url)
            }, restore: CampaignBackupRestoreLifecycle.live.restore)
            #expect(f.session.previewBackupRestore(lifecycle: lifecycle) { context } == nil)
            #expect(reads == (change == 4 ? 1 : 0))
            #expect(f.session.restorePreview == nil)
            #expect(!FileManager.default.fileExists(atPath: f.ledgerURL.path))
        }
    }

    @MainActor @Test func confirmationChecksNewHistoryAndContextAgainAtCommitBoundary() throws {
        for change in 0..<5 {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let pending = try preview(f)
            var calls = 0, writes = 0
            let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: { nil }, read: CampaignWorkspaceStore.readBackup,
                restore: { _, _ in writes += 1; return Data() })
            #expect(!f.session.confirmBackupRestore(pending, lifecycle: lifecycle) {
                calls += 1
                if calls == 2 {
                    switch change {
                    case 0: try? createLocalHistory(f)
                    case 1: f.session.discardRestorePreview()
                    case 2: return nil
                    case 3: return .init(projectID: UUID(), presentationID: f.context.presentationID, sourceURL: f.context.sourceURL)
                    default: return .init(projectID: f.context.projectID, presentationID: UUID(), sourceURL: f.context.sourceURL)
                    }
                }
                return f.context
            })
            #expect(writes == 0)
            if change == 0 {
                #expect(f.session.ledger.baselines.count == 1 && f.session.ledger.decisions.count == 1)
                #expect(f.session.canUndoDraft)
            } else { #expect(!FileManager.default.fileExists(atPath: f.ledgerURL.path)) }
        }
    }

    @MainActor @Test func externalWriterBeforeAfterAndInsideRestoreCommitPreservesItsLedger() throws {
        for phase in 0..<4 {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let other = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
            func externalEdit() { other.updateDraft { $0.brief.brand = "External writer" } }
            if phase == 0 { externalEdit() }
            var choices = 0
            let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: {
                choices += 1
                if phase == 1 { externalEdit() }
                return f.backupURL
            }, read: CampaignWorkspaceStore.readBackup, restore: { ledger, url in
                externalEdit()
                return try CampaignBackupRestoreLifecycle.live.restore(ledger, url)
            })
            let pending = f.session.previewBackupRestore(lifecycle: lifecycle) { f.context }
            if phase < 2 { #expect(pending == nil) }
            else {
                let pending = try #require(pending)
                if phase == 2 { externalEdit() }
                #expect(!f.session.confirmBackupRestore(pending, lifecycle: lifecycle) { f.context })
                #expect(f.session.restorePreview == nil)
            }
            #expect(choices == (phase == 0 ? 0 : 1))
            let disk = try CampaignWorkspaceStore.load(projectID: f.document.project.id, from: f.ledgerURL)
            #expect(disk.ledger.draft.brief.brand == "External writer")
            #expect(f.session.ledger.draft.brief.brand.isEmpty)
        }
    }

    @MainActor @Test func failedRestoreRetainsExactPreviewForExplicitRetry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f)
        var writes = 0
        let failure = CampaignBackupRestoreLifecycle(chooseSource: { nil }, read: CampaignWorkspaceStore.readBackup,
            restore: { _, _ in writes += 1; throw CampaignWorkspaceStore.Failure.writeFailed })
        #expect(!f.session.confirmBackupRestore(pending, lifecycle: failure) { f.context })
        #expect(writes == 1)
        #expect(f.session.restorePreview?.id == pending.id)
        #expect(f.session.ledger.draft.brief.brand.isEmpty)
        #expect(!f.session.canUndoDraft)
        #expect(!FileManager.default.fileExists(atPath: f.ledgerURL.path))
        #expect(f.session.confirmBackupRestore(pending) { f.context })
        #expect(f.session.ledger.draft.brief.brand == "Backup brand")
    }

    @MainActor @Test func fileCommandsCannotReenterRestoreOrPrivateExport() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var choices = 0, writes = 0
        let nestedExport = CampaignPrivateExportLifecycle(chooseDestination: {
            choices += 1; return f.root.appendingPathComponent("unexpected.json")
        }, write: { _, _, _ in writes += 1 })
        let nestedRestore = CampaignBackupRestoreLifecycle(chooseSource: {
            choices += 1; return f.backupURL
        }, read: CampaignWorkspaceStore.readBackup, restore: CampaignBackupRestoreLifecycle.live.restore)
        let lifecycle = CampaignBackupRestoreLifecycle(chooseSource: {
            #expect(f.session.isPerformingRecoveryCommand)
            #expect(f.session.previewBackupRestore(lifecycle: nestedRestore) { f.context } == nil)
            #expect(!f.session.exportBackup(lifecycle: nestedExport) { f.context })
            #expect(!f.session.exportAgencyOriginal(UUID(), lifecycle: nestedExport) { f.context })
            return f.backupURL
        }, read: CampaignWorkspaceStore.readBackup, restore: CampaignBackupRestoreLifecycle.live.restore)
        let pending = try #require(f.session.previewBackupRestore(lifecycle: lifecycle) { f.context })
        #expect(!f.session.isPerformingRecoveryCommand)
        let nestedConfirm = CampaignPrivateExportLifecycle(chooseDestination: {
            #expect(!f.session.confirmBackupRestore(pending) { f.context })
            #expect(!f.session.exportBackup(lifecycle: nestedExport) { f.context })
            return nil
        }, write: { _, _, _ in writes += 1 })
        #expect(!f.session.exportBackup(lifecycle: nestedConfirm) { f.context })
        #expect(choices == 0 && writes == 0)
        #expect(f.session.restorePreview?.id == pending.id)
    }

    @MainActor private func addRetainedOriginal(_ f: Fixture) throws -> Data {
        // Synthetic provenance bytes exercise retention, not Office parsing.
        let original = Data([0x50, 0x4b, 0x03, 0x04, 0x41, 0x42, 0x43])
        let text = "Synthetic Cafe\u{0301} source"
        let origin = try CampaignAgencyDocumentOrigin(format: "docx", originalBytes: original,
            sections: [text], extractor: "docx-body-text-v1", notices: ["Synthetic local fixture only."])
        try #require(f.session.importAgencyText(.init(filename: "Synthetic.docx", bytes: Data(text.utf8),
            text: text, origin: origin), revisingDocumentID: nil))
        return original
    }

    @MainActor private func export(_ f: Fixture, original: Bool, lifecycle: CampaignPrivateExportLifecycle,
                                   currentContext: () -> CampaignRecoveryContext?) -> Bool {
        if original, let id = f.session.ledger.draft.agency?.revisions.first?.id {
            return f.session.exportAgencyOriginal(id, lifecycle: lifecycle, currentContext: currentContext)
        }
        return f.session.exportBackup(lifecycle: lifecycle, currentContext: currentContext)
    }

    @MainActor @Test func privateCopiesPreserveExactBytesAndCanonicalStateAcrossCancelFailureRetry() throws {
        for original in [false, true] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let originalBytes = try addRetainedOriginal(f)
            let before = try CampaignWorkspaceStore.encoded(f.session.ledger)
            let beforeDisk = try Data(contentsOf: f.ledgerURL), undo = f.session.canUndoDraft
            let destination = f.root.appendingPathComponent(original ? "original.docx" : "backup.json")
            var writes = 0
            let cancelled = CampaignPrivateExportLifecycle(chooseDestination: { nil }, write: { _, _, _ in writes += 1 })
            #expect(!export(f, original: original, lifecycle: cancelled) { f.context })
            #expect(writes == 0)
            let failure = CampaignPrivateExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in
                writes += 1; throw DocumentSaveError.changedOnDisk
            })
            #expect(!export(f, original: original, lifecycle: failure) { f.context })
            #expect(writes == 1)
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            let retry = CampaignPrivateExportLifecycle(chooseDestination: { destination },
                write: CampaignReportExportLifecycle.live.write)
            #expect(export(f, original: original, lifecycle: retry) { f.context })
            #expect(try Data(contentsOf: destination) == (original ? originalBytes : before))
            #expect(try CampaignWorkspaceStore.encoded(f.session.ledger) == before)
            #expect(try Data(contentsOf: f.ledgerURL) == beforeDisk)
            #expect(f.session.canUndoDraft == undo)
            #expect(!f.session.isPerformingRecoveryCommand)
        }
    }

    @MainActor @Test func privateExportsRejectLiveContextLeaseAndExactUnicodeChangesAfterPicker() throws {
        for original in [false, true] {
            for change in 0..<7 {
                let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
                _ = try addRetainedOriginal(f)
                f.session.updateDraft { $0.brief.brand = "Caf\u{00E9}" }
                let other = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
                var context: CampaignRecoveryContext? = f.context
                var writes = 0
                let lifecycle = CampaignPrivateExportLifecycle(chooseDestination: {
                    switch change {
                    case 0: context = nil
                    case 1: context = .init(projectID: UUID(), presentationID: f.context.presentationID, sourceURL: f.context.sourceURL)
                    case 2: context = .init(projectID: f.context.projectID, presentationID: UUID(), sourceURL: f.context.sourceURL)
                    case 3: context = .init(projectID: f.context.projectID, presentationID: f.context.presentationID,
                        sourceURL: f.root.appendingPathComponent("replacement.screenplayos"))
                    case 4: f.session.updateDraft { $0.brief.brand = "Cafe\u{0301}" }
                    case 5: f.session.discardRestorePreview()
                    default: other.updateDraft { $0.brief.brand = "External change" }
                    }
                    return f.root.appendingPathComponent("copy.json")
                }, write: { _, _, _ in writes += 1 })
                #expect(!export(f, original: original, lifecycle: lifecycle) { context })
                #expect(writes == 0)
                #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("copy.json").path))
                if change == 4 {
                    #expect(Data(f.session.ledger.draft.brief.brand.utf8) == Data("Cafe\u{0301}".utf8))
                }
            }
        }
    }

    @MainActor @Test func privateExportsCheckLeaseBeforePickerAndAgainImmediatelyBeforeWrite() throws {
        for original in [false, true] {
            for before in [false, true] {
                let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
                _ = try addRetainedOriginal(f)
                let other = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
                if before { other.updateDraft { $0.brief.brand = "Earlier external change" } }
                var choices = 0, calls = 0, writes = 0
                let lifecycle = CampaignPrivateExportLifecycle(chooseDestination: {
                    choices += 1; return f.root.appendingPathComponent("copy.json")
                }, write: { _, _, _ in writes += 1 })
                #expect(!export(f, original: original, lifecycle: lifecycle) {
                    calls += 1
                    if !before && calls == 4 { other.updateDraft { $0.brief.brand = "Late external change" } }
                    return f.context
                })
                #expect(choices == (before ? 0 : 1))
                #expect(writes == 0)
            }
        }
    }

    @MainActor @Test func privateExportsRejectProtectedAliasesHardLinksAndUnboundedDestinations() throws {
        for original in [false, true] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            _ = try addRetainedOriginal(f)
            let screenplayURL = try #require(f.context.sourceURL)
            let ledgerBytes = try Data(contentsOf: f.ledgerURL), sourceBytes = try Data(contentsOf: screenplayURL)
            let ledgerLink = f.root.appendingPathComponent("ledger-hardlink.json")
            let sourceLink = f.root.appendingPathComponent("source-hardlink.json")
            let ledgerAlias = f.root.appendingPathComponent("ledger-symlink.json")
            let sourceAlias = f.root.appendingPathComponent("source-symlink.json")
            try FileManager.default.linkItem(at: f.ledgerURL, to: ledgerLink)
            try FileManager.default.linkItem(at: screenplayURL, to: sourceLink)
            try FileManager.default.createSymbolicLink(at: ledgerAlias, withDestinationURL: f.ledgerURL)
            try FileManager.default.createSymbolicLink(at: sourceAlias, withDestinationURL: screenplayURL)
            let oversized = f.root.appendingPathComponent("large-destination.json")
            try Data(repeating: 32, count: CampaignWorkspaceStore.maximumBytes + 1).write(to: oversized)
            var writes = 0
            let invalidURL = try #require(URL(string: "https://invalid.example/synthetic.json"))
            for destination in [f.ledgerURL, screenplayURL, ledgerLink, sourceLink, ledgerAlias, sourceAlias,
                                oversized, f.root, invalidURL] {
                let lifecycle = CampaignPrivateExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in writes += 1 })
                #expect(!export(f, original: original, lifecycle: lifecycle) { f.context })
            }
            #expect(writes == 0)
            #expect(try Data(contentsOf: f.ledgerURL) == ledgerBytes)
            #expect(try Data(contentsOf: screenplayURL) == sourceBytes)
        }
    }

    @MainActor @Test func changedExportDestinationPreservedAndNoAutomaticRetry() throws {
        for original in [false, true] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            _ = try addRetainedOriginal(f)
            let destination = f.root.appendingPathComponent("existing-copy.json")
            try Data("Original destination".utf8).write(to: destination)
            var writes = 0
            let lifecycle = CampaignPrivateExportLifecycle(chooseDestination: { destination }, write: { bytes, url, previous in
                writes += 1
                try Data("External replacement".utf8).write(to: url)
                try CampaignReportExportLifecycle.live.write(bytes, url, previous)
            })
            #expect(!export(f, original: original, lifecycle: lifecycle) { f.context })
            #expect(writes == 1)
            #expect(try Data(contentsOf: destination) == Data("External replacement".utf8))
            #expect(f.session.problem != nil)
        }
    }

    @MainActor @Test func reportAndPrivateCopyChoosersShareAReentrancyGuard() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try createLocalHistory(f)
        let baseline = try #require(f.session.ledger.baselines.first)
        let report = try #require(f.session.previewReport(baselineID: baseline.id, document: f.document))
        var unexpectedChoices = 0
        let privateExport = CampaignPrivateExportLifecycle(chooseDestination: {
            unexpectedChoices += 1; return nil
        }, write: { _, _, _ in Issue.record("Reentrant export wrote") })
        let reportExport = CampaignReportExportLifecycle(chooseDestination: {
            #expect(!f.session.exportBackup(lifecycle: privateExport) { f.context })
            return nil
        }, write: { _, _, _ in Issue.record("Cancelled report wrote") })
        #expect(!f.session.saveReviewedReport(report, lifecycle: reportExport) {
            (baseline.id, f.document, f.context.sourceURL)
        })
        let nestedReport = CampaignReportExportLifecycle(chooseDestination: {
            unexpectedChoices += 1; return nil
        }, write: { _, _, _ in Issue.record("Reentrant report wrote") })
        let outerExport = CampaignPrivateExportLifecycle(chooseDestination: {
            #expect(!f.session.saveReviewedReport(report, lifecycle: nestedReport) {
                (baseline.id, f.document, f.context.sourceURL)
            })
            return nil
        }, write: { _, _, _ in Issue.record("Cancelled export wrote") })
        #expect(!f.session.exportBackup(lifecycle: outerExport) { f.context })
        #expect(unexpectedChoices == 0)
        #expect(f.session.reportPreview?.id == report.id)
    }
}
