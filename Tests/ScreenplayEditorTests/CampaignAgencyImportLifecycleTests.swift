import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign agency import lifecycle")
@MainActor
struct CampaignAgencyImportLifecycleTests {
    private func temporaryRoot() throws -> URL {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func preview(_ text: String = "Synthetic source", filename: String = "Agency.txt") -> CampaignAgencyImport.Preview {
        .init(filename: filename, bytes: Data(text.utf8), text: text)
    }

    @Test func cancelledPickerNeverReadsOrChangesSavedSources() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        #expect(session.importAgencyText(preview("Previously imported"), revisingDocumentID: nil))
        let before = session.ledger
        let url = try CampaignWorkspaceStore.url(projectID: before.projectID, root: root)
        let bytes = try Data(contentsOf: url)
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }

        #expect(lifecycle.chooseSource(revising: before.draft.agency?.latestRevisions.first?.documentID) { nil } == nil)
        #expect(await reader.requestCount == 0)
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == nil)
        #expect(lifecycle.importPreview(into: session) == nil)
        #expect(session.ledger == before)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func dismissalInsidePickerDiscardsReturnedSelection() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let observation = lifecycle.chooseSource(revising: UUID()) {
            // A modal picker runs a nested event loop. The source view can leave
            // before it returns even though the picker itself is synchronous.
            lifecycle.cancel()
            return URL(fileURLWithPath: "/synthetic/Agency.txt")
        }
        #expect(observation == nil)
        #expect(await reader.requestCount == 0)
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
    }

    @Test func newerSelectionInsidePickerWinsOverTheReturningOlderPicker() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let newerURL = URL(fileURLWithPath: "/synthetic/Newer.txt")
        let newerTarget = UUID()
        var newer: Task<Void, Never>?
        let old = lifecycle.chooseSource(revising: UUID()) {
            newer = lifecycle.chooseSource(revising: newerTarget) { newerURL }
            return URL(fileURLWithPath: "/synthetic/Older.txt")
        }
        #expect(old == nil)
        let observation = try #require(newer)
        #expect(await reader.waitForRequest(0) == newerURL)
        await reader.finish(0, with: .success(preview("Newer selection")))
        await observation.value
        #expect(await reader.requestCount == 1)
        #expect(lifecycle.preview?.text == "Newer selection")
        #expect(lifecycle.previewDocumentID == newerTarget)
        #expect(lifecycle.problem == nil)
    }

    @Test(arguments: [false, true])
    func cancelledReadIgnoresLateSuccessAndError(fails: Bool) async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let url = root.appendingPathComponent("Agency.txt")
        let observation = try #require(lifecycle.chooseSource(revising: UUID()) { url })
        #expect(await reader.waitForRequest(0) == url)
        #expect(lifecycle.isReading)
        #expect(lifecycle.importPreview(into: session) == nil)

        lifecycle.cancel()
        #expect(!lifecycle.isReading)
        await reader.finish(0, with: fails ? .failure(ControlledAgencyError.failed) : .success(preview()))
        await observation.value

        #expect(await reader.wasCancelled(0))
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == nil)
        #expect(lifecycle.importPreview(into: session) == nil)
        #expect(session.ledger.draft.agency == nil)
        #expect(!session.canUndoDraft)
        let storage = try CampaignWorkspaceStore.url(projectID: session.ledger.projectID, root: root)
        #expect(!FileManager.default.fileExists(atPath: storage.path))
    }

    @Test(arguments: [false, true], [false, true])
    func repeatedSelectionIgnoresOldResult(fails: Bool, oldFinishesFirst: Bool) async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let url = URL(fileURLWithPath: "/synthetic/Repeated.txt")
        let oldTarget = UUID(), newTarget = UUID()
        let old = try #require(lifecycle.chooseSource(revising: oldTarget) { url })
        _ = await reader.waitForRequest(0)
        let newer = try #require(lifecycle.chooseSource(revising: newTarget) { url })
        _ = await reader.waitForRequest(1)
        let oldResult: Result<CampaignAgencyImport.Preview, Error> = fails
            ? .failure(ControlledAgencyError.failed) : .success(preview("Old result"))

        if oldFinishesFirst {
            await reader.finish(0, with: oldResult)
            await old.value
            #expect(lifecycle.isReading)
            #expect(lifecycle.preview == nil)
            #expect(lifecycle.problem == nil)
        }
        await reader.finish(1, with: .success(preview("New result")))
        await newer.value
        if !oldFinishesFirst {
            await reader.finish(0, with: oldResult)
            await old.value
        }

        #expect(await reader.wasCancelled(0))
        #expect(!(await reader.wasCancelled(1)))
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview?.text == "New result")
        #expect(lifecycle.previewDocumentID == newTarget)
        #expect(lifecycle.problem == nil)
    }

    @Test func cancelledNewPickerAlsoInvalidatesTheOlderRead() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let old = try #require(lifecycle.chooseSource(revising: UUID()) {
            URL(fileURLWithPath: "/synthetic/Old.txt")
        })
        _ = await reader.waitForRequest(0)
        #expect(lifecycle.chooseSource(revising: nil) { nil } == nil)
        await reader.finish(0, with: .success(preview("Abandoned revision")))
        await old.value

        #expect(await reader.requestCount == 1)
        #expect(await reader.wasCancelled(0))
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == nil)
    }

    @Test func staleSuccessCannotReplaceANewerFailure() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let url = URL(fileURLWithPath: "/synthetic/Agency.txt")
        let old = try #require(lifecycle.chooseSource(revising: UUID()) { url })
        _ = await reader.waitForRequest(0)
        let newer = try #require(lifecycle.chooseSource(revising: nil) { url })
        _ = await reader.waitForRequest(1)
        await reader.finish(1, with: .failure(ControlledAgencyError.failed))
        await newer.value
        await reader.finish(0, with: .success(preview("Stale success")))
        await old.value
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == ControlledAgencyError.failed.localizedDescription)
    }

    @Test func failedReadCanRetryWithAnExplicitNewRevisionTarget() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let url = URL(fileURLWithPath: "/synthetic/Agency.txt")
        let oldTarget = UUID(), newTarget = UUID()
        let failed = try #require(lifecycle.chooseSource(revising: oldTarget) { url })
        _ = await reader.waitForRequest(0)
        await reader.finish(0, with: .failure(ControlledAgencyError.failed))
        await failed.value
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == ControlledAgencyError.failed.localizedDescription)

        let retry = try #require(lifecycle.chooseSource(revising: newTarget) { url })
        _ = await reader.waitForRequest(1)
        #expect(lifecycle.problem == nil)
        await reader.finish(1, with: .success(preview("Retried source")))
        await retry.value
        #expect(lifecycle.preview?.text == "Retried source")
        #expect(lifecycle.previewDocumentID == newTarget)
        #expect(lifecycle.problem == nil)
    }

    @Test func cooperativeReaderCancellationIsNotAnImportError() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let observation = try #require(lifecycle.chooseSource(revising: UUID()) {
            URL(fileURLWithPath: "/synthetic/Agency.txt")
        })
        _ = await reader.waitForRequest(0)
        await reader.finish(0, with: .failure(CancellationError()))
        await observation.value
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == nil)
    }

    @Test func cancelledReaderCannotPublishEvenIfItReturnsSuccess() async throws {
        let candidate = preview()
        let lifecycle = CampaignAgencyImportLifecycle { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return candidate
        }
        let observation = try #require(lifecycle.chooseSource(revising: UUID()) {
            URL(fileURLWithPath: "/synthetic/Agency.txt")
        })
        await observation.value
        #expect(!lifecycle.isReading)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.problem == nil)
    }

    @Test func onlyExplicitImportPersistsTheExactPreviewEvenIfSourceChanges() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Agency.txt")
        let original = Data("\u{FEFF}Cafe\u{0301}\r\nSynthetic source\n".utf8)
        try original.write(to: source)
        let projectID = UUID()
        let session = CampaignWorkspaceSession(projectID: projectID, root: root)
        let storage = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        let lifecycle = CampaignAgencyImportLifecycle()
        let observation = try #require(lifecycle.chooseSource(revising: nil) { source })
        await observation.value

        #expect(lifecycle.problem == nil)
        #expect(lifecycle.preview?.bytes == original)
        #expect(try Data(contentsOf: source) == original)
        #expect(session.ledger.draft.agency == nil)
        #expect(!session.canUndoDraft)
        #expect(!FileManager.default.fileExists(atPath: storage.path))
        let changedOnDisk = Data("Changed after preview".utf8)
        try changedOnDisk.write(to: source)

        let documentID = try #require(lifecycle.importPreview(into: session))
        #expect(session.ledger.draft.agency?.latestRevision(documentID: documentID)?.bytes == original)
        #expect(session.canUndoDraft)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.importPreview(into: session) == nil)
        #expect(session.ledger.draft.agency?.revisions.count == 1)
        #expect(try Data(contentsOf: source) == changedOnDisk)
        let reopened = CampaignWorkspaceSession(projectID: projectID, root: root)
        #expect(reopened.ledger == session.ledger)
        #expect(reopened.problem == nil)
        session.undoDraft()
        #expect(session.ledger.draft.agency == nil)
        #expect(try Data(contentsOf: source) == changedOnDisk)
    }

    @Test func cancellingLoadedRevisionKeepsSavedSourceAndReopenClean() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        #expect(session.importAgencyText(preview("Saved source"), revisingDocumentID: nil))
        let before = session.ledger
        let documentID = try #require(before.draft.agency?.latestRevisions.first?.documentID)
        let storage = try CampaignWorkspaceStore.url(projectID: before.projectID, root: root)
        let bytes = try Data(contentsOf: storage)
        let candidate = preview("Unimported revision")
        let lifecycle = CampaignAgencyImportLifecycle { _ in candidate }
        let observation = try #require(lifecycle.chooseSource(revising: documentID) {
            URL(fileURLWithPath: "/synthetic/Agency-v2.txt")
        })
        await observation.value
        #expect(lifecycle.previewDocumentID == documentID)
        lifecycle.cancel()

        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.importPreview(into: session) == nil)
        #expect(session.ledger == before)
        #expect(try Data(contentsOf: storage) == bytes)
        let reopened = CampaignWorkspaceSession(projectID: before.projectID, root: root)
        #expect(reopened.ledger == before)
        let newLifecycle = CampaignAgencyImportLifecycle()
        #expect(newLifecycle.preview == nil)
        #expect(newLifecycle.importPreview(into: reopened) == nil)
    }

    @Test func failedPersistenceKeepsPreviewAndTargetForExplicitRetryWithoutPartialMutation() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let writer = CampaignWorkspaceSession(projectID: projectID, root: root)
        #expect(writer.importAgencyText(preview("Saved source"), revisingDocumentID: nil))
        let documentID = try #require(writer.ledger.draft.agency?.latestRevisions.first?.documentID)
        let stale = CampaignWorkspaceSession(projectID: projectID, root: root)
        let before = stale.ledger
        writer.updateDraft { $0.brief.brand = "Newer saved work" }
        let storage = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        let savedBytes = try Data(contentsOf: storage)
        let candidate = preview("Explicit revised source")
        let lifecycle = CampaignAgencyImportLifecycle { _ in candidate }
        let observation = try #require(lifecycle.chooseSource(revising: documentID) {
            URL(fileURLWithPath: "/synthetic/Agency-v2.txt")
        })
        await observation.value

        for _ in 0..<2 {
            #expect(lifecycle.importPreview(into: stale) == nil)
            #expect(stale.ledger == before)
            #expect(stale.problem != nil)
            #expect(!stale.canUndoDraft)
            #expect(lifecycle.preview?.bytes == candidate.bytes)
            #expect(lifecycle.previewDocumentID == documentID)
            #expect(try Data(contentsOf: storage) == savedBytes)
        }
        let reopened = CampaignWorkspaceSession(projectID: projectID, root: root)
        #expect(reopened.ledger == writer.ledger)
        #expect(lifecycle.importPreview(into: reopened) == documentID)
        #expect(reopened.ledger.draft.brief.brand == "Newer saved work")
        #expect(reopened.ledger.draft.agency?.revisions.count == 2)
        #expect(reopened.ledger.draft.agency?.latestRevision(documentID: documentID)?.bytes == candidate.bytes)
        #expect(lifecycle.preview == nil)
        #expect(lifecycle.previewDocumentID == nil)
        #expect(lifecycle.importPreview(into: reopened) == nil)
        #expect(CampaignWorkspaceSession(projectID: projectID, root: root).ledger == reopened.ledger)
    }

    @Test func invalidPreviewCannotPartiallyPersistThroughConfirmation() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let session = CampaignWorkspaceSession(projectID: UUID(), root: root)
        let candidate = CampaignAgencyImport.Preview(filename: "Agency.txt", bytes: Data("Unseen".utf8), text: "Previewed")
        let lifecycle = CampaignAgencyImportLifecycle { _ in candidate }
        let observation = try #require(lifecycle.chooseSource(revising: nil) {
            URL(fileURLWithPath: "/synthetic/Agency.txt")
        })
        await observation.value
        #expect(lifecycle.importPreview(into: session) == nil)
        #expect(session.ledger.draft.agency == nil)
        #expect(!session.canUndoDraft)
        #expect(session.problem != nil)
        #expect(lifecycle.preview?.text == "Previewed")
        let storage = try CampaignWorkspaceStore.url(projectID: session.ledger.projectID, root: root)
        #expect(!FileManager.default.fileExists(atPath: storage.path))
    }
}

