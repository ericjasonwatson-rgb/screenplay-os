import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign reviewed report export")
struct CampaignReportExportSessionTests {
    private struct Fixture {
        let session: CampaignWorkspaceSession
        let document: ScreenplayOSDocument
        let baselineID: UUID
        let root: URL
        let ledgerURL: URL
        var context: (baselineID: UUID, document: ScreenplayOSDocument, sourceURL: URL?) {
            (baselineID, document, nil)
        }
    }

    @MainActor private func fixture() throws -> Fixture {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        let screenplay = Screenplay(metadata: .init(title: "Synthetic report"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic report", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        session.updateDraft {
            $0.brief.brand = "Synthetic brand"; $0.brief.objective = "Synthetic objective"
            $0.deliverables = [.init(name: "Synthetic hero")]
        }
        let baselineID = try #require(session.freeze(name: "Baseline A", document: document))
        let ledgerURL = try CampaignWorkspaceStore.url(projectID: document.project.id, root: root)
        return .init(session: session, document: document, baselineID: baselineID, root: root, ledgerURL: ledgerURL)
    }

    @MainActor private func preview(_ f: Fixture) throws -> CampaignChangeReportPreview {
        try #require(f.session.previewReport(baselineID: f.baselineID, document: f.document))
    }

    @MainActor @Test func exactReviewedBytesSavedOnceWithoutMutatingLedgerOrUndo() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), ledger = f.session.ledger
        let bytes = try Data(contentsOf: f.ledgerURL), undo = f.session.canUndoDraft
        let destination = f.root.appendingPathComponent("report.txt")
        var chosen = 0
        let lifecycle = CampaignReportExportLifecycle(chooseDestination: { chosen += 1; return destination },
            write: CampaignReportExportLifecycle.live.write)
        #expect(f.session.saveReviewedReport(pending, lifecycle: lifecycle) { f.context })
        #expect(try Data(contentsOf: destination) == pending.data)
        #expect(f.session.reportPreview == nil)
        #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) { f.context })
        #expect(chosen == 1)
        #expect(f.session.ledger == ledger)
        #expect(try Data(contentsOf: f.ledgerURL) == bytes)
        #expect(f.session.canUndoDraft == undo)
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(reopened.reportPreview == nil)
    }

    @MainActor @Test func cancellationAndWriteFailureKeepValidPreviewForExplicitRetry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), destination = f.root.appendingPathComponent("report.txt")
        var writes = 0
        let cancelled = CampaignReportExportLifecycle(chooseDestination: { nil }, write: { _, _, _ in writes += 1 })
        #expect(!f.session.saveReviewedReport(pending, lifecycle: cancelled) { f.context })
        #expect(writes == 0)
        #expect(f.session.reportPreview?.id == pending.id)
        let failing = CampaignReportExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in
            writes += 1; throw DocumentSaveError.changedOnDisk
        })
        #expect(!f.session.saveReviewedReport(pending, lifecycle: failing) { f.context })
        #expect(writes == 1)
        #expect(f.session.reportPreview?.id == pending.id)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let retry = CampaignReportExportLifecycle(chooseDestination: { destination }, write: CampaignReportExportLifecycle.live.write)
        #expect(f.session.saveReviewedReport(pending, lifecycle: retry) { f.context })
        #expect(try Data(contentsOf: destination) == pending.data)
    }

    @MainActor @Test func modalRevocationReplacementAndReentrantSaveNeverWriteStalePreview() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = f.root.appendingPathComponent("report.txt")
        var writes = 0
        for replace in [false, true] {
            let pending = try preview(f)
            let nested = CampaignReportExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in writes += 1 })
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: {
                #expect(!f.session.saveReviewedReport(pending, lifecycle: nested) { f.context })
                if replace { _ = f.session.previewReport(baselineID: f.baselineID, document: f.document) }
                else { f.session.discardReportPreview() }
                return destination
            }, write: { _, _, _ in writes += 1 })
            #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) { f.context })
        }
        #expect(writes == 0)
    }

    @MainActor @Test func modalCloseProjectTitleBaselineAndDraftChangesPreventWrite() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = f.root.appendingPathComponent("report.txt")
        let second = try #require(f.session.freeze(name: "Baseline B", document: f.document))
        var writes = 0
        for change in 0..<5 {
            let pending = try preview(f)
            var context: (baselineID: UUID, document: ScreenplayOSDocument, sourceURL: URL?)? = f.context
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: {
                switch change {
                case 0: context = nil
                case 1: context?.baselineID = second
                case 2: context?.document.project.metadata.title = "Renamed"
                case 3:
                    var otherDocument = f.document
                    otherDocument.project = Project(metadata: f.document.project.metadata,
                        screenplayID: f.document.screenplay.id)
                    context?.document = otherDocument
                default: f.session.updateDraft { $0.brief.objective = "Changed during picker" }
                }
                return destination
            }, write: { _, _, _ in writes += 1 })
            #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) { context })
        }
        #expect(writes == 0)
    }

    @MainActor @Test func externalLeaseChangesBeforeAndDuringPickerPreventWrites() throws {
        for during in [false, true] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let pending = try preview(f)
            let other = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
            if !during { other.updateDraft { $0.brief.objective = "External edit" } }
            var choices = 0, writes = 0
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: {
                choices += 1
                other.updateDraft { $0.brief.objective = "External edit during picker" }
                return f.root.appendingPathComponent("report.txt")
            }, write: { _, _, _ in writes += 1 })
            #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) { f.context })
            #expect(choices == (during ? 1 : 0))
            #expect(writes == 0)
            #expect(try CampaignWorkspaceStore.load(projectID: f.document.project.id, from: f.ledgerURL).ledger == other.ledger)
        }
    }

    @MainActor @Test func ownedSourceAndHardLinkCannotBeOverwritten() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), original = try Data(contentsOf: f.ledgerURL)
        let source = f.root.appendingPathComponent("project.screenplayos")
        try Data("Synthetic project bytes".utf8).write(to: source)
        let alias = f.root.appendingPathComponent("alias.txt")
        try FileManager.default.linkItem(at: source, to: alias)
        var writes = 0
        for destination in [f.ledgerURL, source, alias] {
            let lifecycle = CampaignReportExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in writes += 1 })
            #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) {
                (f.baselineID, f.document, source)
            })
        }
        #expect(writes == 0)
        #expect(try Data(contentsOf: f.ledgerURL) == original)
        #expect(try String(contentsOf: source, encoding: .utf8) == "Synthetic project bytes")
    }

    @MainActor @Test func oversizedDestinationAndChangedReplacementFailClosed() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), destination = f.root.appendingPathComponent("report.txt")
        try Data(repeating: 65, count: CampaignWorkspaceStore.maximumBytes + 1).write(to: destination)
        var writes = 0
        let lifecycle = CampaignReportExportLifecycle(chooseDestination: { destination }, write: { _, _, _ in writes += 1 })
        #expect(!f.session.saveReviewedReport(pending, lifecycle: lifecycle) { f.context })
        #expect(writes == 0)
        try Data("Before".utf8).write(to: destination)
        let racing = CampaignReportExportLifecycle(chooseDestination: { destination }, write: { data, url, expected in
            try Data("External replacement".utf8).write(to: url)
            try CampaignReportExportLifecycle.live.write(data, url, expected)
        })
        #expect(!f.session.saveReviewedReport(pending, lifecycle: racing) { f.context })
        #expect(try String(contentsOf: destination, encoding: .utf8) == "External replacement")
        #expect(f.session.reportPreview?.id == pending.id)
    }
}
