import Foundation
import Combine

/// Transient local preview state. Only an explicit import invokes a persistence
/// command; leaving the source view discards both pending and completed previews.
@MainActor
final class CampaignAgencyImportLifecycle: ObservableObject {
    @Published private(set) var preview: CampaignAgencyImport.Preview?
    @Published private(set) var previewDocumentID: UUID?
    @Published private(set) var problem: String?
    @Published private(set) var isReading = false

    private let read: @Sendable (URL) async throws -> CampaignAgencyImport.Preview
    private var readTask: Task<CampaignAgencyImport.Preview, Error>?
    private var requestToken: UUID?

    init(read: @escaping @Sendable (URL) async throws -> CampaignAgencyImport.Preview = {
        try CampaignAgencyImport.read($0)
    }) {
        self.read = read
    }

    deinit { readTask?.cancel() }

    /// The native picker stays in the view. Its nested event loop can dismiss the
    /// source view, so selection and reading share the same invalidation token.
    /// Returning the observation task lets tests await result handling exactly.
    @discardableResult
    func chooseSource(revising documentID: UUID?, select: () -> URL?) -> Task<Void, Never>? {
        cancel()
        let token = UUID()
        requestToken = token
        let url = select()
        guard requestToken == token else { return nil }
        guard let url else { requestToken = nil; return nil }

        isReading = true
        let read = self.read
        let task = Task.detached(priority: .userInitiated) { try await read(url) }
        readTask = task
        return Task { @MainActor [weak self] in
            let result = await task.result
            guard let self, self.requestToken == token else { return }
            self.readTask = nil
            self.requestToken = nil
            self.isReading = false
            switch result {
            case .success(let loaded):
                guard !task.isCancelled, !Task.isCancelled else { return }
                self.preview = loaded
                self.previewDocumentID = documentID
            case .failure(let error):
                if !(error is CancellationError) { self.problem = error.localizedDescription }
            }
        }
    }

    /// Cancel Reading, Cancel Import, tab changes, and panel dismissal all revoke
    /// the pending preview. A late reader cannot revive it or clear a newer one.
    func cancel() {
        requestToken = nil
        readTask?.cancel()
        readTask = nil
        isReading = false
        preview = nil
        previewDocumentID = nil
        problem = nil
    }

    /// A failed save keeps the exact preview and revision target available for an
    /// explicit retry. The session remains the only owner of canonical mutations.
    @discardableResult
    func importPreview(into session: CampaignWorkspaceSession) -> UUID? {
        guard let preview, requestToken == nil, !isReading,
              session.importAgencyText(preview, revisingDocumentID: previewDocumentID) else { return nil }
        let selectedID = previewDocumentID ?? session.ledger.draft.agency?.latestRevisions.last?.documentID
        cancel()
        return selectedID
    }
}
