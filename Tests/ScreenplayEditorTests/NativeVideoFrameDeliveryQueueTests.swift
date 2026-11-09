import Foundation
import XCTest
@testable import ScreenplayDomain

final class NativeVideoFrameDeliveryQueueTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    private func video(_ take: UUID = UUID(), count: Int = 8,
                       occurrence: UUID = UUID()) -> NativeAssemblyClip {
        NativeAssemblyClip(id: occurrence, sceneSpineID: "SC-001", shotID: UUID(),
            boardFrameID: UUID(), takeID: take, mediaSHA256: digest,
            mediaPath: "Video Takes/verified.mp4", label: "Video", frameCount: count,
            mediaKind: .video, sourceInFrame: 0, sourceFrameLimit: count)
    }

    private func still(count: Int = 2) -> NativeAssemblyClip {
        NativeAssemblyClip(sceneSpineID: "SC-001", shotID: UUID(),
            boardFrameID: UUID(), takeID: UUID(), mediaSHA256: digest,
            mediaPath: "Board Images/still.png", label: "Still", frameCount: count)
    }

    private func project(_ clips: [NativeAssemblyClip]) -> NativeAssemblyProject {
        NativeAssemblyProject(projectID: UUID(), sceneSpineID: "SC-001",
            boardRevision: digest, clips: clips)
    }

    private func payload(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 8)
    }

    func testBoundedLookaheadAndOutOfOrderCompletion() throws {
        var queue = try NativeVideoFrameDeliveryQueue(
            project: project([video()]), maximumInFlight: 2,
            maximumReady: 2, maximumReadyBytes: 16, lookaheadFrames: 3)
        let planned = queue.plan(at: 0)
        XCTAssertEqual(planned.map(\.timelineFrame), [0, 1])
        XCTAssertEqual(queue.inFlightCount, 2)
        XCTAssertTrue(queue.plan(at: 0).isEmpty)
        XCTAssertTrue(queue.accept(payload(0x22), for: planned[1], currentTimelineFrame: 0))
        XCTAssertNil(queue.presentation(at: 0)) // Never display a future frame.
        XCTAssertTrue(queue.accept(payload(0x11), for: planned[0], currentTimelineFrame: 0))
        let current = queue.presentation(at: 0)
        XCTAssertEqual(current?.deliveredFrame, 0)
        XCTAssertEqual(current?.pngData, payload(0x11))
        XCTAssertEqual(queue.readyCount, 2)
        XCTAssertEqual(queue.readyBytes, 16)
        XCTAssertEqual(queue.inFlightCount, 0)
    }

    func testLateDecodeIsDroppedAndSingleFrameHoldIsBounded() throws {
        var queue = try NativeVideoFrameDeliveryQueue(
            project: project([video(count: 8)]), lookaheadFrames: 2)
        let planned = queue.plan(at: 0)
        XCTAssertEqual(planned.map(\.timelineFrame), [0, 1])
        XCTAssertFalse(queue.accept(payload(1), for: planned[0],
                                    currentTimelineFrame: 2))
        XCTAssertEqual(queue.lateCompletions, 1)
        XCTAssertTrue(queue.accept(payload(2), for: planned[1],
                                   currentTimelineFrame: 1))
        XCTAssertTrue(queue.presentation(at: 2)?.isHeld == true)
        XCTAssertEqual(queue.presentation(at: 2)?.deliveredFrame, 1)
        XCTAssertNil(queue.presentation(at: 3)) // Never hold more than one frame.
        _ = queue.plan(at: 3)
        XCTAssertEqual(queue.readyBytes, 0)
    }

    func testNeverHoldOneTakeAcrossEditorialCut() throws {
        let take = UUID()
        let first = video(take, count: 2)
        let next = video(take, count: 2) // Same Take, different occurrence.
        var queue = try NativeVideoFrameDeliveryQueue(
            project: project([first, next]),
            maximumInFlight: 2, lookaheadFrames: 2)
        let planned = queue.plan(at: 1)
        guard let beforeCut = planned.first(where: { $0.timelineFrame == 1 }) else {
            return XCTFail("Expected last frame before cut")
        }
        XCTAssertTrue(queue.accept(payload(1), for: beforeCut,
                                   currentTimelineFrame: 1))
        XCTAssertNotNil(queue.presentation(at: 1))
        XCTAssertNil(queue.presentation(at: 2))
        XCTAssertNotEqual(first.id, next.id)
    }

    func testResetRefusesOldSessionResponsesAndSourceIdentityForgery() throws {
        var queue = try NativeVideoFrameDeliveryQueue(
            project: project([video()]))
        guard let requested = queue.plan(at: 0).first else {
            return XCTFail("Missing scheduled request")
        }
        var forged = requested
        // Requests are immutable: use another independent queue's token.
        var otherQueue = try NativeVideoFrameDeliveryQueue(
            project: queue.project)
        guard let other = otherQueue.plan(at: 0).first else {
            return XCTFail("Missing second request")
        }
        forged = other
        XCTAssertFalse(queue.accept(payload(2), for: forged, currentTimelineFrame: 0))
        XCTAssertEqual(queue.rejectedCompletions, 1)
        queue.reset()
        XCTAssertEqual(queue.readyCount, 0)
        XCTAssertEqual(queue.inFlightCount, 0)
        XCTAssertFalse(queue.accept(payload(1), for: requested,
                                    currentTimelineFrame: 0))
        XCTAssertEqual(queue.rejectedCompletions, 2)
        let fresh = queue.plan(at: 0)
        XCTAssertNotEqual(fresh[0].sessionID, requested.sessionID)
    }

    func testReadyByteBudgetAndStillFramesNeverScheduleVideo() throws {
        let first = video(count: 3)
        let image = still()
        let second = video(count: 2)
        var queue = try NativeVideoFrameDeliveryQueue(
            project: project([first, image, second]),
            maximumInFlight: 2, maximumReady: 2,
            maximumReadyBytes: 8, lookaheadFrames: 6)
        let planned = queue.plan(at: 2)
        XCTAssertEqual(planned.map(\.timelineFrame), [2, 5])
        XCTAssertFalse(queue.accept(Data(repeating: 1, count: 9),
                                    for: planned[0], currentTimelineFrame: 2))
        XCTAssertEqual(queue.readyBytes, 0)
        XCTAssertTrue(queue.accept(payload(1), for: planned[1],
                                   currentTimelineFrame: 2))
        XCTAssertNil(queue.presentation(at: 3))
        XCTAssertNil(queue.presentation(at: 4))
        XCTAssertEqual(queue.presentation(at: 5)?.occurrenceID, second.id)
        XCTAssertEqual(queue.readyBytes, 8)
        let later = queue.plan(at: 5)
        XCTAssertEqual(later.map(\.timelineFrame), [6])
        XCTAssertTrue(queue.accept(payload(2), for: later[0],
                                   currentTimelineFrame: 5))
        XCTAssertLessThanOrEqual(queue.readyBytes, 8)
        XCTAssertLessThanOrEqual(queue.readyCount, 2)
    }

    func testInvalidBudgetsFailBeforeAnyMediaCanBeScheduled() throws {
        XCTAssertThrowsError(try NativeVideoFrameDeliveryQueue(
            project: project([video()]), maximumInFlight: 0))
        XCTAssertThrowsError(try NativeVideoFrameDeliveryQueue(
            project: project([video()]), maximumReady: 17))
        XCTAssertThrowsError(try NativeVideoFrameDeliveryQueue(
            project: project([video()]), lookaheadFrames: 13))
        XCTAssertThrowsError(try NativeVideoFrameDeliveryQueue(
            project: project([video()]), maximumReadyBytes: 0))
    }
}
