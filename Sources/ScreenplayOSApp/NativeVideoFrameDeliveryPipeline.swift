import Foundation
import ScreenplayDomain

/// Experimental video-only decode adapter for the monotonic timeline clock.
/// It deliberately does NOT enable the UI's Play control or audio/rendering.
/// Each task decodes through the existing SHA-256-verified, source-PTS-conformed
/// reader, while the policy bounds concurrent jobs and refuses stale frames.
actor NativeVideoFrameDeliveryPipeline {
    private var queue: NativeVideoFrameDeliveryQueue
    private let preview = NativeVideoConformedPreview()
    private let screenplayURL: URL
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var currentFrame = 0
    private(set) var decodeFailures = 0

    init(project: NativeAssemblyProject, screenplayURL: URL) throws {
        guard screenplayURL.isFileURL else { throw NativeAssemblyError.invalidFile }
        queue = try NativeVideoFrameDeliveryQueue(project: project)
        self.screenplayURL = screenplayURL
    }

    /// Call from a future frame-display driver with the current monotonic
    /// timeline frame. Returns nil if the correct video has not yet arrived.
    /// Late decodes are not backfilled, and other occurrences cannot be shown
    /// through an edit boundary.
    func tick(atTimelineFrame frame: Int)
        -> NativeVideoFrameDeliveryQueue.Presentation? {
        currentFrame = frame
        if let current = queue.project.clip(at: frame),
           current.mediaKind == .video {
            // The ready queue is also a cache. Before presenting previously
            // decoded pixels, require the current original media to retain
            // its SHA-256; otherwise invalidate every pending/ready token.
            do {
                _ = try NativeVideoFramePreview.verifiedVideoURL(
                    current, screenplayURL: screenplayURL)
            } catch {
                for task in tasks.values { task.cancel() }
                tasks.removeAll()
                queue.reset()
                decodeFailures += 1
                return nil
            }
        }
        let requested = queue.plan(at: frame)
        let live = queue.inFlightRequestIDs
        for (id, task) in tasks where !live.contains(id) {
            task.cancel()
            tasks.removeValue(forKey: id)
        }
        for request in requested {
            let verifiedPreview = preview
            let source = screenplayURL
            tasks[request.id] = Task { [weak self] in
                do {
                    let decoded = try await verifiedPreview.frame(
                        request.clip, localFrame: request.localFrame,
                        screenplayURL: source)
                    await self?.didDecode(decoded.pngData, request: request)
                } catch {
                    await self?.didFail(request)
                }
            }
        }
        return queue.presentation(at: frame)
    }

    private func didDecode(_ pngData: Data,
                           request: NativeVideoFrameDeliveryQueue.Request) {
        tasks.removeValue(forKey: request.id)
        _ = queue.accept(pngData, for: request, currentTimelineFrame: currentFrame)
    }

    private func didFail(_ request: NativeVideoFrameDeliveryQueue.Request) {
        // A clock jump intentionally cancels obsolete decode work. Do not
        // count those cancellations as media/decoder failures.
        let wasCurrent = queue.inFlightRequestIDs.contains(request.id)
        tasks.removeValue(forKey: request.id)
        queue.fail(request)
        if wasCurrent { decodeFailures += 1 }
    }

    /// Stops any requested work and invalidates the source index and frame
    /// caches. Results of pre-stop requests cannot be accepted afterwards.
    func reset() async {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        queue.reset()
        currentFrame = 0
        await preview.clear()
    }

    /// Diagnostic-only deterministic drain for synthetic XCTest fixtures.
    /// Real playback must NEVER synchronously wait for all decoders to finish.
    #if DEBUG
    func drainCurrentRequests() async {
        let snapshot = Array(tasks.values)
        for task in snapshot { await task.value }
    }

    struct Diagnostics: Sendable {
        let inFlight: Int
        let ready: Int
        let readyBytes: Int
        let lateCompletions: Int
        let rejectedCompletions: Int
        let decodeFailures: Int
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(inFlight: queue.inFlightCount, ready: queue.readyCount,
                    readyBytes: queue.readyBytes,
                    lateCompletions: queue.lateCompletions,
                    rejectedCompletions: queue.rejectedCompletions,
                    decodeFailures: decodeFailures)
    }
    #endif
}
