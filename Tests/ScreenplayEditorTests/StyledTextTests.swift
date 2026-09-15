import Foundation
import Testing
import ScreenplayDomain

@Suite("Formatting architecture")
struct StyledTextTests {
    @Test func overlappingRunsPreserveExplicitFalseAndExactUnicode() throws {
        let text = "Cafe\u{301} 👩🏽‍🚀 東京"
        let value = try StyledText(text: text, runs: [.init(start: 0, length: 5, style: .init(bold: true)), .init(start: 0, length: 1, style: .init(bold: false, italic: true))])
        #expect(value.resolvedRuns[0].style == .init(italic: true))
        #expect(value.resolvedRuns[1].style == .init(bold: true))
        let decoded = try JSONDecoder().decode(StyledText.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(Array(decoded.text.unicodeScalars) == Array(text.unicodeScalars))
    }
    @Test func platformOffsetsRejectPartialGraphemesAndOverflow() throws {
        let value = try StyledText(text: "A👩🏽‍🚀e\u{301}Z")
        let native = (value.text as NSString).range(of: "👩🏽‍🚀")
        let scalar = try value.scalarRange(fromUTF16: native)
        #expect(scalar == 1..<5)
        #expect(try value.utf16Range(fromScalars: scalar) == native)
        #expect(throws: (any Error).self) { try value.utf16Range(fromScalars: 1..<2) }
        #expect(throws: (any Error).self) { try value.scalarRange(fromUTF16: NSRange(location: Int.max, length: 2)) }
        #expect(throws: (any Error).self) { try StyledText(text: "x", runs: [.init(start: 1, length: Int.max, style: .init(bold: true))]) }
    }
    @Test func replaceSplitJoinAndClearPreserveStyles() throws {
        var value = try StyledText(text: "one two")
        try value.format(4..<7, patch: .init(italic: true, underline: true))
        try value.replace(0..<3, with: "ONE!")
        #expect(value.resolvedRuns == [.init(start: 5, length: 3, style: .init(italic: true, underline: true))])
        let (left, right) = try value.split(at: 5)
        #expect(try left.appending(right) == value)
        try value.clear(5..<8)
        #expect(value.runs.isEmpty && value.text == "ONE! two")
    }
    @Test func transactionsRejectStaleAndFailedEditsAndUndoExactly() throws {
        let original = try StyledText(text: "abc", runs: [.init(start: 0, length: 3, style: .init(bold: true))])
        var history = try StyledTextHistory(original)
        let stale = history.revision
        try history.perform(expectedRevision: history.revision) { try $0.format(1..<2, patch: .init(bold: false, italic: true)) }
        let changed = history.value
        #expect(throws: (any Error).self) { try history.perform(expectedRevision: stale) { try $0.clear(0..<1) } }
        #expect(throws: (any Error).self) { try history.perform(expectedRevision: history.revision) { try $0.clear(0..<99) } }
        #expect(history.value == changed)
        history.undo(); #expect(history.value == original)
        history.redo(); #expect(history.value == changed)
    }
    @Test func typographyAndCanonicalEquivalentTextRemainDistinct() throws {
        let settings = try DocumentTypography(fontFamily: "Courier", fontSize: 12)
        #expect(try JSONDecoder().decode(DocumentTypography.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(throws: (any Error).self) { try DocumentTypography(fontSize: .infinity) }
        #expect(throws: (any Error).self) { try DocumentTypography(fontFamily: " ") }
        let original = try StyledText(text: "é")
        var history = try StyledTextHistory(original)
        try history.perform(expectedRevision: history.revision) { try $0.replace(0..<1, with: "e\u{301}") }
        #expect(history.value.text.unicodeScalars.count == 2)
        history.undo(); #expect(history.value.text.unicodeScalars.count == 1)
    }
    @Test func malformedAndUnknownStylesAreNotSilentlyDropped() throws {
        let invalid = Data(#"{"text":"x","runs":[{"start":0,"length":2,"style":{"bold":true}}]}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StyledText.self, from: invalid) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StyledText.Style.self, from: Data(#"{"color":"red"}"#.utf8)) }
    }
}
