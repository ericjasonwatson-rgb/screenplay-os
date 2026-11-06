import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain

@MainActor
final class CampaignWorkspaceSession: ObservableObject {
    @Published private(set) var ledger: CampaignLedger
    @Published private(set) var problem: String?
    @Published private(set) var reportPreview: CampaignChangeReportPreview?
    @Published private(set) var isPerformingRecoveryCommand = false
    @Published private(set) var restorePreview: CampaignBackupRestorePreview?
    private var recoveryGeneration = UUID()
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
            discardRestorePreview()
            status = "Saved locally at \(Date().formatted(date: .omitted, time: .standard)). Nothing was sent."
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Dismissal and tab changes revoke even a chooser which has not returned yet.
    func discardRestorePreview() {
        recoveryGeneration = UUID()
        if restorePreview != nil { restorePreview = nil }
    }

    var canImport: Bool { bytes == nil && !isReadOnly }

    private func recoveryContext(_ currentContext: () -> CampaignRecoveryContext?) throws -> CampaignRecoveryContext {
        guard !isReadOnly, storageURL != nil, let context = currentContext(),
              context.projectID == ledger.projectID else {
            throw CampaignError.invalid("Campaign's project or presentation changed. Reopen Campaign and try again.")
        }
        return context
    }

    private func validateAbsentRestore() throws {
        guard bytes == nil, !isReadOnly, let storageURL else {
            throw CampaignError.invalid("Restore is available only before a local Campaign exists. Existing Campaign history was left untouched.")
        }
        let current = try CampaignWorkspaceStore.load(projectID: ledger.projectID, from: storageURL)
        guard current.bytes == nil else { throw CampaignWorkspaceStore.Failure.conflict }
    }

    @discardableResult
    func previewBackupRestore(lifecycle: CampaignBackupRestoreLifecycle? = nil,
                              currentContext: () -> CampaignRecoveryContext?) -> CampaignBackupRestorePreview? {
        guard !isPerformingRecoveryCommand else { return nil }
        isPerformingRecoveryCommand = true
        defer { isPerformingRecoveryCommand = false }
        discardRestorePreview()
        let generation = recoveryGeneration
        let lifecycle = lifecycle ?? .live
        do {
            let context = try recoveryContext(currentContext)
            func validate() throws {
                guard context.matches(try recoveryContext(currentContext)),
                      recoveryGeneration == generation else {
                    throw CampaignError.invalid("The restore preview was cancelled. Choose the backup again.")
                }
                try validateAbsentRestore()
            }
            try validate()
            guard let url = lifecycle.chooseSource() else { return nil }
            try validate()
            let selectedBytes = try lifecycle.read(url)
            let preview = try CampaignBackupRestorePreview(filename: url.lastPathComponent,
                bytes: selectedBytes, context: context)
            try validate()
            restorePreview = preview
            problem = nil
            return preview
        } catch { problem = error.localizedDescription; return nil }
    }

