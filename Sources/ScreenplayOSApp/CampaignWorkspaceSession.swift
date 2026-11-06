import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain

@MainActor
final class CampaignWorkspaceSession: ObservableObject {
    @Published private(set) var ledger: CampaignLedger
    @Published private(set) var problem: String?
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

    @discardableResult
    func record(baselineID: UUID, scope: CampaignApprovalScope, approver: String, evidence: String,
                document: ScreenplayOSDocument, amount: String, currency: String) -> Bool {
        do {
            var next = ledger
            let ceiling: Int64?
            if scope == .spend {
                guard let parsed = Int64(amount), parsed >= 0 else {
                    throw CampaignError.invalid("Enter the authorized ceiling as a nonnegative integer in minor currency units, for example 12500 for USD 125.00.")
                }
                ceiling = parsed
            } else { ceiling = nil }
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

    func exportReport(baselineID: UUID, document: ScreenplayOSDocument) {
        do {
            guard let baseline = ledger.baselines.first(where: { $0.id == baselineID }) else { return }
            let changes = try ledger.compare(baselineID: baselineID, document: document)
            var lines = ["CAMPAIGN CHANGE REVIEW", "Project: \(document.project.metadata.title)",
                         "Baseline: \(baseline.name) [\(baseline.id)]", "Frozen: \(baseline.createdAt.formatted())",
                         "Human review required. This is not a quote, approval, or authorization to spend.",
                         "Scope: campaign brief, deliverables, assumptions, script, shots, board timing and selected image metadata. Imported text and bounded DOCX extraction are tracked with retained original hashes, manual review and line citations. PDF import is not enabled. Extraction may omit layout or nontext content; originals must be checked by a person. No OCR or media analysis.", ""]
            if changes.isEmpty { lines.append("No tracked changes or unresolved source links detected.") }
            for change in changes {
                lines += [change.title, "Source: \(change.sourceKind.rawValue) \(change.sourceID)",
                          "Affected deliverables: \(change.affectedDeliverableIDs.map(\.uuidString).joined(separator: ", "))",
                          "BEFORE", change.before, "AFTER", change.after, ""]
            }
            try export(Data(lines.joined(separator: "\n").utf8), name: "Campaign-change-review.txt", type: .plainText)
        } catch { problem = error.localizedDescription }
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
