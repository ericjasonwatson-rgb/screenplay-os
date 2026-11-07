import Foundation
import XCTest
@testable import ScreenplayDomain

final class NativeMonotonicPlaybackClockTests: XCTestCase {
    func testExactFrameDeadlinesUseMonotonicIntegerTime() throws {
        let clock = try NativeMonotonicPlaybackClock(
            totalFrames: 240, startedAtNanoseconds: 0)
        XCTAssertEqual(clock.frame(atNanoseconds: 0), 0)
        XCTAssertEqual(clock.frame(atNanoseconds: 41_666_666), 0)
        XCTAssertEqual(clock.frame(atNanoseconds: 41_666_667), 1)
        XCTAssertEqual(clock.frame(atNanoseconds: 83_333_333), 1)
        XCTAssertEqual(clock.frame(atNanoseconds: 83_333_334), 2)
        XCTAssertEqual(clock.frame(atNanoseconds: 1_000_000_000), 24)
        XCTAssertEqual(clock.nextFrameDeadline(afterNanoseconds: 0), 41_666_667)
        XCTAssertEqual(clock.nextFrameDeadline(afterNanoseconds: 41_666_667), 83_333_334)
    }

    func testPausedClockDoesNotConsumeTimeAndResumesFromSelectedFrame() throws {
        var clock = try NativeMonotonicPlaybackClock(
            totalFrames: 240, startedAtNanoseconds: 1_000_000_000)
        XCTAssertEqual(clock.frame(atNanoseconds: 1_500_000_000), 12)
        clock.pause(atNanoseconds: 1_500_000_000)
        XCTAssertFalse(clock.isPlaying)
        XCTAssertEqual(clock.frame(atNanoseconds: 9_000_000_000), 12)
        XCTAssertNil(clock.nextFrameDeadline(afterNanoseconds: 9_000_000_000))
        clock.resume(atNanoseconds: 10_000_000_000)
        XCTAssertEqual(clock.frame(atNanoseconds: 10_250_000_000), 18)
        try clock.seek(toFrame: 3, atNanoseconds: 10_250_000_000)
        XCTAssertEqual(clock.frame(atNanoseconds: 10_500_000_000), 9)
    }

    func testDisplayStallSkipsFramesRatherThanSlowingPlayback() throws {
        let clock = try NativeMonotonicPlaybackClock(
            totalFrames: 240, startedAtNanoseconds: 0)
        XCTAssertEqual(clock.frame(atNanoseconds: 2_000_000_000), 48)
        XCTAssertEqual(clock.nextFrameDeadline(afterNanoseconds: 2_000_000_000),
                       2_041_666_667)
        XCTAssertEqual(clock.frame(atNanoseconds: 30_000_000_000), 240)
        XCTAssertNil(clock.nextFrameDeadline(afterNanoseconds: 30_000_000_000))
    }

    func testEndOfEditAndBadInputFailClosed() throws {
        XCTAssertThrowsError(try NativeMonotonicPlaybackClock(
            totalFrames: 0, startedAtNanoseconds: 0))
        XCTAssertThrowsError(try NativeMonotonicPlaybackClock(
            totalFrames: 24, startFrame: 25, startedAtNanoseconds: 0))
        var clock = try NativeMonotonicPlaybackClock(
            totalFrames: 48, startFrame: 47, startedAtNanoseconds: 0)
        XCTAssertEqual(clock.frame(atNanoseconds: 1_000_000_000), 48)
        XCTAssertNil(clock.nextFrameDeadline(afterNanoseconds: 1_000_000_000))
        XCTAssertThrowsError(try clock.seek(toFrame: -1, atNanoseconds: 0))
        XCTAssertThrowsError(try clock.seek(toFrame: 49, atNanoseconds: 0))
        try clock.seek(toFrame: 48, atNanoseconds: 1_000_000_000)
        XCTAssertFalse(clock.isPlaying)
        clock.resume(atNanoseconds: 2_000_000_000)
        XCTAssertFalse(clock.isPlaying)
    }

    func testHugeTimeJumpAndMonotonicOverflowDoNotWrapFrames() throws {
        let clock = try NativeMonotonicPlaybackClock(
            totalFrames: 24, startedAtNanoseconds: 1_000)
        XCTAssertEqual(clock.frame(atNanoseconds: UInt64.max), 24)
        XCTAssertEqual(clock.frame(atNanoseconds: 0), 0)

        let nearOverflow = try NativeMonotonicPlaybackClock(
            totalFrames: 48, startedAtNanoseconds: UInt64.max - 10)
        XCTAssertEqual(nearOverflow.frame(atNanoseconds: UInt64.max), 0)
        XCTAssertNil(nearOverflow.nextFrameDeadline(afterNanoseconds: UInt64.max))
    }
}
