import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

/// Synthetic file-to-file recovery through the production writer and restore
/// commands. This is not file-picker, Office rendering or interactive acceptance.
@Suite("Campaign full-ledger backup roundtrip", .serialized)
struct CampaignBackupRoundTripTests {
    private struct Corpus: Decodable {
        let synthetic: Bool
        let fixtures: [AgencyFixture]
    }

    private struct AgencyFixture: Decodable {
        let name: String
        let filename: String
        let originalBase64: String
        let originalSHA256: String
        let expectedText: String?
        let extractedSHA256: String?
    }

    private struct Fixture {
        let session: CampaignWorkspaceSession
        let document: ScreenplayOSDocument
        let root: URL
        let ledgerURL: URL
        let screenplayURL: URL
        let sourceFiles: [URL: Data]
        let firstBaseline: CampaignBaseline
        let latestBaseline: CampaignBaseline
        let beforeWorkingEdit: CampaignLedger
        let context: CampaignRecoveryContext
    }

    private func temporaryRoot() throws -> URL {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CampaignAgency/corpus.json")
        let result = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        try #require(result.synthetic)
        return result
    }

    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor private func importSource(_ url: URL, into session: CampaignWorkspaceSession,
                                         revising documentID: UUID? = nil) throws -> CampaignAgencyRevision {
        let preview = try CampaignAgencyImport.read(url)
        try #require(session.importAgencyText(preview, revisingDocumentID: documentID))
        return try #require(session.ledger.draft.agency?.revisions.last)
    }

