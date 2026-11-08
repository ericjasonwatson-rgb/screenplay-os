import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign persisted citation replacement")
struct CampaignAgencyReconciliationSessionTests {
    private struct Fixture {
        let session: CampaignWorkspaceSession
        let document: ScreenplayOSDocument
        let citation: CampaignAgencyCitation
        let current: CampaignAgencyRevision
        let root: URL
        let url: URL
    }

    @MainActor private func fixture() throws -> Fixture {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        let screenplay = Screenplay(metadata: .init(title: "Synthetic atomic save"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic atomic save", author: ""),
            screenplayID: screenplay.id), screenplay: screenplay)
        var ledger = CampaignLedger(projectID: document.project.id, draft: .init(
            brief: .init(brand: "Synthetic brand", objective: "Original objective"),
            deliverables: [.init(name: "Café hero")], assumptions: [.init(text: "One synthetic location")]))
        let original = try ledger.draft.importAgencyText(data: Data("Café\r\n30 seconds".utf8), filename: "Synthetic-v1.txt")
        _ = try ledger.draft.reviewAgencyRevision(revisionID: original.id, reviewer: "Synthetic Producer", note: "Original reviewed")
        let citation = try ledger.draft.citeAgencyRevision(revisionID: original.id, firstLine: 1, lastLine: 2,
            targetKind: .deliverable, targetID: ledger.draft.deliverables[0].id, note: "Original human citation")
        let baseline = try ledger.freeze(name: "Original baseline", document: document)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Synthetic Director",
            evidence: "Synthetic creative evidence only", document: document)
        _ = try ledger.recordDecision(baselineID: baseline.id, scope: .spend, approver: "Synthetic Client",
            evidence: "Separate synthetic ceiling", document: document, spendCeilingMinorUnits: 25000, currencyCode: "USD")
        let current = try ledger.draft.importAgencyText(data: Data("Cafe\u{0301}\r\n45 seconds 👩🏽‍🎨".utf8),
            filename: "Synthetic-v2.txt", revisingDocumentID: original.documentID)
        _ = try ledger.draft.reviewAgencyRevision(revisionID: current.id, reviewer: "Synthetic Producer", note: "Current reviewed")
        let url = try CampaignWorkspaceStore.url(projectID: document.project.id, root: root)
        try CampaignWorkspaceStore.save(ledger, to: url, expected: nil)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        try #require(session.problem == nil)
        return .init(session: session, document: document, citation: citation, current: current, root: root, url: url)
    }

    @MainActor private func preview(_ f: Fixture) throws -> CampaignAgencyCitationReplacementPreview {
        try f.session.ledger.draft.previewAgencyCitationReplacement(citationID: f.citation.id,
            revisionID: f.current.id, firstLine: 1, lastLine: 2, targetKind: .deliverable,
            targetID: f.citation.targetID, note: "Human explicitly chose current evidence without changing the target")
    }

    /// Deterministic precommit storage failure, without permissions or timing races.
    private func blockSaving(_ f: Fixture) throws -> URL {
        let lock = f.url.deletingLastPathComponent().appendingPathComponent(".campaign.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        return lock
    }

    @MainActor @Test func previewIsReadOnlyAndOneSuccessfulSaveHasOneUndoRestoringExactBytes() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = f.session.ledger, bytes = try Data(contentsOf: f.url)
        #expect(!f.session.canUndoDraft)
        let pending = try preview(f)
        #expect(try Data(contentsOf: f.url) == bytes)
        #expect(!f.session.canUndoDraft)
        #expect(f.session.replaceAgencyCitation(pending))
        let replacement = try #require(f.session.ledger.draft.agency?.citations.first)
        #expect(replacement.id != f.citation.id)
        #expect(replacement.revisionID == f.current.id)
        #expect(f.session.ledger.draft.agency?.citations.count == 1)
        #expect(f.session.canUndoDraft)
        #expect(f.session.ledger.baselines == original.baselines)
        #expect(f.session.ledger.decisions == original.decisions)
        #expect(f.session.ledger.decisions.map(\.scope) == [.creative, .spend])
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger == f.session.ledger)
        #expect(!reopened.canUndoDraft)
        f.session.undoDraft()
        #expect(!f.session.canUndoDraft)
        #expect(f.session.ledger == original)
        #expect(f.session.ledger.draft.agency?.citations == [f.citation])
        #expect(try Data(contentsOf: f.url) == bytes)
        let restored = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(restored.ledger == original)
        #expect(restored.problem == nil)
    }

    @MainActor @Test func failedSaveKeepsOldCitationDiskAndHistoryAndSamePreviewCanRetry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), original = f.session.ledger, bytes = try Data(contentsOf: f.url)
        let lock = try blockSaving(f)
        #expect(!f.session.replaceAgencyCitation(pending))
        #expect(f.session.problem != nil)
        #expect(f.session.ledger == original)
        #expect(f.session.ledger.draft.agency?.citations == [f.citation])
        #expect(!f.session.canUndoDraft)
        #expect(try Data(contentsOf: f.url) == bytes)
        try f.session.ledger.draft.validateAgencyCitationReplacement(pending)
        try FileManager.default.removeItem(at: lock)
        #expect(f.session.replaceAgencyCitation(pending))
        #expect(f.session.problem == nil)
        f.session.undoDraft()
        #expect(!f.session.canUndoDraft)
        #expect(try Data(contentsOf: f.url) == bytes)
    }

    @MainActor @Test func failedReplacementDoesNotInsertHistoryBeforeAnExistingUndo() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let initial = f.session.ledger, initialBytes = try Data(contentsOf: f.url)
        f.session.updateDraft { $0.brief.objective = "Explicit intermediate edit" }
        let pending = try preview(f), edited = f.session.ledger, editedBytes = try Data(contentsOf: f.url)
        let lock = try blockSaving(f)
        #expect(!f.session.replaceAgencyCitation(pending))
        #expect(f.session.canUndoDraft)
        #expect(f.session.ledger == edited)
        #expect(try Data(contentsOf: f.url) == editedBytes)
        try FileManager.default.removeItem(at: lock)
        f.session.undoDraft()
        #expect(f.session.ledger == initial)
        #expect(!f.session.canUndoDraft)
        #expect(try Data(contentsOf: f.url) == initialBytes)
    }

    @MainActor @Test func failedUndoRetainsReplacementAndRetryRestoresItsSinglePriorDraft() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let initialBytes = try Data(contentsOf: f.url)
        #expect(f.session.replaceAgencyCitation(try preview(f)))
        let saved = f.session.ledger, savedBytes = try Data(contentsOf: f.url)
        let lock = try blockSaving(f)
        f.session.undoDraft()
        #expect(f.session.problem != nil)
        #expect(f.session.canUndoDraft)
        #expect(f.session.ledger == saved)
        #expect(try Data(contentsOf: f.url) == savedBytes)
        try FileManager.default.removeItem(at: lock)
        f.session.undoDraft()
        #expect(!f.session.canUndoDraft)
        #expect(f.session.ledger.draft.agency?.citations == [f.citation])
        #expect(try Data(contentsOf: f.url) == initialBytes)
    }

    @MainActor @Test func conflictingWriterCannotPublishReplacementOrUndoEntry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), original = f.session.ledger
        let writer = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        writer.updateDraft { $0.brief.objective = "Other window's explicit edit" }
        let writerBytes = try Data(contentsOf: f.url)
        // The previewed endpoints still match. The store's byte lease must refuse.
        try f.session.ledger.draft.validateAgencyCitationReplacement(pending)
        #expect(!f.session.replaceAgencyCitation(pending))
        #expect(f.session.problem != nil)
        #expect(!f.session.canUndoDraft)
        #expect(f.session.ledger == original)
        #expect(try Data(contentsOf: f.url) == writerBytes)
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: f.root)
        #expect(reopened.ledger == writer.ledger)
        #expect(reopened.ledger.draft.agency?.citations == [f.citation])
    }

    @MainActor @Test func staleTargetPreviewCannotPersistOrConsumeTheTargetsUndoEntry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), initialBytes = try Data(contentsOf: f.url)
        f.session.updateDraft { $0.deliverables[0].name = "Cafe\u{0301} hero" }
        let editedBytes = try Data(contentsOf: f.url)
        #expect(editedBytes != initialBytes)
        #expect(!f.session.replaceAgencyCitation(pending))
        #expect(f.session.problem != nil)
        #expect(f.session.canUndoDraft)
        #expect(f.session.ledger.draft.agency?.citations == [f.citation])
        #expect(try Data(contentsOf: f.url) == editedBytes)
        f.session.undoDraft()
        #expect(!f.session.canUndoDraft)
        #expect(try Data(contentsOf: f.url) == initialBytes)
    }

    @MainActor @Test func repeatedConfirmationCannotSaveOrAddAnExtraUndoEntry() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let pending = try preview(f), initialBytes = try Data(contentsOf: f.url)
        #expect(f.session.replaceAgencyCitation(pending))
        let replaced = f.session.ledger, savedBytes = try Data(contentsOf: f.url)
        #expect(!f.session.replaceAgencyCitation(pending))
        #expect(f.session.ledger == replaced)
        #expect(try Data(contentsOf: f.url) == savedBytes)
        f.session.undoDraft()
        #expect(!f.session.canUndoDraft)
        #expect(try Data(contentsOf: f.url) == initialBytes)
    }
}
