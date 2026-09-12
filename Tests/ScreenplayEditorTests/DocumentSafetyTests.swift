import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Editor writing and document safety")
@MainActor
struct DocumentSafetyTests {
    private func withModel(_ body: (ScreenplayViewModel, URL, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ScreenplayEditorTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        try body(model, directory, preferences)
    }

    @Test func firstWriteRejectsAnOccupiedDestinationAndCleansTemporaryFiles() throws {
        try withModel { _, directory, _ in
            let url = directory.appendingPathComponent("script.json")
            let original = Data("original screenplay".utf8)
            try original.write(to: url)
            #expect(throws: (any Error).self) {
                try DocumentFileWriter.write(Data("replacement".utf8), to: url, overwriteExisting: false)
            }
            #expect(try Data(contentsOf: url) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["script.json"])
        }
    }

    @Test func firstWritePublishesCompleteDataAndCleansTemporaryFiles() throws {
        try withModel { _, directory, _ in
            let url = directory.appendingPathComponent("script.json")
            let data = Data(repeating: 65, count: 100_000)
            try DocumentFileWriter.write(data, to: url, overwriteExisting: false)
            #expect(try Data(contentsOf: url) == data)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["script.json"])
        }
    }

    @Test func newDocumentHasEditableRows() throws {
        try withModel { model, _, _ in
            model.newDocument()
            #expect(model.elements.count == 2)
            #expect(model.screenplayPages.flatMap(\.elements).map(\.element.id) == model.elements.map(\.id))
        }
    }

    @Test func returnPreservesBlankLineAndSelectionAfterReopen() throws {
        try withModel { model, directory, preferences in
            model.newDocument()
            let heading = try #require(model.elements.first)
            model.binding(for: heading).wrappedValue = "INT. ROOM - DAY"
            model.insertElement(after: heading.id)
            let selected = try #require(model.selectedElementID)
            #expect(model.elements.count == 3)
            #expect(model.elements.contains { $0.id == selected && $0.text.isEmpty })
            #expect(model.screenplayPages.flatMap(\.elements).contains { $0.element.id == selected })
            let url = try #require(model.saveURL)
            let reopened = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
            reopened.loadOpenScreenplay(at: url)
            #expect(reopened.elements.map(\.id) == model.elements.map(\.id))
            let blank = try #require(reopened.elements.first { $0.id == selected })
            reopened.binding(for: blank).wrappedValue = "The door opens."
            #expect(reopened.elements.first { $0.id == selected }?.text == "The door opens.")
        }
    }

    @Test func sameTitleDocumentsNeverOverwriteEachOther() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.save()
            let firstURL = try #require(model.saveURL)
            let firstData = try Data(contentsOf: firstURL)
            model.newDocument()
            model.save()
            let secondURL = try #require(model.saveURL)
            #expect(firstURL != secondURL)
            #expect(try Data(contentsOf: firstURL) == firstData)
            let element = try #require(model.elements.first)
            model.binding(for: element).wrappedValue = "EXT. SECOND SCRIPT - NIGHT"
            #expect(model.saveURL == secondURL)
            #expect(try Data(contentsOf: firstURL) == firstData)
        }
    }

    @Test func preexistingFileIsPreservedOnFirstAutosave() throws {
        try withModel { model, directory, _ in
            let existing = directory.appendingPathComponent("Untitled_Screenplay.open-screenplay.json")
            let sentinel = Data("existing screenplay".utf8)
            try sentinel.write(to: existing)
            model.newDocument()
            let heading = try #require(model.elements.first)
            model.binding(for: heading).wrappedValue = "INT. NEW SCRIPT - DAY"
            #expect(model.saveURL != existing)
            #expect(try Data(contentsOf: existing) == sentinel)
        }
    }

    @Test func failedSaveKeepsEditsAndBlocksNewAndOpen() throws {
        try withModel { model, directory, preferences in
            model.newDocument()
            model.save()
            let originalURL = try #require(model.saveURL)
            let originalData = try Data(contentsOf: originalURL)
            let otherURL = directory.appendingPathComponent("other.json")
            try originalData.write(to: otherURL)
            try FileManager.default.removeItem(at: originalURL)
            // A directory at the destination makes the atomic file write fail.
            try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: false)
            let heading = try #require(model.elements.first)
            model.binding(for: heading).wrappedValue = "INT. KEEP THESE EDITS - DAY"
            let edited = model.document
            #expect(model.errorMessage?.hasPrefix("Could not save screenplay:") == true)
            model.newDocument()
            #expect(model.document == edited)
            model.loadOpenScreenplay(at: otherURL)
            #expect(model.document == edited)
            // Once storage works again, the same edits can be saved and reopened.
            try FileManager.default.removeItem(at: originalURL)
            model.save()
            let reopened = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
            reopened.loadOpenScreenplay(at: originalURL)
            #expect(reopened.elements.first?.text == "INT. KEEP THESE EDITS - DAY")
        }
    }

    @Test func blankSplitHalvesRemainEditable() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let heading = try #require(model.elements.first)
            model.binding(for: heading).wrappedValue = "INT. ROOM - DAY"
            model.splitElement(heading.id, at: 0)
            #expect(model.elements.first?.id == heading.id)
            #expect(model.elements.first?.text == "")
            #expect(model.screenplayPages.flatMap(\.elements).count == model.elements.count)
        }
    }
}
