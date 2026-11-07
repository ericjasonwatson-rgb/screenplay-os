import Foundation
import ScreenplayDomain

/// Session-scoped PTS and frame reuse for paused video scrubbing. Every entry
/// is tied to the exact local media path, SHA-256 and presentation timestamp.
/// A cache hit NEVER bypasses verification of the current local source bytes.
actor NativeVideoConformedPreview {
    private struct Entry {
        let mediaPath: String
        let mediaSHA256: String
        let index: NativeVideoPresentationIndex
    }

    private var entries: [Entry] = []
    private let maximumCachedSources = 4
    private var frames = NativeVerifiedFrameCache()
    private var cacheGeneration: UInt64 = 0

    func frame(_ clip: NativeAssemblyClip, localFrame: Int,
               screenplayURL: URL) async throws -> NativeVideoFramePreview.Decoded {
        let generation = cacheGeneration
        // This full SHA-256 verification is intentionally performed before
        // *both* cached and newly decoded frames can be returned.
        let verifiedURL = try NativeVideoFramePreview.verifiedVideoURL(
            clip, screenplayURL: screenplayURL)
        try Task.checkCancellation()
        let urlKey = verifiedURL.standardizedFileURL.path
        let index: NativeVideoPresentationIndex
        if let entry = entries.first(where: {
            $0.mediaPath == urlKey && $0.mediaSHA256 == clip.mediaSHA256
        }) {
            index = entry.index
        } else {
            let probed = try await NativeVideoTimestampProbe.inspect(
                verifiedURL, expectedSHA256: clip.mediaSHA256)
            try Task.checkCancellation()
            // An in-flight scan from before project navigation may finish
            // afterward. It must not repopulate an invalidated cache.
            if cacheGeneration == generation {
                entries.removeAll { $0.mediaPath == urlKey }
                if entries.count >= maximumCachedSources { entries.removeFirst() }
                entries.append(Entry(mediaPath: urlKey,
                                     mediaSHA256: clip.mediaSHA256, index: probed))
            }
            index = probed
        }

        let selected = try index.sample(for: clip, localFrame: localFrame)
        let key = NativeVerifiedFrameCache.Key(
            sourcePath: urlKey, mediaSHA256: clip.mediaSHA256,
            ptsValue: selected.timestamp.value,
            ptsTimescale: selected.timestamp.timescale)
        if let cached = frames.value(for: key) {
            try Task.checkCancellation()
            // Occurrence-local frame numbers are reconstructed rather than
            // cached, so a duplicated or split Take cannot borrow an ID.
            return NativeVideoFramePreview.Decoded(
                pngData: cached.pngData,
                requestedFrame: clip.sourceInFrame + localFrame,
                actualTimestampSeconds: cached.actualTimestampSeconds,
                selectedSampleIndex: selected.index,
                selectedSourceTimestamp: selected.timestamp)
        }

        // The decoder itself checks SHA-256 before AND after decoding a frame.
        let decoded = try await NativeVideoFramePreview.preview(
            clip, localFrame: localFrame, screenplayURL: screenplayURL,
            presentationIndex: index)
        try Task.checkCancellation()
        if cacheGeneration == generation {
            frames.insert(.init(pngData: decoded.pngData,
                                actualTimestampSeconds: decoded.actualTimestampSeconds),
                          for: key)
        }
        return decoded
    }

    /// Navigation or project replacement invalidates both kinds of cache.
    /// In-flight decoders cannot reinsert content after this generation change.
    func clear() {
        cacheGeneration &+= 1
        entries.removeAll()
        frames.clear()
    }

    #if DEBUG
    struct CacheDiagnostics: Sendable {
        let frameCount: Int
        let bytes: Int
        let hits: Int
        let misses: Int
    }

    func cacheDiagnostics() -> CacheDiagnostics {
        CacheDiagnostics(frameCount: frames.count, bytes: frames.totalBytes,
                         hits: frames.hits, misses: frames.misses)
    }
    #endif
}
