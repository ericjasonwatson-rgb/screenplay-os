import AppKit
import PDFKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Package print pagination", .serialized)
@MainActor
struct PackagePrintTests {
    @Test func pagesCoverAllCharactersAndPreserveSource() throws {
        let fixture = PackageTextSessionTests()
        var files = try fixture.fixture()
        var script = try JSONSerialization.jsonObject(with: files["screenplay.json"]!) as! [String: Any]
        script["elements"] = (0..<180).map { i in ["id": UUID().uuidString, "type": i % 3 == 0 ? "dialogue" : "action", "text": "MARKER\(i) " + String(repeating: "A line of screenplay text. ", count: 12)] }
        files["screenplay.json"] = try JSONSerialization.data(withJSONObject: script)
        let session = try PackageTextSession(files: files)
        let result = try PackagePrintLayout.make(session)
        let pdf = try #require(PDFDocument(data: result.data))
        #expect(pdf.pageCount > 2)
        #expect(pdf.pageCount == result.characterRanges.count)
        var end = 0
        for range in result.characterRanges { #expect(range.location == end); end = NSMaxRange(range) }
        #expect(end == (result.text as NSString).length)
        let extracted = pdf.string ?? ""
        for i in 0..<180 { #expect(extracted.contains("MARKER\(i)")) }
        for i in 0..<pdf.pageCount {
            let page = try #require(pdf.page(at: i))
            #expect(page.bounds(for: .mediaBox).size == NSSize(width: 612, height: 792))
        }
        #expect(session.originalFiles == files && session.screenplayBytes == files["screenplay.json"])
        #expect(!session.canUndo)
        if let path = ProcessInfo.processInfo.environment["PACKAGE_PRINT_SAMPLE"] {
            try result.data.write(to: URL(fileURLWithPath: path))
            for index in [0, pdf.pageCount / 2, pdf.pageCount - 1] {
                let image = pdf.page(at: index)!.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + ".page-\(index).png"))
            }
        }
    }
    @Test func headingsAndCuesDoNotEndPagesAlone() throws {
        let fixture = PackageTextSessionTests()
        var files = try fixture.fixture()
        let rows = (0..<180).map { i in ["id": UUID().uuidString, "type": i % 3 == 0 ? "scene_heading" : (i % 3 == 1 ? "character" : "dialogue"), "text": i % 3 == 2 ? String(repeating: "Spoken words. ", count: 4) : "HEADING OR CUE"] }
        files["screenplay.json"] = try JSONSerialization.data(withJSONObject: ["id": fixture.document.uuidString, "elements": rows])
        let session = try PackageTextSession(files: files)
        let projection = PackageWritingProjection(session)
        let result = try PackagePrintLayout.make(session)
        for page in result.characterRanges.dropLast() {
            let last = try #require(projection.entries.last(where: { $0.range.location < NSMaxRange(page) }))
            #expect(!["character", "scene_heading"].contains(last.type))
        }
    }
    @Test func emptyAndLongSingleParagraphPrint() throws {
        let fixture = PackageTextSessionTests()
        var files = try fixture.fixture()
        for text in ["", String(repeating: "word ", count: 10000)] {
            files["screenplay.json"] = try JSONSerialization.data(withJSONObject: ["id": fixture.document.uuidString, "elements": [["id": fixture.first.uuidString, "type": "action", "text": text]]])
            let result = try PackagePrintLayout.make(PackageTextSession(files: files))
            #expect(PDFDocument(data: result.data)!.pageCount >= 1)
            #expect(result.characterRanges.reduce(0) { $0 + $1.length } == (text as NSString).length)
        }
    }
}
