import AppKit
import PDFKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package dialogue continuations", .serialized)
@MainActor
struct PackageDialoguePrintTests {
    func fixture(_ rows: [(String, String)]) throws -> PackageTextSession {
        let base = PackageTextSessionTests()
        var files = try base.fixture()
        files["screenplay.json"] = try JSONSerialization.data(withJSONObject: ["id": base.document.uuidString,
            "elements": rows.map { ["id": UUID().uuidString, "type": $0.0, "text": $0.1] }])
        return try PackageTextSession(files: files)
    }
    @Test func multiPageDialogueHasPairedMarkersAndExactAuthoredCoverage() throws {
        let words = (0..<1400).map { String(format: "w%04d", $0) }.joined(separator: " ")
        let session = try fixture([("character", "ELI"), ("parenthetical", "(quietly)"), ("dialogue", words)])
        let original = session.screenplayBytes
        let result = try PackagePrintLayout.make(session)
        let pdf = try #require(PDFDocument(data: result.data))
        #expect(pdf.pageCount >= 3)
        var end = 0
        for range in result.characterRanges { #expect(range.location == end); end = NSMaxRange(range) }
        #expect(end == (result.text as NSString).length)
        for i in 0..<pdf.pageCount {
            let text = pdf.page(at: i)!.string ?? ""
            #expect(text.contains("(MORE)") == (i < pdf.pageCount - 1))
            #expect(text.contains("ELI (CONT’D)") == (i > 0))
        }
        let extracted = pdf.string ?? ""
        for i in 0..<1400 { #expect(extracted.components(separatedBy: String(format: "w%04d", i)).count == 2) }
        #expect(session.screenplayBytes == original && session.originalFiles["screenplay.json"] == original)
        #expect(!result.text.contains("MORE") && !result.text.contains("CONT’D"))
        #expect(!session.canUndo)
        if let path = ProcessInfo.processInfo.environment["DIALOGUE_PRINT_SAMPLE"] {
            try result.data.write(to: URL(fileURLWithPath: path))
            for index in [0, 1, pdf.pageCount - 1] {
                let image = pdf.page(at: index)!.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + ".page-\(index).png"))
            }
        }
    }
    @Test func parentheticalGroupsStayTogetherAndNewSpeakersResetContinuations() throws {
        let rows = (0..<90).flatMap { i in [("character", "SPEAKER\(i)"), ("parenthetical", "(softly)"), ("dialogue", "Spoken sentence. Spoken sentence. Spoken sentence.")] }
        let session = try fixture(rows)
        let projection = PackageWritingProjection(session)
        let result = try PackagePrintLayout.make(session)
        for page in result.characterRanges.dropLast() {
            let last = try #require(projection.entries.last(where: { $0.range.location < NSMaxRange(page) }))
            #expect(last.type == "dialogue")
        }
        let pdf = PDFDocument(data: result.data)!
        for i in 1..<pdf.pageCount {
            let range = result.characterRanges[i]
            let firstIndex = try #require(projection.entries.lastIndex(where: { $0.range.location <= range.location }))
            let pageText = pdf.page(at: i)!.string ?? ""
            if projection.entries[firstIndex].type == "dialogue", range.location > projection.entries[firstIndex].range.location {
                #expect(pageText.contains(projection.entries[firstIndex - 2].text + " (CONT’D)"))
            } else if projection.entries[firstIndex].type == "character" {
                #expect(!pageText.contains("CONT’D"))
            }
        }
    }
    @Test func previewAndSaveNeverPersistMarkers() throws {
        let session = try fixture([("character", "ELI"), ("dialogue", String(repeating: "A spoken sentence. ", count: 400))])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Original.screenplay")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, bytes) in session.originalFiles { try bytes.write(to: source.appendingPathComponent(path)) }
        let editor = try PackageEditor(source: source)
        editor.showPrintPreview()
        #expect(editor.printPreview != nil && !editor.dirty && !editor.canUndo)
        let copy = root.appendingPathComponent("Copy.screenplay")
        #expect(editor.save(to: copy))
        #expect(try Data(contentsOf: copy.appendingPathComponent("screenplay.json")) == session.screenplayBytes)
        #expect(try Data(contentsOf: source.appendingPathComponent("screenplay.json")) == session.screenplayBytes)
    }
    @Test func actionAndUncuedDialogueNeverInventSpeakers() throws {
        let long = String(repeating: "A long speech without a speaker. ", count: 300)
        for rows in [[("dialogue", long)], [("character", "ELI"), ("action", "Leaves."), ("dialogue", long)], [("character", ""), ("dialogue", long)]] {
            let pdf = PDFDocument(data: try PackagePrintLayout.make(fixture(rows)).data)!
            #expect(!(pdf.string ?? "").contains("(MORE)"))
            #expect(!(pdf.string ?? "").contains("CONT’D"))
        }
    }
    @Test func existingSuffixIsNotRepeatedAndShortSpeechHasNoMarkers() throws {
        let short = try PackagePrintLayout.make(fixture([("character", "ELI"), ("parenthetical", "(quietly)"), ("dialogue", "Hello.")]))
        #expect(!PDFDocument(data: short.data)!.string!.contains("MORE"))
        for cue in ["ELI (CONT’D)", "ELI (CONT'D)"] {
            let result = try PackagePrintLayout.make(fixture([("character", cue), ("dialogue", String(repeating: "Spoken words. ", count: 400))]))
            let pdf = PDFDocument(data: result.data)!
            #expect(pdf.pageCount > 1)
            #expect(!(pdf.string ?? "").contains(cue + " (CONT’D)"))
        }
    }
}