    @MainActor private func review(_ revision: CampaignAgencyRevision, in session: CampaignWorkspaceSession) throws {
        try #require(session.reviewAgencyRevision(revision.id, reviewer: "Synthetic Producer",
            note: "Compared \(revision.filename) and its exact extraction; no approval or spending is implied."))
    }

    @MainActor private func cite(_ revision: CampaignAgencyRevision, lines: ClosedRange<Int>,
                                kind: CampaignAgencyTargetKind, targetID: UUID,
                                in session: CampaignWorkspaceSession) throws {
        try #require(session.citeAgencyRevision(revision.id,
            firstLine: lines.lowerBound, lastLine: lines.upperBound, targetKind: kind, targetID: targetID,
            note: "Human-selected source range is the synthetic bid basis; no automatic scope adoption."))
    }

    @MainActor private func fixture(root: URL) throws -> Fixture {
        let action = ScreenplayElement(type: .action, text: "Cafe\u{0301}: a carton stands beside morning coffee. 👩🏽‍🎨")
        let screenplay = Screenplay(metadata: .init(title: "Synthetic Oat & Ember recovery"), elements: [action])
        let shot = Shot(label: "Hero packshot", sourceRefs: [.init(screenplayElementID: action.id)])
        let board = BoardFrame(shotID: shot.id, sceneSpineID: "", frameNumber: 1, label: "Carton and coffee")
        let document = ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic campaign recovery", author: "Test Author"),
            screenplayID: screenplay.id), screenplay: screenplay, shots: [shot], boardFrames: [board])
        let screenplayURL = root.appendingPathComponent("Synthetic.screenplayos.json")
        let screenplayBytes = try JSONEncoder().encode(document)
        try screenplayBytes.write(to: screenplayURL)
        var sourceFiles = [screenplayURL: screenplayBytes]
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let corpus = try corpus()
        var docxURLs: [String: URL] = [:]
        for name in ["deliverables-v1", "deliverables-v2"] {
            let fixture = try #require(corpus.fixtures.first { $0.name == name })
            let bytes = try #require(Data(base64Encoded: fixture.originalBase64))
            #expect(digest(bytes) == fixture.originalSHA256)
            let url = sourceRoot.appendingPathComponent(fixture.filename)
            try bytes.write(to: url)
            sourceFiles[url] = bytes; docxURLs[name] = url
            let preview = try CampaignAgencyImport.read(url)
            let expectedText = try #require(fixture.expectedText)
            #expect(preview.origin?.originalBytes == bytes)
            #expect(preview.bytes == Data(expectedText.utf8))
            #expect(digest(preview.bytes) == fixture.extractedSHA256)
        }
        let textSources = [
            "Synthetic-bid-v1.txt": Data("\u{FEFF}SYNTHETIC BID BASIS\r\nCaf\u{00E9}: one studio day, one location, no travel.\r\n".utf8),
            "Synthetic-bid-v2.txt": Data("\u{FEFF}SYNTHETIC BID BASIS\r\nCafe\u{0301}: one studio day, one location, no travel. 👩🏽‍🎨\r\n".utf8)
        ]
        for (name, bytes) in textSources {
            let url = sourceRoot.appendingPathComponent(name)
            try bytes.write(to: url); sourceFiles[url] = bytes
        }
        let storeRoot = root.appendingPathComponent("original-store", isDirectory: true)
        let session = CampaignWorkspaceSession(projectID: document.project.id, root: storeRoot)
        let hero = CampaignDeliverable(name: "Hero film", durationSeconds: 30, aspectRatio: "16:9",
            market: "US + UK", language: "en-US", linkedShotIDs: [shot.id])
        let social = CampaignDeliverable(name: "Social cutdown", durationSeconds: 15, aspectRatio: "9:16",
            market: "US + UK", language: "en-US", linkedShotIDs: [shot.id])
        let assumption = CampaignAssumption(text: "One studio day, one location, no travel.",
            sourceLabel: "Synthetic bid basis", sourceReference: "Line 2")
        session.updateDraft {
            $0.brief = .init(brand: "Oat & Ember", objective: "Introduce an oat drink for everyday coffee rituals",
                audience: "Adult home-coffee drinkers", keyMessage: "Small rituals, brighter mornings.",
                mandatoryRequirements: "Show carton label; no nutrition or environmental claims.")
            $0.deliverables = [hero, social]; $0.assumptions = [assumption]
        }
        let matrixV1 = try importSource(try #require(docxURLs["deliverables-v1"]), into: session)
        let bidV1 = try importSource(sourceRoot.appendingPathComponent("Synthetic-bid-v1.txt"), into: session)
        for revision in [matrixV1, bidV1] { try review(revision, in: session) }
        try cite(matrixV1, lines: 19...29, kind: .deliverable, targetID: hero.id, in: session)
        try cite(matrixV1, lines: 31...41, kind: .deliverable, targetID: social.id, in: session)
        try cite(bidV1, lines: 2...2, kind: .assumption, targetID: assumption.id, in: session)
        let firstID = try #require(session.freeze(name: "Reviewed V1 bid basis", document: document))
        let firstBaseline = try #require(session.ledger.baselines.first { $0.id == firstID })
        try #require(session.record(baselineID: firstID, scope: .creative, approver: "Synthetic Client",
            evidence: "Fictional creative-only decision for the 30-second V1. No spend approval.",
            document: document, amount: "", currency: ""))

        let matrixV2 = try importSource(try #require(docxURLs["deliverables-v2"]), into: session, revising: matrixV1.documentID)
        let bidV2 = try importSource(sourceRoot.appendingPathComponent("Synthetic-bid-v2.txt"), into: session, revising: bidV1.documentID)
        #expect(matrixV2.priorRevisionID == matrixV1.id)
        #expect(bidV2.priorRevisionID == bidV1.id)
        for revision in [matrixV2, bidV2] { try review(revision, in: session) }
        let bumper = CampaignDeliverable(name: "Bumper", durationSeconds: 6, aspectRatio: "1:1",
            market: "US + UK", language: "en-US", linkedShotIDs: [shot.id])
        session.updateDraft {
            $0.deliverables[0].durationSeconds = 45
            $0.deliverables.append(bumper)
        }
        // Use the real explicit replacement command, preserving V1 citations in
        // their immutable baseline instead of pretending review migrates them.
        let priorCitations = try #require(session.ledger.draft.agency).citations
        for citation in priorCitations {
            let revision = citation.documentID == matrixV1.documentID ? matrixV2 : bidV2
            let preview = try session.ledger.draft.previewAgencyCitationReplacement(citationID: citation.id,
                revisionID: revision.id, firstLine: citation.firstLine, lastLine: citation.lastLine,
                targetKind: citation.targetKind, targetID: citation.targetID,
                note: "Producer explicitly reconciled V2 source and target; historical V1 stays unchanged.")
            try #require(session.replaceAgencyCitation(preview))
        }
        try cite(matrixV2, lines: 43...53, kind: .deliverable, targetID: bumper.id, in: session)
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).isEmpty == true)
        let latestID = try #require(session.freeze(name: "Reconciled V2 bid basis", document: document))
        let latestBaseline = try #require(session.ledger.baselines.first { $0.id == latestID })
        try #require(session.record(baselineID: latestID, scope: .spend, approver: "Synthetic Budget Owner",
            evidence: "Fictional V2 ceiling evidence, separately recorded; not a payment or authenticated identity.",
            document: document, amount: "1250000", currency: "USD"))
        let beforeWorkingEdit = session.ledger
        // An unapproved working edit and a nonempty local Undo stack accompany
        // frozen history. Export must include the draft but must not edit history.
        session.updateDraft { $0.brief.audience += "; draft audience wording still under review" }
        try #require(session.problem == nil)
        try #require(session.canUndoDraft)
        return .init(session: session, document: document, root: root,
            ledgerURL: try CampaignWorkspaceStore.url(projectID: document.project.id, root: storeRoot),
            screenplayURL: screenplayURL, sourceFiles: sourceFiles, firstBaseline: firstBaseline,
            latestBaseline: latestBaseline, beforeWorkingEdit: beforeWorkingEdit,
            context: .init(projectID: document.project.id, presentationID: UUID(), sourceURL: screenplayURL))
    }

    @MainActor private func export(_ f: Fixture) throws -> URL {
        let url = f.root.appendingPathComponent("Synthetic-private-backup.json")
        let lifecycle = CampaignPrivateExportLifecycle(chooseDestination: { url },
            write: CampaignReportExportLifecycle.live.write)
        try #require(f.session.exportBackup(lifecycle: lifecycle) { f.context })
        return url
    }

    @MainActor private func restoreLifecycle(_ url: URL) -> CampaignBackupRestoreLifecycle {
        .init(chooseSource: { url }, read: CampaignBackupRestoreLifecycle.live.read,
            restore: CampaignBackupRestoreLifecycle.live.restore)
    }

    private func expectUnchangedSources(_ f: Fixture) throws {
        for (url, bytes) in f.sourceFiles { #expect(try Data(contentsOf: url) == bytes) }
        #expect(try JSONDecoder().decode(ScreenplayOSDocument.self,
            from: Data(contentsOf: f.screenplayURL)) == f.document)
    }

    @MainActor @Test func fullLedgerExportsRestoresAndReopensWithExactEvidenceAndSafeFirstUndo() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root: root), exportedLedger = f.session.ledger
        let canonicalBytes = try CampaignWorkspaceStore.encoded(exportedLedger)
        let originalBytes = try Data(contentsOf: f.ledgerURL)
        #expect(originalBytes == canonicalBytes)
        let backupURL = try export(f)
        #expect(try Data(contentsOf: backupURL) == canonicalBytes)
        #expect(f.session.ledger == exportedLedger)
        #expect(try Data(contentsOf: f.ledgerURL) == originalBytes)
        #expect(f.session.canUndoDraft)

        let restoreRoot = root.appendingPathComponent("fresh-restore-store", isDirectory: true)
        let restoredURL = try CampaignWorkspaceStore.url(projectID: f.document.project.id, root: restoreRoot)
        let restored = CampaignWorkspaceSession(projectID: f.document.project.id, root: restoreRoot)
        let emptyLedger = restored.ledger
        let context = CampaignRecoveryContext(projectID: f.document.project.id, presentationID: UUID(), sourceURL: f.screenplayURL)
        let lifecycle = restoreLifecycle(backupURL)
        let pending = try #require(restored.previewBackupRestore(lifecycle: lifecycle) { context })
        #expect(pending.projectID == f.document.project.id)
        #expect(pending.filename == backupURL.lastPathComponent)
        #expect(pending.byteCount == canonicalBytes.count)
        #expect(pending.baselineCount == exportedLedger.baselines.count)
        #expect(pending.decisionCount == exportedLedger.decisions.count)
        #expect(pending.agencyRevisionCount == exportedLedger.draft.agency?.revisions.count)
        #expect(pending.retainedOriginalCount == exportedLedger.draft.agency?.revisions.filter { $0.origin != nil }.count)
        #expect(restored.ledger == emptyLedger)
        #expect(!restored.canUndoDraft)
        #expect(!FileManager.default.fileExists(atPath: restoredURL.path))
        try #require(restored.confirmBackupRestore(pending, lifecycle: lifecycle) { context })
        #expect(restored.restorePreview == nil)
        #expect(!restored.canImport)
        #expect(!restored.canUndoDraft)
        #expect(restored.ledger == exportedLedger)
        #expect(try Data(contentsOf: restoredURL) == canonicalBytes)
        #expect(!restored.confirmBackupRestore(pending, lifecycle: lifecycle) { context })
        #expect(restored.previewBackupRestore(lifecycle: lifecycle) { context } == nil)
        #expect(try Data(contentsOf: restoredURL) == canonicalBytes)

        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: restoreRoot)
        try #require(reopened.problem == nil)
        #expect(reopened.ledger == exportedLedger)
        #expect(try CampaignWorkspaceStore.encoded(reopened.ledger) == canonicalBytes)
        #expect(reopened.ledger.baselines == [f.firstBaseline, f.latestBaseline])
        #expect(reopened.ledger.baselines.flatMap(\.sources) == exportedLedger.baselines.flatMap(\.sources))
        #expect(reopened.ledger.decisions == exportedLedger.decisions)
        #expect(reopened.ledger.decisions.map(\.scope) == [.creative, .spend])
        #expect(reopened.ledger.decisions.first?.baselineID == f.firstBaseline.id)
        #expect(reopened.ledger.decisions.first?.spendCeilingMinorUnits == nil)
        #expect(reopened.ledger.decisions.last?.baselineID == f.latestBaseline.id)
        #expect(reopened.ledger.decisions.last?.spendCeilingMinorUnits == 1_250_000)
        #expect(reopened.ledger.decisions.last?.currencyCode == "USD")
        let agency = try #require(reopened.ledger.draft.agency)
        let originalAgency = try #require(exportedLedger.draft.agency)
        #expect(agency.reviews == originalAgency.reviews)
        #expect(agency.citations == originalAgency.citations)
        #expect(agency.revisions.map(\.id) == originalAgency.revisions.map(\.id))
        for revision in agency.revisions {
            let original = try #require(originalAgency.revisions.first { $0.id == revision.id })
            #expect(revision.documentID == original.documentID)
            #expect(revision.priorRevisionID == original.priorRevisionID)
            #expect(revision.bytes == original.bytes)
            #expect(Data(revision.text.utf8) == original.bytes)
            #expect(revision.sha256 == digest(original.bytes))
            #expect(revision.origin == original.origin)
            let sourceURL = root.appendingPathComponent("sources").appendingPathComponent(revision.filename)
            let sourceBytes = try #require(f.sourceFiles[sourceURL])
            if let origin = revision.origin {
                #expect(origin.originalBytes == sourceBytes)
                #expect(origin.originalSHA256 == digest(sourceBytes))
            } else {
                #expect(revision.bytes == sourceBytes)
            }
        }

        // Undo history is intentionally session-local. Recovery itself cannot
        // be undone into an empty ledger or erase restored baselines/decisions.
        #expect(!reopened.canUndoDraft)
        reopened.updateDraft { $0.deliverables.removeLast() }
        try #require(reopened.canUndoDraft)
        #expect(reopened.ledger.baselines == exportedLedger.baselines)
        #expect(reopened.ledger.decisions == exportedLedger.decisions)
        reopened.undoDraft()
        #expect(!reopened.canUndoDraft)
        #expect(reopened.ledger == exportedLedger)
        #expect(try Data(contentsOf: restoredURL) == canonicalBytes)
        reopened.undoDraft()
        #expect(try Data(contentsOf: restoredURL) == canonicalBytes)
        let afterUndoReopen = CampaignWorkspaceSession(projectID: f.document.project.id, root: restoreRoot)
        #expect(afterUndoReopen.problem == nil)
        #expect(afterUndoReopen.ledger == exportedLedger)
        // The export did not add an Undo entry or consume the existing draft edit.
        f.session.undoDraft()
        #expect(f.session.ledger == f.beforeWorkingEdit)
        #expect(try Data(contentsOf: f.ledgerURL) == CampaignWorkspaceStore.encoded(f.beforeWorkingEdit))
        #expect(try Data(contentsOf: backupURL) == canonicalBytes)
        try expectUnchangedSources(f)
    }

    @MainActor @Test func preparedBackupNeverReplacesExistingOrNewlyCreatedCampaignHistory() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root: root), original = f.session.ledger
        let originalBytes = try Data(contentsOf: f.ledgerURL), backupURL = try export(f)
        let lifecycle = restoreLifecycle(backupURL)
        #expect(f.session.previewBackupRestore(lifecycle: lifecycle) { f.context } == nil)
        #expect(f.session.ledger == original)
        #expect(try Data(contentsOf: f.ledgerURL) == originalBytes)

        let targetRoot = root.appendingPathComponent("concurrent-store", isDirectory: true)
        let target = CampaignWorkspaceSession(projectID: f.document.project.id, root: targetRoot)
        let context = CampaignRecoveryContext(projectID: f.document.project.id, presentationID: UUID(), sourceURL: f.screenplayURL)
        let pending = try #require(target.previewBackupRestore(lifecycle: lifecycle) { context })
        let emptyLedger = target.ledger
        let newer = CampaignWorkspaceSession(projectID: f.document.project.id, root: targetRoot)
        newer.updateDraft {
            $0.brief = .init(brand: "Synthetic independent local work", objective: "Keep this history")
            $0.deliverables = [.init(name: "Locally reviewed hero")]
        }
        let newBaseline = try #require(newer.freeze(name: "Local work created during restore review", document: f.document))
        try #require(newer.record(baselineID: newBaseline, scope: .creative, approver: "Synthetic Local Reviewer",
            evidence: "Local evidence must not be replaced by the older backup.", document: f.document, amount: "", currency: ""))
        let targetURL = try CampaignWorkspaceStore.url(projectID: f.document.project.id, root: targetRoot)
        let newerBytes = try Data(contentsOf: targetURL)
        #expect(!target.confirmBackupRestore(pending, lifecycle: lifecycle) { context })
        #expect(target.problem != nil)
        #expect(target.ledger == emptyLedger)
        #expect(!target.canUndoDraft)
        #expect(try Data(contentsOf: targetURL) == newerBytes)
        let reopened = CampaignWorkspaceSession(projectID: f.document.project.id, root: targetRoot)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger == newer.ledger)
        #expect(reopened.ledger.baselines.map(\.id) == [newBaseline])
        #expect(reopened.ledger.decisions == newer.ledger.decisions)
        #expect(try Data(contentsOf: f.ledgerURL) == originalBytes)
        #expect(try Data(contentsOf: backupURL) == originalBytes)
        f.session.undoDraft()
        #expect(f.session.ledger == f.beforeWorkingEdit)
        try expectUnchangedSources(f)
    }
}
