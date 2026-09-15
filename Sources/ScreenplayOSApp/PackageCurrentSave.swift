import Foundation
import Darwin
import ScreenplayDomain

/// Whole-package publication on macOS. Prior generations are retained, never pruned here.
enum PackageCurrentSave {
    struct Receipt { let destination: URL; let files: [String: Data]; let previous: URL? }
    struct RetainedFailure: Error { let location: URL; let published: Bool; let underlying: Error }
    static func write(_ session: PackageTextSession, base: [String: Data], destination: URL,
                      replacing: Bool, checkpoint: (String, URL) throws -> Void = { _, _ in }) throws -> Receipt {
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let lockURL = parent.appendingPathComponent("." + destination.lastPathComponent + ".save-lock")
        let lock = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw PackageEditedCopy.Failure.system(errno) }
        defer { close(lock) }
        var status = stat()
        guard fstat(lock, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw PackageEditedCopy.Failure.system(errno) }
        defer { flock(lock, LOCK_UN) }
        // Keep the lock inode: unlinking it could let another writer lock a new
        // inode while an existing writer still holds the old one.
        return try publish(session, base: base, destination: destination, replacing: replacing, checkpoint: checkpoint)
    }
    private static func publish(_ session: PackageTextSession, base: [String: Data], destination: URL,
                                replacing: Bool, checkpoint: (String, URL) throws -> Void) throws -> Receipt {
        guard destination.pathExtension == "screenplay" else { throw PackageEditedCopy.Failure.unsupported }
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        if replacing { guard try PackageEditedCopy.snapshot(target) == base else { throw PackageEditedCopy.Failure.changedSource } }
        var files = base
        var manifest = try PreservedJSON(files["manifest.json"]!)
        try manifest.replaceString(at: [.key("modified_at")], expected: manifest.string(at: [.key("modified_at")]),
                                   with: ISO8601DateFormatter().string(from: Date()))
        files["manifest.json"] = manifest.data; files["screenplay.json"] = session.screenplayBytes
        _ = try PackageTextSession(files: files)
        let stage = parent.appendingPathComponent(".screenplay-save-" + UUID().uuidString + ".screenplay")
        guard mkdir(stage.path, 0o700) == 0 else { throw PackageEditedCopy.Failure.system(errno) }
        var published = false
        do {
            try checkpoint("staging_created", stage)
            for name in files.keys.sorted() {
                try PackageEditedCopy.writeNew(stage.appendingPathComponent(name), data: files[name]!)
                try checkpoint("write:" + name, stage)
            }
            try PackageEditedCopy.syncDirectory(stage)
            guard try PackageEditedCopy.snapshot(stage) == files else { throw PackageEditedCopy.Failure.readback }
            try checkpoint("before_publish", stage)
            if replacing { guard try PackageEditedCopy.snapshot(target) == base else { throw PackageEditedCopy.Failure.changedSource } }
            // Swap leaves the entire previous package at stage. Exclusive creation
            // refuses an existing destination, including a competing symlink.
            let flags = replacing ? RENAME_SWAP : RENAME_EXCL
            guard renamex_np(stage.path, target.path, UInt32(flags)) == 0 else { throw PackageEditedCopy.Failure.system(errno) }
            published = true
            try checkpoint("published", stage)
            try PackageEditedCopy.syncDirectory(parent)
            if replacing { guard try PackageEditedCopy.snapshot(stage) == base else { throw PackageEditedCopy.Failure.changedSource } }
            try checkpoint("published_readback", target)
            guard try PackageEditedCopy.snapshot(target) == files else { throw PackageEditedCopy.Failure.readback }
            return Receipt(destination: target, files: files, previous: replacing ? stage : nil)
        } catch {
            // No blind rollback: a noncooperating writer may have changed either path.
            // Preserve both generations and leave the live editor dirty on any failure.
            throw RetainedFailure(location: published && !replacing ? target : stage, published: published, underlying: error)
        }
    }
}
