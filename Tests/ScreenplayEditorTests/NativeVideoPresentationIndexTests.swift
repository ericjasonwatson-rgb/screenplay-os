import Foundation
import XCTest
@testable import ScreenplayDomain

final class NativeVideoPresentationIndexTests: XCTestCase {
    private let digest = String(repeating: "b", count: 64)

    private func index(_ samples: [NativeVideoTimestamp],
                       duration: NativeVideoTimestamp) throws -> NativeVideoPresentationIndex {
        try NativeVideoPresentationIndex(mediaSHA256: digest, trackID: 1,
                                         duration: duration, samples: samples)
    }

    func testTwentyThreePointNineSevenSixFPSRetainsExactRationalPTS() throws {
        // 24000/1001 fps. The 24 fps edit frame at 1/24 second occurs
        // BEFORE the second source sample at 1001/24000 seconds.
        let samples = (0..<48).map {
            NativeVideoTimestamp(value: Int64($0) * 1001, timescale: 24_000)
        }
        let source = try index(samples, duration: .init(value: 2_002, timescale: 1000))
        XCTAssertEqual(try source.sample(atTimelineFrame: 1).index, 0)
        XCTAssertEqual(try source.sample(atTimelineFrame: 2).index, 1)
        XCTAssertEqual(try source.sample(atTimelineFrame: 24).index, 23)
        XCTAssertEqual(try source.sample(atTimelineFrame: 24).timestamp,
                       samples[23])
        XCTAssertEqual(try source.sample(atTimelineFrame: 47).index, 46)
    }

    func testTwentyFiveFPSAndVariableTimestampsMapToVisibleSamples() throws {
        let cfr = try index((0..<50).map {
            NativeVideoTimestamp(value: Int64($0), timescale: 25)
        }, duration: .init(value: 2, timescale: 1))
        XCTAssertEqual(try cfr.sample(atTimelineFrame: 1).index, 1)
        XCTAssertEqual(try cfr.sample(atTimelineFrame: 24).index, 25)

        let vfr = try index([
            .init(value: 0, timescale: 1),
            .init(value: 1, timescale: 25),
            .init(value: 1, timescale: 10),
            .init(value: 3, timescale: 10)
        ], duration: .init(value: 2, timescale: 5))
        XCTAssertEqual(try vfr.sample(atTimelineFrame: 1).index, 1)
        XCTAssertEqual(try vfr.sample(atTimelineFrame: 2).index, 1)
        XCTAssertEqual(try vfr.sample(atTimelineFrame: 3).index, 2)
        XCTAssertEqual(try vfr.sample(atTimelineFrame: 7).index, 2)
        XCTAssertEqual(try vfr.sample(atTimelineFrame: 8).index, 3)
    }

    func testMissingOrInvalidPresentationTimesFailClosed() throws {
        XCTAssertThrowsError(try index([], duration: .init(value: 1, timescale: 1)))
        XCTAssertThrowsError(try index([.init(value: -1, timescale: 24)],
                                      duration: .init(value: 1, timescale: 1)))
        XCTAssertThrowsError(try index([.init(value: 0, timescale: 0)],
                                      duration: .init(value: 1, timescale: 1)))
        XCTAssertThrowsError(try index([
            .init(value: 0, timescale: 1), .init(value: 0, timescale: 24)
        ], duration: .init(value: 1, timescale: 1)))
        XCTAssertThrowsError(try index([
            .init(value: 1, timescale: 24), .init(value: 0, timescale: 1)
        ], duration: .init(value: 1, timescale: 1)))
        let lateFirst = try index([.init(value: 1, timescale: 25)],
                                  duration: .init(value: 1, timescale: 1))
        XCTAssertThrowsError(try lateFirst.sample(atTimelineFrame: 0))
        XCTAssertThrowsError(try lateFirst.sample(atTimelineFrame: -1))
        XCTAssertThrowsError(try lateFirst.sample(atTimelineFrame: 24))
    }

    func testIndexSerializesWithoutFloatingPointTimeDrift() throws {
        let source = try index([
            .init(value: 0, timescale: 24_000),
            .init(value: 1001, timescale: 24_000),
            .init(value: 2002, timescale: 24_000)
        ], duration: .init(value: 3003, timescale: 24_000))
        let restored = try JSONDecoder().decode(NativeVideoPresentationIndex.self,
                                                 from: JSONEncoder().encode(source))
        XCTAssertEqual(restored, source)
        XCTAssertEqual(try restored.sample(atTimelineFrame: 2).timestamp,
                       .init(value: 1001, timescale: 24_000))
    }
}
