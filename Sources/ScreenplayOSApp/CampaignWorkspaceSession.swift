import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain

@MainActor
final class CampaignWorkspaceSession: ObservableObject {
    @Published private(set) var ledger: CampaignLedger
    @Published private(set) var problem: String?
    @Published private(set) var reportPreview: CampaignChangeReportPreview?
    private var isSavingReport = false
    @Published private(set) var decisionPreview: CampaignDecisionPreview?
    @Published private(set) var status = "Changes save locally. Nothing is sent to anyone."
    @Published private(set) var isReadOnly = false
    @Published private(set) var canUndoDraft = false
    private var history: [CampaignDraft] = []
    private var bytes: Data?
    private var storageURL: URL?

    init(projectID: UUID, root: URL? = nil) {
        ledger = CampaignLedger(projectID: projectID)
        do {
            let url = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
            let loaded = try CampaignWorkspaceStore.load(projectID: projectID, from: url)
            storageURL = url; bytes = loaded.bytes; ledger = loaded.ledger
        } catch {
            isReadOnly = true
            problem = error.localizedDescription
        }
    }

    func updateDraft(_ edit: (inout CampaignDraft) -> Void) {
        _ = mutateDraft(edit)
    }

    @discardableResult
    private func mutateDraft(_ edit: (inout CampaignDraft) throws -> Void) -> Bool {
        do {
            var next = ledger
            try edit(&next.draft)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard try encoder.encode(next.draft) != encoder.encode(ledger.draft) else { return true }
            let previous = ledger.draft
            guard commit(next) else { return false }
            history.append(previous)
            if history.count > 50 { history.removeFirst() }
            canUndoDraft = true
            return true
        } catch { problem = error.localizedDescription; return false }
    }

    @discardableResult
    func importAgencyText(_ preview: CampaignAgencyImport.Preview, revisingDocumentID: UUID?) -> Bool {
        mutateDraft { draft in
            guard Data(preview.text.utf8) == preview.bytes else {
                throw CampaignError.invalid("Import preview no longer matches the selected bytes. Choose the source again.")
            }
            if let origin = preview.origin {
                guard Data(origin.text.utf8) == preview.bytes else {
                    throw CampaignError.invalid("Document extraction no longer matches its preview.")
                }
                _ = try draft.importAgencyDocument(origin: origin, filename: preview.filename,
                                                  revisingDocumentID: revisingDocumentID)
            } else {
                _ = try draft.importAgencyText(data: preview.bytes, filename: preview.filename,
                                              revisingDocumentID: revisingDocumentID)
            }
        }
    }

    @discardableResult
    func reviewAgencyRevision(_ id: UUID, reviewer: String, note: String) -> Bool {
        mutateDraft { draft in _ = try draft.reviewAgencyRevision(revisionID: id, reviewer: reviewer, note: note) }
    }

    @discardableResult
    func citeAgencyRevision(_ id: UUID, firstLine: Int, lastLine: Int,
                            targetKind: CampaignAgencyTargetKind, targetID: UUID, note: String) -> Bool {
        mutateDraft { draft in
            _ = try draft.citeAgencyRevision(revisionID: id, firstLine: firstLine, lastLine: lastLine,
                                            targetKind: targetKind, targetID: targetID, note: note)
        }
    }

    func removeAgencyCitation(_ id: UUID) {
        _ = mutateDraft { draft in try draft.removeAgencyCitation(id: id) }
    }

    @discardableResult
    func replaceAgencyCitation(_ preview: CampaignAgencyCitationReplacementPreview) -> Bool {
        mutateDraft { draft in _ = try draft.replaceAgencyCitation(preview) }
    }

    func undoDraft() {
        guard let prior = history.last else { return }
        var next = ledger; next.draft = prior
        if commit(next) { history.removeLast(); canUndoDraft = !history.isEmpty }
    }

