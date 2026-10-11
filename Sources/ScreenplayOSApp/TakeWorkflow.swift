import Foundation
import ScreenplayDomain

/// Rebuildable local service state. The screenplay's BoardFrame records remain
/// authoritative until the versioned project-package migration is implemented.
enum TakeWorkflow {
    static var applicationSupportRoot: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
    }

    static func storageURL(projectID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("ScreenplayOS/Takes/\(projectID.uuidString)/takes-v1.json")
    }

    @discardableResult
    static func persistProjection(of document: ScreenplayOSDocument, root: URL? = nil) throws -> TakeLedger {
        let boards = document.boardFrames
        let ledger = TakeLedger(
            projectID: document.screenplay.id,
            sourceRevision: try BoardTakeMigration.sourceRevision(boards),
            takes: try BoardTakeMigration.project(boards)
        )
        try TakeFileStore.write(ledger, to: storageURL(projectID: document.screenplay.id, root: root))
        return ledger
    }
}
