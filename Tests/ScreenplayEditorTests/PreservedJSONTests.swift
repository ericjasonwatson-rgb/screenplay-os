import Foundation
import Testing
import ScreenplayDomain

@Suite("Preserved JSON editing")
struct PreservedJSONTests {
    private let path: [PreservedJSON.Component] = [.key("elements"), .index(0), .key("text")]

    @Test func editsOnlyTheChosenToken() throws {
        let source = #"{ "elements": [{"id":"stable-id", "text":"old", "future":{"huge":1234567890123456789012345678901234567890,"precise":1.2300000000000000000001e9999}}], "locks": {"raw":"untouched"} }"#
        var document = try PreservedJSON(Data(source.utf8))
        try document.replaceString(at: path, expected: "old", with: "new")
        #expect(document.data == Data(source.replacingOccurrences(of: #""old""#, with: #""new""#).utf8))
    }

    @Test func exactUnicodeAndUndoRedo() throws {
        let source = Data(#"{"elements":[{"text":"e\u0301"}],"other":"same"}"#.utf8)
        var session = try PreservedJSONSession(source)
        let replacement = "👩🏽‍🚀\n\"quoted\"\\\t"
        try session.replaceString(at: path, expected: "e\u{301}", with: replacement)
        let edited = session.document.data
        #expect(try session.document.string(at: path) == replacement)
        session.undo()
        #expect(session.document.data == source)
        session.redo()
        #expect(session.document.data == edited)
        session.undo()
        try session.replaceString(at: path, expected: "e\u{301}", with: "")
        #expect(!session.canRedo)
        #expect(try session.document.string(at: path) == "")
    }

    @Test func staleAndMissingTargetsLeaveHistoryIntact() throws {
        let source = Data(#"{"elements":[{"text":"e\u0301"}]}"#.utf8)
        var session = try PreservedJSONSession(source)
        #expect(throws: PreservedJSON.Failure.self) {
            try session.replaceString(at: path, expected: "é", with: "wrong")
        }
        #expect(throws: PreservedJSON.Failure.self) {
            try session.replaceString(at: [.key("missing")], expected: "", with: "wrong")
        }
        try session.replaceString(at: path, expected: "e\u{301}", with: "e\u{301}")
        #expect(session.document.data == source)
        #expect(!session.canUndo)
    }

    @Test func distinguishesExactKeysAndArrayIndexes() throws {
        var document = try PreservedJSON(Data(#"{"é":"composed","e\u0301":"decomposed","0":"key","array":["index"]}"#.utf8))
        try document.replaceString(at: [.key("e\u{301}")], expected: "decomposed", with: "changed")
        #expect(try document.string(at: [.key("é")]) == "composed")
        #expect(try document.string(at: [.key("e\u{301}")]) == "changed")
        #expect(try document.string(at: [.key("0")]) == "key")
        #expect(try document.string(at: [.key("array"), .index(0)]) == "index")
    }

    @Test func rejectsAmbiguityMalformedSyntaxAndDeepInput() throws {
        let invalid = [#"{"text":"a","te\u0078t":"b"}"#, #"{"nested":{"a":1,"a":2}}"#,
                       "{", "[", "[1,]", "{\"a\":}", "01", "+1", "1.", "1e", "NaN", "true false",
                       #""\uD800""#, #""\x""#, "\"raw\nnewline\"", String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)]
        for source in invalid {
            #expect(throws: (any Error).self) { _ = try PreservedJSON(Data(source.utf8)) }
        }
        #expect(throws: (any Error).self) { _ = try PreservedJSON(Data([34, 255, 34])) }
    }
}
