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

    @Test func dualDialogueReviewCancellationAndAcceptanceProtectDocuments() throws {
        try fixture { model, directory in
            model.newDocument()
            let before = model.document
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let bytes = try Data(contentsOf: root.appendingPathComponent("Docs/AuditEvidence/fd13-dual-dialogue.fdx"))
            let source = directory.appendingPathComponent("dual.fdx")
            try bytes.write(to: source)
            var reviews = 0
            model.loadFDX(at: source, reviewSequentialDialogue: { result in
                reviews += 1
                #expect(result.document.screenplay.elements.count == 6)
                return false
            })
            #expect(reviews == 1)
            #expect(model.document == before)
            model.loadFDX(at: source, reviewSequentialDialogue: { _ in reviews += 1; return true })
            #expect(reviews == 2)
            #expect(model.elements.map(\.text).suffix(4) == ["ALICE", "AUDIT LEFT WORDS.", "BOB", "AUDIT RIGHT WORDS."])
            let imported = model.elements
            model.save()
            let saved = try #require(model.saveURL)
            #expect(saved != source)
            model.loadOpenScreenplay(at: saved)
            #expect(model.elements == imported)
            #expect(try Data(contentsOf: source) == bytes)
        }
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

    @Test func estimatesDriveTheExistingTimelineAndPlaybackWithoutPersistingClips() throws {
        try fixture { model, directory in
            let script = Screenplay(metadata: ScreenplayMetadata(title: "Mixed timing"), elements: [
                .init(type: .sceneHeading, text: "INT. FIRST - DAY", spineID: "S001"),
                .init(type: .dialogue, text: Array(repeating: "word", count: 180).joined(separator: " ")),
                .init(type: .sceneHeading, text: "EXT. SECOND - DAY", spineID: "S002"),
                .init(type: .sceneHeading, text: "INT. THIRD - DAY", spineID: "S003"),
                .init(type: .dialogue, text: Array(repeating: "word", count: 360).joined(separator: " ")),
                .init(type: .sceneHeading, text: "EXT. EMPTY - DAY", spineID: "S004")])
            let shot = Shot(sceneSpineID: "S002", shotNumber: 1, label: "Board shot")
            let board = BoardFrame(shotID: shot.id, sceneSpineID: "S002", frameNumber: 1, label: "Board")
            let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Mixed timing", author: ""), screenplayID: script.id), screenplay: script, shots: [shot], boardFrames: [board])
            let url = directory.appendingPathComponent("mixed.json")
            try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
            model.loadOpenScreenplay(at: url)
            model.showEditEstimates = true
            let before = model.document
            #expect(model.editTimeline.map(\.duration) == [75, 4, 150])
            #expect(model.editTimeline.map(\.start) == [0, 75, 79])
            #expect(model.editDuration == 229)
            #expect(model.untimedEditSceneCount == 1)
            #expect(model.timedEditClips.first?.start == 75)
            model.seekEdit(to: 76)
            #expect(model.activeBoardFrame?.id == board.id)
            model.seekEdit(to: 80)
            #expect(model.selectedSceneBreakdown?.editSpineID == "S003")
            #expect(model.activeBoardFrame == nil)
            model.toggleEditPlayback()
            model.advanceEditPlayback(by: 300)
            #expect(model.editPlayheadSeconds == 229 && !model.editIsPlaying)
            model.showEditEstimates = false
            #expect(model.editDuration == 4)
            #expect(model.timedEditClips.first?.start == 0)
            #expect(model.editPlayheadSeconds == 0)
            model.showEditEstimates = true
            #expect(model.editDuration == 229)
            #expect(model.document == before)
            model.save()
            model.loadOpenScreenplay(at: try #require(model.saveURL))
            #expect(model.document?.editorialSpine == before?.editorialSpine)
            #expect(model.editDuration == 229)
        }
    }

    @Test func timelineRecalculatesAfterWritingUndoAndEditorialReorder() throws {
        try fixture { model, directory in
            let script = Screenplay(metadata: ScreenplayMetadata(title: "Timing edits"), elements: [
                .init(type: .sceneHeading, text: "INT. FIRST - DAY", spineID: "S001"),
                .init(type: .dialogue, text: Array(repeating: "word", count: 180).joined(separator: " ")),
                .init(type: .sceneHeading, text: "INT. SECOND - DAY", spineID: "S002"),
                .init(type: .dialogue, text: Array(repeating: "word", count: 360).joined(separator: " "))])
            let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Timing edits", author: ""), screenplayID: script.id), screenplay: script)
            let url = directory.appendingPathComponent("timing.json")
            try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
            model.loadOpenScreenplay(at: url)
            model.showEditEstimates = true
            #expect(model.editDuration == 225)
            let dialogue = model.elements[1]
            model.binding(for: dialogue).wrappedValue = dialogue.text + " " + dialogue.text
            #expect(model.editDuration == 300)
            model.undo()
            #expect(model.editDuration == 225)
            model.moveEditorialBeat(model.editorialBeats[1].id, direction: -1)
            #expect(model.editTimeline.map(\.sceneSpineID) == ["S002", "S001"])
            #expect(model.editTimeline.map(\.start) == [0, 150])
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
