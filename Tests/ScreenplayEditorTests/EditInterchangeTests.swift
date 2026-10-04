import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("NLE timing interchange") struct EditInterchangeTests {
    func segments() -> [TimedEditSegment] {
        [TimedEditSegment(id: UUID(), sceneSpineID: "S001", label: "A & <B> \"C\"\nTITLE: bad", start: 0, duration: 1.1, clip: nil, estimate: nil),
         TimedEditSegment(id: UUID(), sceneSpineID: "S002", label: "Second", start: 1.1, duration: 60, clip: nil, estimate: nil)]
    }
    @Test func quantizationIsContiguousAndTimecodeRollsOver() throws {
        let events = try EditInterchange.events(segments())
        #expect(events[0].end == 26)
        #expect(events[1].start == 26)
        #expect(events[1].end == 1466)
        #expect(EditInterchange.timecode(1466) == "00:01:01:02")
        let edl = try EditInterchange.edl(title: "Test\nInjected", segments: segments())
        #expect(edl.contains("TITLE: Test Injected\nFCM: NON-DROP FRAME"))
        #expect(edl.contains("00:00:00:00 00:00:01:02 00:00:00:00 00:00:01:02"))
        #expect(edl.contains("00:00:00:00 00:01:00:00 00:00:01:02 00:01:01:02"))
        #expect(!edl.contains("\nTITLE: bad"))
    }
    @Test func xmlIsWellFormedAndRetainsNamesAndDurations() throws {
        let text = try EditInterchange.fcpxml(title: "Film & Friends", segments: segments())
        let xml = try XMLDocument(xmlString: text)
        let gaps = try xml.nodes(forXPath: "//gap")
        #expect(gaps.count == 2)
        #expect((gaps[0] as? XMLElement)?.attribute(forName: "duration")?.stringValue == "26/24s")
        #expect((gaps[1] as? XMLElement)?.attribute(forName: "offset")?.stringValue == "26/24s")
        #expect((gaps[0] as? XMLElement)?.attribute(forName: "name")?.stringValue?.contains("A & <B> \"C\"") == true)
        #expect(try xml.nodes(forXPath: "//asset").isEmpty)
    }
    @Test func rejectsEmptyInvalidAndOversizedTimelines() {
        #expect(throws: (any Error).self) { try EditInterchange.events([]) }
        var entries = segments()
        entries.append(TimedEditSegment(id: UUID(), sceneSpineID: "S003", label: "Invalid", start: .nan, duration: 1, clip: nil, estimate: nil))
        #expect(throws: (any Error).self) { try EditInterchange.events(entries) }
        #expect(throws: (any Error).self) { try EditInterchange.events(Array(repeating: segments()[0], count: 1000)) }
    }
}
