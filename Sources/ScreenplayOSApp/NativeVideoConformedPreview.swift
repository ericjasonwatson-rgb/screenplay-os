import Foundation
import ScreenplayDomain

/// Session-scoped, bounded index reuse for paused video scrubbing. An index is
/// always built from the actual SHA-verified local asset; it is never accepted
/// from an untrusted file or borrowed from another Take identity.
actor NativeVideoConformedPreview {
    private struct Entry {
        let mediaPath: String
        let mediaSHA256: String
        let index: NativeVideoPresentationIndex
    }

    private var entries: [Entry] = []
    private let maximumCachedSources = 4

    func frame(_ clip: NativeAssemblyClip, localFrame: Int,
               screenplayURL: URL) async throws -> NativeVideoFramePreview.Decoded {
        // Do not look up cached state until path safety and current bytes pass.
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
            entries.removeAll { $0.mediaPath == urlKey }
            if entries.count >= maximumCachedSources { entries.removeFirst() }
            entries.append(Entry(mediaPath: urlKey,
                                 mediaSHA256: clip.mediaSHA256, index: probed))
            index = probed
        }
        // The decoder rechecks the original image source file before and after
        // generating its frame; a cached index does not bypass media verification.
        return try await NativeVideoFramePreview.preview(
            clip, localFrame: localFrame, screenplayURL: screenplayURL,
            presentationIndex: index)
    }

    func clear() {
        entries.removeAll()
    }
}