    @discardableResult
    func freeze(name: String, document: ScreenplayOSDocument) -> UUID? {
        do {
            var next = ledger
            let baseline = try next.freeze(name: name, document: document)
            return commit(next) ? baseline.id : nil
        } catch { problem = error.localizedDescription; return nil }
    }

    func discardDecisionPreview() { decisionPreview = nil }

    @discardableResult
    func previewDecision(baselineID: UUID, scope: CampaignApprovalScope, approver: String, evidence: String,
                         document: ScreenplayOSDocument, amount: String, currency: String) -> CampaignDecisionPreview? {
        // An unsuccessful new preview must not leave an older proposal confirmable.
        decisionPreview = nil
        guard !isReadOnly else { return nil }
        do {
            let ceiling = try decisionCeiling(scope: scope, amount: amount)
            let preview = try ledger.previewDecision(baselineID: baselineID, scope: scope,
                approver: approver, evidence: evidence, document: document,
                spendCeilingMinorUnits: ceiling, currencyCode: scope == .spend ? currency.uppercased() : nil)
            decisionPreview = preview
            problem = nil
            return preview
        } catch { problem = error.localizedDescription; return nil }
    }

    @discardableResult
    func confirmDecision(_ preview: CampaignDecisionPreview, baselineID: UUID,
                         document: ScreenplayOSDocument) -> Bool {
        do {
            guard decisionPreview?.id == preview.id else {
                throw CampaignError.invalid("Preview the local approval record again before confirming it.")
            }
            var next = ledger
            try next.confirmDecision(preview, baselineID: baselineID, document: document)
            // Failed persistence preserves ledger, draft undo history and the
            // same proposal for an explicit retry. No automatic re-preview.
            guard commit(next) else { return false }
            decisionPreview = nil
            return true
        } catch { problem = error.localizedDescription; return false }
    }

    private func decisionCeiling(scope: CampaignApprovalScope, amount: String) throws -> Int64? {
        guard scope == .spend else { return nil }
        guard let parsed = Int64(amount), parsed >= 0 else {
            throw CampaignError.invalid("Enter the authorized ceiling as a nonnegative integer in minor currency units, for example 12500 for USD 125.00.")
        }
        return parsed
    }

    @discardableResult
    func record(baselineID: UUID, scope: CampaignApprovalScope, approver: String, evidence: String,
                document: ScreenplayOSDocument, amount: String, currency: String) -> Bool {
        do {
            var next = ledger
            let ceiling = try decisionCeiling(scope: scope, amount: amount)
            try next.recordDecision(baselineID: baselineID, scope: scope, approver: approver,
                                    evidence: evidence, document: document,
                                    spendCeilingMinorUnits: ceiling,
                                    currencyCode: scope == .spend ? currency.uppercased() : nil)
            return commit(next)
        } catch { problem = error.localizedDescription; return false }
    }

