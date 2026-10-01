import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Document interchange and independent edit order")
@MainActor struct ImportAndEditTests {
    private func fixture(_ body: (ScreenplayViewModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ImportAndEdit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        try body(ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: defaults), directory)
    }

    @Test func independentOrderSurvivesSaveReopenFormattingAndUndo() throws {
        try fixture { model, directory in
            let script = Screenplay(metadata: ScreenplayMetadata(title: "Order"), elements: [
                ScreenplayElement(type: .sceneHeading, text: "INT. FIRST - DAY", spineID: "S001"),
                ScreenplayElement(type: .sceneHeading, text: "EXT. SECOND - NIGHT", spineID: "S002")])
            let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Order", author: ""), screenplayID: script.id), screenplay: script)
            let url = directory.appendingPathComponent("order.json")
            try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
            model.loadOpenScreenplay(at: url)
            let original = model.elements
            model.moveEditorialBeat(model.editorialBeats[1].id, direction: -1)
            #expect(model.elements == original)
            #expect(model.editorialBeats.map(\.sceneSpineID) == ["S002", "S001"])
            #expect(model.document?.formatVersion == "1.2")
            model.undo()
            #expect(model.editorialBeats.map(\.sceneSpineID) == ["S001", "S002"])
            model.redo()
            model.changeWritingTypography(font: "Helvetica", size: 14)
            #expect(model.document?.formatVersion == "1.2")
            model.save()
            model.loadOpenScreenplay(at: url)
            #expect(model.elements == original)
            #expect(model.editorialBeats.map(\.sceneSpineID) == ["S002", "S001"])
            var reopened = try #require(model.document)
            reopened.screenplay.elements.reverse()
            reopened.ensureEditorialSpine()
            #expect(reopened.editorialSpine.sequences[0].beats.map(\.sceneSpineID) == ["S002", "S001"])
        }
    }

    @Test func playbackCrossesSceneBoundaryAndStopsAtEnd() throws {
        try fixture { model, directory in
            let script = Screenplay(metadata: ScreenplayMetadata(title: "Playback"), elements: [
                ScreenplayElement(type: .sceneHeading, text: "INT. A - DAY", spineID: "S001"),
                ScreenplayElement(type: .sceneHeading, text: "INT. B - DAY", spineID: "S002")])
            let shots = [Shot(sceneSpineID: "S001", shotNumber: 1, label: "A"), Shot(sceneSpineID: "S002", shotNumber: 2, label: "B")]
            let boards = shots.enumerated().map { index, shot in
                BoardFrame(shotID: shot.id, sceneSpineID: shot.sceneSpineID, frameNumber: index + 1, label: shot.label)
            }
            let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Playback", author: ""), screenplayID: script.id), screenplay: script, shots: shots, boardFrames: boards)
            let url = directory.appendingPathComponent("play.json")
            try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
            model.loadOpenScreenplay(at: url)
            #expect(model.editDuration == 8)
            model.seekEdit(to: 4.1)
            #expect(model.selectedSceneBreakdown?.editSpineID == "S002")
            #expect(model.activeBoardFrame?.id == boards[1].id)
            model.toggleEditPlayback()
            model.advanceEditPlayback(by: 10)
            #expect(model.editPlayheadSeconds == 8)
            #expect(!model.editIsPlaying)
            #expect(model.elements == document.screenplay.elements)
        }
    }

    @Test func plainTextPreviewPreservesUnicodeWhitespaceAndBlankLines() throws {
        try fixture { _, directory in
            let source = "INT. ROOM - DAY\r\n\r\n  ALICE\r\nHello é 😀.\r\n"
            let url = directory.appendingPathComponent("text.txt")
            let bytes = Data(source.utf8); try bytes.write(to: url)
            let extracted = try ScreenplayTextImport.extract(url)
            let raw = ScreenplayTextImport.document(extracted, title: "Text", detectStructure: false)
            let detected = ScreenplayTextImport.document(extracted, title: "Text", detectStructure: true)
            #expect(raw.screenplay.elements.map(\.text) == ["INT. ROOM - DAY", "", "  ALICE", "Hello é 😀.", ""])
            #expect(raw.screenplay.elements.map(\.text) == detected.screenplay.elements.map(\.text))
            #expect(detected.screenplay.elements.map(\.type) == [.sceneHeading, .general, .character, .dialogue, .general])
            #expect(try Data(contentsOf: url) == bytes)
            try Data([0xff, 0x00, 0x80]).write(to: url)
            #expect(throws: (any Error).self) { try ScreenplayTextImport.extract(url) }
        }
    }

    @Test func docxAndPDFExtractRealTextWithoutChangingSources() throws {
        try fixture { model, directory in
            let attributed = NSAttributedString(string: "INT. ROOM - DAY\nA visitor arrives.\n")
            let bytes = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            let docx = directory.appendingPathComponent("sample.docx")
            try bytes.write(to: docx)
            let extracted = try ScreenplayTextImport.extract(docx)
            #expect(extracted.text.contains("A visitor arrives."))
            #expect(try Data(contentsOf: docx) == bytes)
            let script = ScreenplayTextImport.document(extracted, title: "PDF Test", detectStructure: true)
            let native = directory.appendingPathComponent("native.json")
            try JSONEncoder.openScreenplayEncoder().encode(script).write(to: native)
            model.loadOpenScreenplay(at: native)
            let pdf = directory.appendingPathComponent("sample.pdf")
            let pdfBytes = try model.makePrintPDF(); try pdfBytes.write(to: pdf)
            let pdfText = try ScreenplayTextImport.extract(pdf)
            #expect(pdfText.text.contains("A visitor arrives."))
            #expect(pdfText.pages.count >= 1)
            #expect(try Data(contentsOf: pdf) == pdfBytes)
        }
    }
}
