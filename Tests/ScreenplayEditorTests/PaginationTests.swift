import AppKit
import Foundation
import PDFKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Printed pagination")
@MainActor
struct PaginationTests {
    private func withDocument(_ elements: [ScreenplayElement], body: (ScreenplayViewModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "PaginationTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Pagination Review"), elements: elements)
        let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Pagination Review", author: ""), screenplayID: script.id), screenplay: script)
        let url = directory.appendingPathComponent("script.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        model.loadOpenScreenplay(at: url)
        try body(model, directory)
    }

    @Test func longParagraphIsSplitWithoutChangingSource() throws {
        let text = (1...700).map { "word\($0)" }.joined(separator: " ")
        let element = ScreenplayElement(type: .action, text: text)
        try withDocument([element]) { model, directory in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.flatMap(\.elements).map(\.text).joined() == text)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(model.document == before)
            #expect(model.elements.count == 1)
            let url = directory.appendingPathComponent("review.pdf")
            model.exportPDF(to: url)
            let pdf = try #require(PDFDocument(url: url))
            #expect(pdf.pageCount == pages.count + 1)
            let extracted = (1..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ")
            let tokens = extracted.components(separatedBy: .whitespacesAndNewlines).filter { $0.hasPrefix("word") }
            #expect(tokens == text.components(separatedBy: " "))
            // Optional artifacts for visual inspection; never writes into a user's screenplay folder.
            if let destination = ProcessInfo.processInfo.environment["SCREENPLAY_PAGINATION_QA_DIR"] {
                let output = URL(fileURLWithPath: destination)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try Data(contentsOf: url).write(to: output.appendingPathComponent("pagination.pdf"))
                for index in 1..<pdf.pageCount {
                    let page = try #require(pdf.page(at: index))
                    let thumbnail = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                    let tiff = try #require(thumbnail.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("page-\(index).png"))
                }
            }
        }
    }

    @Test func unicodeAndUnbrokenWordsSurviveSplitting() throws {
        let text = String(repeating: "👩🏽‍🚀café e\u{301} ", count: 300) + String(repeating: "X", count: 900)
        try withDocument([ScreenplayElement(type: .action, text: text)]) { model, _ in
            #expect(model.printedPages.count > 1)
            #expect(model.printedPages.flatMap(\.elements).map(\.text).joined() == text)
            #expect(model.printedPages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
        }
    }

    @Test func cueStaysWithStartOfLongDialogue() throws {
        let cue = ScreenplayElement(type: .character, text: "MARA")
        let dialogue = ScreenplayElement(type: .dialogue, text: String(repeating: "We have to keep going. ", count: 220).trimmingCharacters(in: .whitespaces))
        try withDocument([cue, dialogue]) { model, _ in
            #expect(model.printedPages.count > 1)
            #expect(model.printedPages.first?.elements.map(\.element.id) == [cue.id, dialogue.id])
            #expect(model.printedPages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
        }
    }

    @Test func explicitPageBreakStartsNextPage() throws {
        let first = ScreenplayElement(type: .action, text: "Before the break.")
        let second = ScreenplayElement(type: .action, text: "After the break.")
        try withDocument([first, ScreenplayElement(type: .pageBreak, text: ""), second]) { model, _ in
            #expect(model.printedPages.count == 2)
            #expect(model.printedPages[0].elements.first?.element.id == first.id)
            #expect(model.printedPages[1].elements.first?.element.id == second.id)
        }
    }
}
