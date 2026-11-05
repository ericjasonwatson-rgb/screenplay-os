import Foundation
import Darwin
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign agency local import")
struct CampaignAgencyImportTests {
    private func temporaryRoot() throws -> URL {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func previewPreservesExactBOMUnicodeAndNewlinesWithoutWriting() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Agency script.txt")
        let bytes = Data("\u{FEFF}Cafe\u{0301}\r\nSecond line\n".utf8)
        try bytes.write(to: url)
        let preview = try CampaignAgencyImport.read(url)
        #expect(preview.filename == "Agency script.txt")
        #expect(preview.bytes == bytes)
        #expect(Data(preview.text.utf8) == bytes)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Agency script.txt"])
    }

    @Test func previewAcceptsExactMaximumSize() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Maximum.fountain")
        let bytes = Data(repeating: 65, count: CampaignAgencyWorkspace.maximumSourceBytes)
        try bytes.write(to: url)
        #expect(try CampaignAgencyImport.read(url).bytes == bytes)
    }

    @Test func previewRejectsUnsupportedBinaryEmptyAndOversizedFiles() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(String, Data)] = [
            ("Source.pdf", Data("%PDF-1.7".utf8)), ("Source.docx", Data("PK".utf8)),
            ("Empty.txt", Data()), ("Invalid.txt", Data([0xff, 0xfe, 0x00, 0x00])),
            ("Nul.md", Data([65, 0, 66])),
            ("Oversized.txt", Data(repeating: 65, count: CampaignAgencyWorkspace.maximumSourceBytes + 1))
        ]
        for (name, bytes) in cases {
            let url = root.appendingPathComponent(name); try bytes.write(to: url)
            #expect(throws: (any Error).self) { try CampaignAgencyImport.read(url) }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func previewRejectsSymlinkDirectoryAndFIFOWithoutBlocking() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.txt"); try Data("Text".utf8).write(to: real)
        let link = root.appendingPathComponent("Link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let directory = root.appendingPathComponent("Directory.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let pipe = root.appendingPathComponent("Pipe.txt")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        for url in [link, directory, pipe] {
            #expect(throws: (any Error).self) { try CampaignAgencyImport.read(url) }
        }
    }

    @MainActor @Test func importReviewCitationRoundtripAndUndoPreserveFrozenHistory() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let screenplay = Screenplay(metadata: .init(title: "Agency"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Agency", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        let target = CampaignDeliverable(name: "Hero")
        session.updateDraft { $0.brief.brand = "Brand"; $0.brief.objective = "Launch"; $0.deliverables = [target] }
        let preview = CampaignAgencyImport.Preview(filename: "Agency.txt", bytes: Data("Hero film\n30 seconds".utf8), text: "Hero film\n30 seconds")
        #expect(session.importAgencyText(preview, revisingDocumentID: nil))
        let revision = try #require(session.ledger.draft.agency?.latestRevisions.first)
        #expect(!session.citeAgencyRevision(revision.id, firstLine: 1, lastLine: 2, targetKind: .deliverable, targetID: target.id, note: "Matches hero"))
        #expect(session.reviewAgencyRevision(revision.id, reviewer: "Producer", note: "Verified against agency email"))
        #expect(session.citeAgencyRevision(revision.id, firstLine: 1, lastLine: 2, targetKind: .deliverable, targetID: target.id, note: "Matches hero"))
        let baselineID = try #require(session.freeze(name: "Reviewed source", document: document))
        #expect(session.record(baselineID: baselineID, scope: .creative, approver: "Client", evidence: "Approval email", document: document, amount: "", currency: ""))
        let revised = CampaignAgencyImport.Preview(filename: "Agency-v2.txt", bytes: Data("Hero film\n45 seconds".utf8), text: "Hero film\n45 seconds")
        #expect(session.importAgencyText(revised, revisingDocumentID: revision.documentID))
        #expect(session.ledger.draft.agency?.revisions.count == 2)
        #expect(!session.record(baselineID: baselineID, scope: .production, approver: "Producer", evidence: "Unreviewed revision", document: document, amount: "", currency: ""))
        let reopened = CampaignWorkspaceSession(projectID: document.project.id, root: root)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger == session.ledger)
        session.undoDraft()
        #expect(session.ledger.draft.agency?.revisions.count == 1)
        #expect(session.ledger.baselines.first?.draft.agency?.revisions.first?.bytes == preview.bytes)
        #expect(session.ledger.decisions.count == 1)
        #expect(try session.ledger.compare(baselineID: baselineID, document: document).isEmpty)
    }

    @MainActor @Test func conflictingImportDoesNotPublishSourceOrUndoHistory() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let first = CampaignWorkspaceSession(projectID: projectID, root: root)
        let second = CampaignWorkspaceSession(projectID: projectID, root: root)
        first.updateDraft { $0.brief.brand = "Saved writer" }
        let preview = CampaignAgencyImport.Preview(filename: "Source.txt", bytes: Data("Private text".utf8), text: "Private text")
        #expect(!second.importAgencyText(preview, revisingDocumentID: nil))
        #expect(second.ledger.draft.agency == nil)
        #expect(!second.canUndoDraft)
        #expect(second.problem != nil)
    }

    @MainActor @Test func mismatchedPreviewCannotImportUnseenBytes() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        let preview = CampaignAgencyImport.Preview(filename: "Source.txt", bytes: Data("Unseen".utf8), text: "Previewed")
        #expect(!session.importAgencyText(preview, revisingDocumentID: nil))
        #expect(session.ledger.draft.agency == nil)
        #expect(!session.canUndoDraft)
    }

    @Test func unknownAgencyFieldsRemainProtected() throws {
        let id = UUID()
        var ledger = CampaignLedger(projectID: id)
        try ledger.draft.importAgencyText(data: Data("Source".utf8), filename: "Agency.txt")
        var object = try #require(JSONSerialization.jsonObject(with: CampaignWorkspaceStore.encoded(ledger)) as? [String: Any])
        var draft = try #require(object["draft"] as? [String: Any])
        var agency = try #require(draft["agency"] as? [String: Any])
        agency["futurePrivateEvidence"] = "Preserve me"; draft["agency"] = agency; object["draft"] = draft
        let altered = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.decode(altered, projectID: id) }
    }

    @Test func oldLedgerWithBaselineAndApprovalStillDecodesWithoutAgencyFields() throws {
        let screenplay = Screenplay(metadata: .init(title: "Legacy"))
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Legacy", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        var ledger = CampaignLedger(projectID: document.project.id,
            draft: .init(brief: .init(brand: "Brand", objective: "Launch"), deliverables: [.init(name: "Hero")]))
        let baseline = try ledger.freeze(name: "Old v1", document: document)
        try ledger.recordDecision(baselineID: baseline.id, scope: .creative, approver: "Client", evidence: "Email", document: document)
        let encoded = try CampaignWorkspaceStore.encoded(ledger)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("\"agency\""))
        #expect(try CampaignWorkspaceStore.decode(encoded, projectID: document.project.id) == ledger)
    }
}
