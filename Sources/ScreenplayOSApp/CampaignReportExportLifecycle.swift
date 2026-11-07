import AppKit
import Foundation
import Darwin
import UniformTypeIdentifiers

/// Small internal boundary for deterministic fixture tests. Production always
/// opens the native chooser and uses the shared exclusive/atomic file writer.
@MainActor
struct CampaignReportExportLifecycle {
    let chooseDestination: () -> URL?
    let write: (Data, URL, Data?) throws -> Void

    static var live: Self {
        Self(chooseDestination: {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Campaign-change-review.txt"
            panel.message = "Save exactly the reviewed report as a private local copy. Nothing is sent."
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }, write: { data, url, previous in
            // Bound the immediate destination check too. The shared writer then
            // checks exact existing bytes before replacement; it is not a lock
            // against noncooperating external writers.
            guard try destinationBytes(url) == previous else { throw DocumentSaveError.changedOnDisk }
            try DocumentFileWriter.write(data, to: url, overwriteExisting: previous != nil,
                                         expectedExistingData: previous)
        })
    }

    static func validateDestination(_ url: URL, protecting sources: [URL]) throws {
        guard url.isFileURL else { throw DocumentSaveError.changedOnDisk }
        let destination = url.resolvingSymlinksInPath()
        var targetInfo = stat()
        let hasTarget = stat(url.path, &targetInfo) == 0
        for source in sources {
            var sourceInfo = stat()
            let sameObject = hasTarget && stat(source.path, &sourceInfo) == 0
                && sourceInfo.st_dev == targetInfo.st_dev && sourceInfo.st_ino == targetInfo.st_ino
            guard destination != source.resolvingSymlinksInPath(), !sameObject else {
                throw DocumentSaveError.changedOnDisk
            }
        }
    }

    static func destinationBytes(_ url: URL) throws -> Data? {
        guard url.isFileURL else { throw DocumentSaveError.changedOnDisk }
        if !FileManager.default.fileExists(atPath: url.path) { return nil }
        // Reuse the existing bounded, regular-file-only reader. Destinations over
        // 16 MiB fail closed even if the report itself is much smaller.
        return try CampaignWorkspaceStore.readBackup(url)
    }
}
