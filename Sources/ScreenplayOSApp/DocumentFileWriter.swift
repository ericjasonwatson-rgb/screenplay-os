import Foundation

/// Writes a complete file before making a new destination visible.
/// Linking the temporary sibling is exclusive: it fails if the destination exists.
enum DocumentFileWriter {
    static func write(_ data: Data, to url: URL, overwriteExisting: Bool) throws {
        if overwriteExisting {
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
