import AppKit
import Foundation
import UniformTypeIdentifiers
import ScreenplayDomain

/// A presentation lease supplied from live UI state after native modal loops.
/// URLs are transient protection targets, never persisted in a Campaign ledger.
struct CampaignRecoveryContext {
    let projectID: UUID
    let presentationID: UUID
    let sourceURL: URL?

    func matches(_ other: Self) -> Bool {
        projectID == other.projectID && presentationID == other.presentationID
            && sourceURL.map { Data($0.absoluteString.utf8) } == other.sourceURL.map { Data($0.absoluteString.utf8) }
    }
}

/// Only inventory is displayed. Private body text, notes, approval evidence and
/// retained document bytes remain in the frozen in-memory candidate until Confirm.
struct CampaignBackupRestorePreview: Identifiable {
    let id = UUID()
    let filename: String
    let projectID: UUID
    let byteCount: Int
    let deliverableCount: Int
    let assumptionCount: Int
    let baselineCount: Int
    let decisionCount: Int
    let agencyDocumentCount: Int
    let agencyRevisionCount: Int
    let retainedOriginalCount: Int
    let disclosure = "This private backup may contain confidential Campaign scope, notes, source text, retained original documents, baseline snapshots and approval evidence. It does not restore the screenplay or project media. IDs and hashes do not verify authenticity. Restored decisions are historical local records, not new approval or permission to spend or send anything."

    private let selectedBytes: Data
    private let context: CampaignRecoveryContext

    init(filename: String, bytes: Data, context: CampaignRecoveryContext) throws {
        let imported = try CampaignWorkspaceStore.decode(bytes, projectID: context.projectID)
        self.filename = filename
        selectedBytes = bytes
        self.context = context
        projectID = imported.projectID
        byteCount = bytes.count
        deliverableCount = imported.draft.deliverables.count
        assumptionCount = imported.draft.assumptions.count
        baselineCount = imported.baselines.count
        decisionCount = imported.decisions.count
        // Count identities once across both the current draft and immutable history.
        let revisions = ([imported.draft] + imported.baselines.map(\.draft))
            .flatMap { $0.agency?.revisions ?? [] }
        agencyDocumentCount = Set(revisions.map(\.documentID)).count
        agencyRevisionCount = Set(revisions.map(\.id)).count
        retainedOriginalCount = Set(revisions.filter { $0.origin != nil }.map(\.id)).count
    }

    func validatedLedger(in context: CampaignRecoveryContext) throws -> CampaignLedger {
        guard self.context.matches(context) else {
            throw CampaignError.invalid("Campaign's project or presentation changed. Choose the backup and review it again.")
        }
        // Decode exactly the selected bytes, never reread the imported pathname or
        // reconstruct the candidate from displayed inventory or current UI fields.
        return try CampaignWorkspaceStore.decode(selectedBytes, projectID: projectID)
    }
}

/// Small deterministic seams; production uses bounded reading and the existing
/// cooperating-writer lock with an explicit absent-file lease, never overwrite.
@MainActor
struct CampaignBackupRestoreLifecycle {
    let chooseSource: () -> URL?
    let read: (URL) throws -> Data
    let restore: (CampaignLedger, URL) throws -> Data

    static var live: Self {
        Self(chooseSource: {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = "Preview a private Campaign backup for this project. Restoring requires a separate confirmation and does not restore the screenplay or project media."
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }, read: CampaignWorkspaceStore.readBackup, restore: { ledger, url in
            try CampaignWorkspaceStore.save(ledger, to: url, expected: nil)
        })
    }
}

@MainActor
struct CampaignPrivateExportLifecycle {
    let chooseDestination: () -> URL?
    let write: (Data, URL, Data?) throws -> Void

    static func live(filename: String, type: UTType) -> Self {
        Self(chooseDestination: {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [type]
            panel.nameFieldStringValue = filename
            panel.message = "Save a private local copy. Backups include notes, approval evidence and retained source documents. Review the contents before sharing; nothing is sent."
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }, write: CampaignReportExportLifecycle.live.write)
    }
}
