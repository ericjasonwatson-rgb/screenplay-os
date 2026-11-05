import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign workspace commands")
struct CampaignWorkspaceSessionTests {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
    }

    @MainActor @Test func draftPersistsBeforePublishAndUndoDoesNotRemoveBaselines() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let screenplay = Screenplay(metadata: .init(title: "Campaign"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Campaign", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        session.updateDraft {
            $0.brief.brand = "Brand"; $0.brief.objective = "Launch"
            $0.deliverables = [.init(name: "Hero")]
        }
        let baseline = try #require(session.freeze(name: "Bid basis", document: document))
        #expect(session.record(baselineID: baseline, scope: .creative, approver: "Reviewer", evidence: "Email 1", document: document, amount: "", currency: ""))
        session.updateDraft { $0.brief.objective = "Revised" }
        session.undoDraft()
        #expect(session.ledger.draft.brief.objective == "Launch")
        #expect(session.ledger.baselines.count == 1)
        #expect(session.ledger.decisions.count == 1)
        let reopened = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        #expect(reopened.ledger == session.ledger)
        #expect(reopened.problem == nil)
    }

    @MainActor @Test func conflictingWriteDoesNotPublishOrDiscardPriorState() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let first = CampaignWorkspaceSession(projectID: id, root: root)
        let second = CampaignWorkspaceSession(projectID: id, root: root)
        first.updateDraft { $0.brief.brand = "First writer" }
        second.updateDraft { $0.brief.brand = "Second writer" }
        #expect(second.ledger.draft.brief.brand.isEmpty)
        #expect(second.problem != nil)
        #expect(!second.canUndoDraft)
        let reopened = CampaignWorkspaceSession(projectID: id, root: root)
        #expect(reopened.ledger.draft.brief.brand == "First writer")
    }

    @MainActor @Test func unsupportedCampaignIsReadOnlyAndNeverReset() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), bytes = Data("{broken".utf8)
        let url = try CampaignWorkspaceStore.url(projectID: id, root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        let session = CampaignWorkspaceSession(projectID: id, root: root)
        #expect(session.isReadOnly)
        #expect(!session.canImport)
        session.updateDraft { $0.brief.brand = "Replacement" }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(session.ledger.draft.brief.brand.isEmpty)
    }

    @MainActor @Test func normalizationOnlyDraftChangesAreNotDropped() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        session.updateDraft { $0.brief.brand = "Caf\u{00E9}" }
        session.updateDraft { $0.brief.brand = "Cafe\u{0301}" }
        #expect(Array(session.ledger.draft.brief.brand.utf8) == Array("Cafe\u{0301}".utf8))
    }
}