private enum ControlledAgencyError: LocalizedError {
    case failed
    var errorDescription: String? { "Synthetic reader failure" }
}

/// Intentionally ignores cancellation until explicitly resumed, reproducing an
/// uncooperative parser without sleeps, network, or private fixture data.
actor ControlledAgencyReader {
    private var urls: [URL] = []
    private var pending: [Int: CheckedContinuation<CampaignAgencyImport.Preview, Error>] = [:]
    private var waiting: [Int: CheckedContinuation<URL, Never>] = [:]
    private var cancelled: [Int: Bool] = [:]
    var requestCount: Int { urls.count }

    func read(_ url: URL) async throws -> CampaignAgencyImport.Preview {
        let index = urls.count
        urls.append(url)
        defer { cancelled[index] = Task.isCancelled }
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            waiting.removeValue(forKey: index)?.resume(returning: url)
        }
    }

    func waitForRequest(_ index: Int) async -> URL {
        if urls.indices.contains(index) { return urls[index] }
        return await withCheckedContinuation { waiting[index] = $0 }
    }

    func finish(_ index: Int, with result: Result<CampaignAgencyImport.Preview, Error>) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("Synthetic read must start before finishing")
        }
        continuation.resume(with: result)
    }

    func wasCancelled(_ index: Int) -> Bool { cancelled[index] == true }
}