    /// Preview and confirmation both require an absent local ledger. The writer
    /// receives expected:nil even if a nested event creates new local history.
    @discardableResult
    func confirmBackupRestore(_ preview: CampaignBackupRestorePreview,
                              lifecycle: CampaignBackupRestoreLifecycle? = nil,
                              currentContext: () -> CampaignRecoveryContext?) -> Bool {
        guard !isPerformingRecoveryCommand else { return false }
        isPerformingRecoveryCommand = true
        defer { isPerformingRecoveryCommand = false }
        let lifecycle = lifecycle ?? .live
        let generation = recoveryGeneration
        var persistenceContext: CampaignRecoveryContext?
        do {
            guard restorePreview?.id == preview.id else {
                throw CampaignError.invalid("Choose the backup and preview it again before confirming restore.")
            }
            let context = try recoveryContext(currentContext)
            try validateAbsentRestore()
            let imported = try preview.validatedLedger(in: context)
            // Recheck the live context and exact nil lease immediately before the
            // persistence call. Do not route through commit's mutable bytes lease.
            guard context.matches(try recoveryContext(currentContext)),
                  restorePreview?.id == preview.id, recoveryGeneration == generation, let storageURL else {
                throw CampaignError.invalid("The restore preview was cancelled. Choose the backup again.")
            }
            try validateAbsentRestore()
            persistenceContext = context
            let saved = try lifecycle.restore(imported, storageURL)
            bytes = saved
            ledger = imported
            history.removeAll()
            canUndoDraft = false
            reportPreview = nil
            decisionPreview = nil
            discardRestorePreview()
            problem = nil
            status = "Restored Campaign records locally. Screenplay and project media were not changed. Nothing was sent."
            return true
        } catch {
            // Keep a failed-write proposal only while its exact context and nil
            // lease remain valid. Context/conflict failures revoke stale review.
            if restorePreview?.id == preview.id {
                let retryIsValid: Bool
                if let persistenceContext {
                    do {
                        let current = try recoveryContext(currentContext)
                        guard persistenceContext.matches(current), recoveryGeneration == generation else {
                            throw CampaignWorkspaceStore.Failure.conflict
                        }
                        try validateAbsentRestore()
                        retryIsValid = true
                    } catch { retryIsValid = false }
                } else { retryIsValid = false }
                if !retryIsValid { discardRestorePreview() }
            }
            problem = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func exportBackup(lifecycle: CampaignPrivateExportLifecycle? = nil,
                      currentContext: () -> CampaignRecoveryContext?) -> Bool {
        exportPrivateCopy(lifecycle: lifecycle, currentContext: currentContext) {
            (try CampaignWorkspaceStore.encoded(ledger), "Campaign-private-backup.json", .json)
        }
    }

    @discardableResult
    func exportAgencyOriginal(_ revisionID: UUID, lifecycle: CampaignPrivateExportLifecycle? = nil,
                              currentContext: () -> CampaignRecoveryContext?) -> Bool {
        exportPrivateCopy(lifecycle: lifecycle, currentContext: currentContext) {
            guard let revision = ledger.draft.agency?.revisions.first(where: { $0.id == revisionID }),
                  let origin = revision.origin else {
                throw CampaignError.invalid("The selected retained original is no longer available.")
            }
            try origin.validate()
            return (origin.originalBytes, revision.filename, UTType(filenameExtension: "docx") ?? .data)
        }
    }

    private func exportPrivateCopy(lifecycle: CampaignPrivateExportLifecycle?,
                                   currentContext: () -> CampaignRecoveryContext?,
                                   content: () throws -> (data: Data, filename: String, type: UTType)) -> Bool {
        guard !isPerformingRecoveryCommand else { return false }
        isPerformingRecoveryCommand = true
        defer { isPerformingRecoveryCommand = false }
        do {
            let generation = recoveryGeneration
            let context = try recoveryContext(currentContext)
            let ledgerData = try CampaignWorkspaceStore.encoded(ledger), lease = bytes
            let selected = try content()
            func validate() throws {
                guard context.matches(try recoveryContext(currentContext)),
                      recoveryGeneration == generation, bytes == lease,
                      try CampaignWorkspaceStore.encoded(ledger) == ledgerData else {
                    throw CampaignError.invalid("Campaign changed while choosing a destination. Review it and export again.")
                }
                try validateReportLease()
            }
            try validate()
            let lifecycle = lifecycle ?? .live(filename: selected.filename, type: selected.type)
            guard let url = lifecycle.chooseDestination() else { return false }
            try validate()
            let protected = [storageURL, context.sourceURL].compactMap { $0 }
            try CampaignReportExportLifecycle.validateDestination(url, protecting: protected)
            let previous = try CampaignReportExportLifecycle.destinationBytes(url)
            try validate()
            try CampaignReportExportLifecycle.validateDestination(url, protecting: protected)
            try lifecycle.write(selected.data, url, previous)
            problem = nil
            status = "Saved \(url.lastPathComponent). Nothing was sent."
            return true
        } catch { problem = error.localizedDescription; return false }
    }

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
        guard !isPerformingRecoveryCommand else { return false }
        isPerformingRecoveryCommand = true
        let lifecycle = lifecycle ?? .live
        defer { isPerformingRecoveryCommand = false }
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

}
