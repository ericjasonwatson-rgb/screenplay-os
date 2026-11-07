import Foundation

/// A small, in-memory cache of already verified video stills. Cache hits are
/// never authorization: the caller MUST verify the current source SHA-256
/// before retrieving any cached frame.
struct NativeVerifiedFrameCache {
    struct Key: Hashable, Sendable {
        let sourcePath: String
        let mediaSHA256: String
        let ptsValue: Int64
        let ptsTimescale: Int32
    }

    struct Value: Sendable {
        let pngData: Data
        let actualTimestampSeconds: Double
    }

    private struct Entry {
        let key: Key
        let value: Value
    }

    let maximumBytes: Int
    let maximumEntries: Int
    private var entries: [Entry] = []
    private(set) var totalBytes = 0
    private(set) var hits = 0
    private(set) var misses = 0

    init(maximumBytes: Int = 16 * 1024 * 1024, maximumEntries: Int = 16) {
        self.maximumBytes = max(1, maximumBytes)
        self.maximumEntries = max(1, maximumEntries)
    }

    var count: Int { entries.count }

    mutating func value(for key: Key) -> Value? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else {
            misses += 1
            return nil
        }
        hits += 1
        let entry = entries.remove(at: index)
        entries.append(entry) // LRU: newest at the end.
        return entry.value
    }

    @discardableResult
    mutating func insert(_ value: Value, for key: Key) -> Bool {
        let size = value.pngData.count
        guard size > 0, size <= maximumBytes,
              value.actualTimestampSeconds.isFinite,
              key.ptsTimescale > 0 else { return false }

        if let existing = entries.firstIndex(where: { $0.key == key }) {
            let old = entries.remove(at: existing)
            totalBytes -= old.value.pngData.count
        }
        while !entries.isEmpty &&
                (entries.count >= maximumEntries || totalBytes > maximumBytes - size) {
            let evicted = entries.removeFirst()
            totalBytes -= evicted.value.pngData.count
        }
        entries.append(Entry(key: key, value: value))
        totalBytes += size
        return true
    }

    mutating func clear() {
        entries.removeAll(keepingCapacity: false)
        totalBytes = 0
        hits = 0
        misses = 0
    }
}
