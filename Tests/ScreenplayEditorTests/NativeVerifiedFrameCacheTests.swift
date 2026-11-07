import Foundation
import XCTest
@testable import ScreenplayOSApp

final class NativeVerifiedFrameCacheTests: XCTestCase {
    private let hash = String(repeating: "a", count: 64)

    private func key(_ n: Int, source: String = "/tmp/Video Takes/a.mov",
                     fingerprint: String? = nil) -> NativeVerifiedFrameCache.Key {
        .init(sourcePath: source, mediaSHA256: fingerprint ?? hash,
              ptsValue: Int64(n), ptsTimescale: 24)
    }

    private func frame(_ bytes: Int, time: Double = 0) -> NativeVerifiedFrameCache.Value {
        .init(pngData: Data(repeating: 0x4f, count: bytes),
              actualTimestampSeconds: time)
    }

    func testByteAndCountBoundedLeastRecentlyUsedEviction() {
        var cache = NativeVerifiedFrameCache(maximumBytes: 9, maximumEntries: 2)
        XCTAssertTrue(cache.insert(frame(4), for: key(1)))
        XCTAssertTrue(cache.insert(frame(4), for: key(2)))
        XCTAssertEqual(cache.totalBytes, 8)
        XCTAssertNotNil(cache.value(for: key(1))) // 2 is now oldest
        XCTAssertTrue(cache.insert(frame(4), for: key(3)))
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.totalBytes, 8)
        XCTAssertNil(cache.value(for: key(2)))
        XCTAssertNotNil(cache.value(for: key(1)))
        XCTAssertNotNil(cache.value(for: key(3)))
        XCTAssertLessThanOrEqual(cache.totalBytes, cache.maximumBytes)
        XCTAssertLessThanOrEqual(cache.count, cache.maximumEntries)
    }

    func testOversizedFrameCannotEvictOrBypassLimit() {
        var cache = NativeVerifiedFrameCache(maximumBytes: 8, maximumEntries: 2)
        XCTAssertTrue(cache.insert(frame(6), for: key(1)))
        XCTAssertFalse(cache.insert(frame(9), for: key(2)))
        XCTAssertFalse(cache.insert(frame(0), for: key(2)))
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.totalBytes, 6)
        XCTAssertNotNil(cache.value(for: key(1)))
        XCTAssertNil(cache.value(for: key(2)))
    }

    func testSamePresentationTimeDoesNotCrossSourcePathOrFingerprint() {
        var cache = NativeVerifiedFrameCache(maximumBytes: 100, maximumEntries: 5)
        let original = key(24)
        XCTAssertTrue(cache.insert(frame(4, time: 1), for: original))
        XCTAssertNil(cache.value(for: key(24, source: "/tmp/Video Takes/b.mov")))
        XCTAssertNil(cache.value(for: key(24, fingerprint: String(repeating: "b", count: 64))))
        XCTAssertNil(cache.value(for: key(25)))
        XCTAssertEqual(cache.value(for: original)?.actualTimestampSeconds, 1)
    }

    func testReplacingAFrameUpdatesMemoryAndClearDropsContent() {
        var cache = NativeVerifiedFrameCache(maximumBytes: 8, maximumEntries: 2)
        XCTAssertTrue(cache.insert(frame(7), for: key(1)))
        XCTAssertTrue(cache.insert(frame(2), for: key(1)))
        XCTAssertEqual(cache.totalBytes, 2)
        XCTAssertEqual(cache.count, 1)
        XCTAssertTrue(cache.insert(frame(5), for: key(2)))
        XCTAssertEqual(cache.totalBytes, 7)
        cache.clear()
        XCTAssertEqual(cache.totalBytes, 0)
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.value(for: key(1)))
    }
}
