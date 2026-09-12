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

    @Test func previewMatchesExportAndDoesNotChangeTheScreenplay() throws {
        let dialogue = (1...800).map { "line\($0)" }.joined(separator: " ")
        let elements = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY"),
                        ScreenplayElement(type: .character, text: "MARA"),
                        ScreenplayElement(type: .dialogue, text: dialogue),
                        ScreenplayElement(type: .pageBreak, text: ""),
                        ScreenplayElement(type: .action, text: "END OF SCENE.")]
        try withDocument(elements) { model, directory in
            model.titlePageBinding(.title).wrappedValue = "Preview Review"
            let before = model.document
            let data = try model.makePrintPDF()
            let snapshot = try PrintPreviewSnapshot(data: data)
            #expect(model.document == before)
            #expect(snapshot.document.pageCount == model.printedPages.count + 1)
            #expect(snapshot.document.page(at: 0)?.string?.contains("Preview Review") == true)
            #expect(snapshot.document.string?.contains("(MORE)") == true)
            #expect(snapshot.document.string?.contains("(CONT'D)") == true)
            let url = directory.appendingPathComponent("export.pdf")
            model.exportPDF(to: url)
            let exported = try #require(PDFDocument(url: url))
            #expect(exported.pageCount == snapshot.document.pageCount)
            for index in 0..<exported.pageCount {
                let previewPage = try #require(snapshot.document.page(at: index))
                let exportedPage = try #require(exported.page(at: index))
                #expect(previewPage.string == exportedPage.string)
                #expect(previewPage.bounds(for: .mediaBox) == exportedPage.bounds(for: .mediaBox))
                let size = NSSize(width: 306, height: 396)
                #expect(previewPage.thumbnail(of: size, for: .mediaBox).tiffRepresentation == exportedPage.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
            }
            // Exporting a reviewed snapshot writes those exact bytes, even after later edits.
            model.binding(for: elements.last!).wrappedValue = "A later change."
            model.writePrintPDF(snapshot.data, to: url)
            #expect(try Data(contentsOf: url) == snapshot.data)
            #expect(snapshot.document.string?.contains("END OF SCENE.") == true)
            #expect(snapshot.document.string?.contains("A later change.") == false)
        }
    }

    @Test func printExportFailureIsReportedWithoutChangingSource() throws {
        try withDocument([ScreenplayElement(type: .action, text: "Original.")]) { model, directory in
            let before = model.document
            model.exportPDF(to: directory.appendingPathComponent("missing/export.pdf"))
            #expect(model.errorMessage?.hasPrefix("Could not export PDF:") == true)
            #expect(model.document == before)
            #expect(throws: (any Error).self) { try PrintPreviewSnapshot(data: Data("invalid".utf8)) }
        }
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
            #expect(model.printedPages.first?.elements.filter { !$0.isContinuation }.map(\.element.id) == [cue.id, dialogue.id])
            #expect(model.printedPages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(model.printedPages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(model.printedPages.last?.elements.last?.isContinuation == false)
            let fragments = model.printedPages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == dialogue.id }
            #expect(fragments.map(\.text).joined() == dialogue.text)
            #expect(model.elements == [cue, dialogue])
            #expect(model.printedPages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
        }
    }

    @Test func adjacentDialogueParagraphsContinueAcrossAutomaticBreaks() throws {
        let dialogue = (1...85).map { ScreenplayElement(type: .dialogue, text: "Sentence \($0).") }
        let source = [ScreenplayElement(type: .character, text: "MARA")] + dialogue
        try withDocument(source) { model, _ in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count >= 3)
            #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation }.map(\.element.id) == source.map(\.id))
            #expect(model.document == before)
        }
    }

    @Test func explicitBreakWithinSpeechAddsMarkersAndPreservesParenthetical() throws {
        let source = [ScreenplayElement(type: .character, text: "MARA (V.O.)"),
                      ScreenplayElement(type: .dialogue, text: "I thought we were done."),
                      ScreenplayElement(type: .pageBreak, text: ""),
                      ScreenplayElement(type: .pageBreak, text: ""),
                      ScreenplayElement(type: .parenthetical, text: "(quietly)"),
                      ScreenplayElement(type: .dialogue, text: "There is one more thing.")]
        try withDocument(source) { model, directory in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count == 2)
            #expect(pages[0].elements.last?.text == "(MORE)")
            #expect(pages[1].elements.map(\.text) == ["MARA (V.O.) (CONT'D)", "(quietly)", "There is one more thing."])
            #expect(model.document == before)
            let data = try model.makePrintPDF()
            let pdf = try #require(PDFDocument(data: data))
            #expect(pdf.pageCount == 3)
            #expect(pdf.page(at: 1)?.string?.contains("(MORE)") == true)
            #expect(pdf.page(at: 2)?.string?.contains("MARA (V.O.) (CONT'D)") == true)
            if let destination = ProcessInfo.processInfo.environment["SCREENPLAY_PAGINATION_QA_DIR"] {
                let output = URL(fileURLWithPath: destination)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try data.write(to: output.appendingPathComponent("continued-dialogue.pdf"))
                for index in 1..<pdf.pageCount {
                    let page = try #require(pdf.page(at: index))
                    let image = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                    let tiff = try #require(image.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("continued-dialogue-\(index).png"))
                }
            }
        }
    }

    @Test func newSpeakerAndSceneEndContinuation() throws {
        for next in [ScreenplayElement(type: .character, text: "ELI"),
                     ScreenplayElement(type: .sceneHeading, text: "EXT. STREET - NIGHT"),
                     ScreenplayElement(type: .action, text: "Mara leaves.")] {
            let source = [ScreenplayElement(type: .character, text: "MARA"),
                          ScreenplayElement(type: .dialogue, text: "Goodbye."),
                          ScreenplayElement(type: .pageBreak, text: ""), next,
                          ScreenplayElement(type: .dialogue, text: "A new thought.")]
            try withDocument(source) { model, _ in
                #expect(model.printedPages.flatMap(\.elements).allSatisfy { !$0.isContinuation })
            }
        }
    }

    @Test func parentheticalAtPageBoundaryKeepsDialogueAndFitsMarkers() throws {
        let dialogue = (1...36).map { ScreenplayElement(type: .dialogue, text: "Sentence \($0).") }
        let source = [ScreenplayElement(type: .character, text: "MARA (CONT'D)")] + dialogue +
            [ScreenplayElement(type: .parenthetical, text: "(after a long pause)"),
             ScreenplayElement(type: .dialogue, text: String(repeating: "Keep going. ", count: 150))]
        try withDocument(source) { model, _ in
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(pages.flatMap(\.elements).allSatisfy { !$0.text.contains("(CONT'D) (CONT'D)") })
            let final = source.last!
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == final.id }.map(\.text).joined() == final.text.trimmingCharacters(in: .whitespaces))
        }
    }

    @Test func longParentheticalsAndForcedBreaksStayWithinPages() throws {
        for count in [1, 30, 100, 250] {
            let parenthetical = ScreenplayElement(type: .parenthetical, text: "(" + String(repeating: "quietly waiting ", count: count) + ")")
            let source = [ScreenplayElement(type: .character, text: "MARA"),
                          ScreenplayElement(type: .dialogue, text: "Before the pause."),
                          ScreenplayElement(type: .pageBreak, text: ""), parenthetical,
                          ScreenplayElement(type: .pageBreak, text: ""),
                          ScreenplayElement(type: .dialogue, text: "After the pause.")]
            try withDocument(source) { model, _ in
                let pages = model.printedPages
                #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
                #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
                #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
                #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == parenthetical.id }.map(\.text).joined() == parenthetical.text)
            }
        }
    }

    @Test func oversizedSpeakerDoesNotPreventPaginationProgress() throws {
        let cue = ScreenplayElement(type: .character, text: String(repeating: "MARA ", count: 400))
        let dialogue = ScreenplayElement(type: .dialogue, text: String(repeating: "Keep going. ", count: 200))
        try withDocument([cue, dialogue]) { model, _ in
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == dialogue.id }.map(\.text).joined() == dialogue.text.trimmingCharacters(in: .whitespacesAndNewlines))
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
