import Foundation

enum DocumentSaveError: LocalizedError {
    case changedOnDisk
    var errorDescription: String? {
        "The file changed outside ScreenplayOS or is no longer available. Save your edits as a separate copy."
    }
}

/// Checks the exact version read by this document immediately before atomic replacement.
/// This detects existing outside edits; it is not a lock against concurrent external writers.
/// Exclusive creation also prevents first-save collisions.
enum DocumentFileWriter {
    static func write(_ data: Data, to url: URL, overwriteExisting: Bool, expectedExistingData: Data? = nil) throws {
        if overwriteExisting {
            guard let expectedExistingData else { throw DocumentSaveError.changedOnDisk }
            guard let current = try? Data(contentsOf: url), current == expectedExistingData else {
                throw DocumentSaveError.changedOnDisk
            }
            try data.write(to: url, options: .atomic)
            return
        }
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".screenplay-save-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try FileManager.default.linkItem(at: temporaryURL, to: url)
    }
}