    private func commit(_ next: CampaignLedger) -> Bool {
        guard !isReadOnly, let storageURL else { return false }
        do {
            let saved = try CampaignWorkspaceStore.save(next, to: storageURL, expected: bytes)
            // A failed write never becomes the visible canonical campaign state.
            bytes = saved; ledger = next; problem = nil
            status = "Saved locally at \(Date().formatted(date: .omitted, time: .standard)). Nothing was sent."
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    func exportAgencyOriginal(_ revisionID: UUID) {
        guard let revision = ledger.draft.agency?.revisions.first(where: { $0.id == revisionID }),
              let origin = revision.origin else { return }
        do {
            try origin.validate()
            let type = UTType(filenameExtension: "docx") ?? .data
            try export(origin.originalBytes, name: revision.filename, type: type)
        } catch { problem = error.localizedDescription }
    }

    func exportBackup() {
        do { try export(try CampaignWorkspaceStore.encoded(ledger), name: "Campaign-private-backup.json", type: .json) }
        catch { problem = error.localizedDescription }
    }

    /// Backup restore is explicit and only allowed before a local campaign exists.
    /// Existing baselines/decisions are never replaced by an imported older copy.
    func importBackup() {
        guard bytes == nil, !isReadOnly else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Restore a campaign backup for this project. This does not restore screenplay text or media."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try CampaignWorkspaceStore.decode(CampaignWorkspaceStore.readBackup(url), projectID: ledger.projectID)
            _ = commit(imported)
        } catch { problem = error.localizedDescription }
    }

    var canImport: Bool { bytes == nil && !isReadOnly }

    func discardReportPreview() { reportPreview = nil }

    @discardableResult
    func previewReport(baselineID: UUID, document: ScreenplayOSDocument,
                       includeFullEvidence: Bool = false) -> CampaignChangeReportPreview? {
        reportPreview = nil
        do {
            try validateReportLease()
            let preview = try ledger.previewChangeReport(baselineID: baselineID, document: document,
                options: .init(includeFullEvidence: includeFullEvidence))
            reportPreview = preview
            problem = nil
            return preview
        } catch { problem = error.localizedDescription; return nil }
    }

    func reportPreviewIsCurrent(_ preview: CampaignChangeReportPreview, baselineID: UUID,
                                document: ScreenplayOSDocument) -> Bool {
        guard reportPreview?.id == preview.id else { return false }
        return (try? preview.validatedData(ledger: ledger, baselineID: baselineID, document: document)) != nil
    }

    private func validateReportLease() throws {
        guard !isReadOnly, let storageURL else {
            throw CampaignError.invalid("Reopen Campaign before previewing or saving a report.")
        }
        let current = try CampaignWorkspaceStore.load(projectID: ledger.projectID, from: storageURL)
        guard current.bytes == bytes else { throw CampaignWorkspaceStore.Failure.conflict }
    }

    /// The context callback reads live UI state, never the state captured before
    /// NSSavePanel's nested event loop. Cancellation and failure do not consume a
    /// still-valid preview. Only successful saving consumes it.
    @discardableResult
    func saveReviewedReport(_ preview: CampaignChangeReportPreview,
                            lifecycle: CampaignReportExportLifecycle? = nil,
                            currentContext: () -> (baselineID: UUID, document: ScreenplayOSDocument, sourceURL: URL?)?) -> Bool {
        guard !isSavingReport else { return false }
        isSavingReport = true
        let lifecycle = lifecycle ?? .live
        defer { isSavingReport = false }
        do {
            func validate() throws -> Data {
                guard reportPreview?.id == preview.id, let context = currentContext() else {
                    throw CampaignError.invalid("Preview the report again before saving a reviewed copy.")
                }
                try validateReportLease()
                return try preview.validatedData(ledger: ledger, baselineID: context.baselineID,
                                                  document: context.document)
            }
            _ = try validate()
            guard let url = lifecycle.chooseDestination() else { return false }
            let reviewedBytes = try validate()
            // Report exports may never replace their own canonical companion data.
            guard let context = currentContext() else {
                throw CampaignError.invalid("Preview the report again before saving a reviewed copy.")
            }
            try CampaignReportExportLifecycle.validateDestination(url,
                protecting: [storageURL, context.sourceURL].compactMap { $0 })
            let previous = try CampaignReportExportLifecycle.destinationBytes(url)
            // Recheck at the write boundary as well as after the modal returns.
            _ = try validate()
            try lifecycle.write(reviewedBytes, url, previous)
            reportPreview = nil
            problem = nil
            status = "Saved \(url.lastPathComponent). Nothing was sent."
            return true
        } catch { problem = error.localizedDescription; return false }
    }

    private func export(_ data: Data, name: String, type: UTType) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.message = "Save a private local copy. Review its contents before sharing it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let exists = FileManager.default.fileExists(atPath: url.path)
        let previous = exists ? try Data(contentsOf: url) : nil
        try DocumentFileWriter.write(data, to: url, overwriteExisting: exists, expectedExistingData: previous)
        status = "Saved \(url.lastPathComponent). Nothing was sent."
    }
}
