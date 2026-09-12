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

    @Test func undoRedoRestoresTextSelectionAndInvalidatesAfterNewEdit() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let element = try #require(model.elements.last)
            model.selectedElementID = element.id
            model.binding(for: element).wrappedValue = "Original"
            model.binding(for: element).wrappedValue = "Changed"
            model.undo()
            #expect(model.elements.last?.text == "Original")
            #expect(model.selectedElementID == element.id)
            #expect(model.canRedo)
            model.redo()
            #expect(model.elements.last?.text == "Changed")
            #expect(model.selectedElementID == element.id)
            model.undo()
            model.binding(for: element).wrappedValue = "New direction"
            #expect(!model.canRedo)
            model.redo()
            #expect(model.elements.last?.text == "New direction")
            model.newDocument()
            #expect(!model.canUndo && !model.canRedo)
        }
    }

    @Test func snapshotsAreIsolatedAndForeignRestoreIsRejected() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.createSnapshot()
            let foreign = try #require(model.snapshots.first)
            model.newDocument()
            model.createSnapshot()
            #expect(model.snapshots.count == 1)
            #expect(model.snapshots.first?.url.deletingLastPathComponent() != foreign.url.deletingLastPathComponent())
            let before = model.document
            model.restoreSnapshot(foreign)
            #expect(model.document == before)
            #expect(model.errorMessage == "This snapshot belongs to a different project.")
        }
    }

    @Test func rapidSnapshotsStayDistinctAndRestoreCanBeUndone() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let element = try #require(model.elements.last)
            model.binding(for: element).wrappedValue = "Before"
            model.createSnapshot()
            let snapshot = try #require(model.snapshots.first)
            model.createSnapshot()
            #expect(model.snapshots.count == 2)
            model.binding(for: element).wrappedValue = "After"
            model.restoreSnapshot(snapshot)
            #expect(model.elements.last?.text == "Before")
            #expect(model.snapshots.count == 3)
            model.undo()
            #expect(model.elements.last?.text == "After")
            model.redo()
            #expect(model.elements.last?.text == "Before")
        }
    }

    @Test func backupFailureAbortsRestoreWithoutChangingScript() throws {
        try withModel { model, directory, _ in
            model.newDocument()
            model.createSnapshot()
            let snapshot = try #require(model.snapshots.first)
            let snapshotData = try Data(contentsOf: snapshot.url)
            let externalURL = directory.appendingPathComponent("external.snapshot.open-screenplay.json")
            try snapshotData.write(to: externalURL)
            let external = ProjectSnapshot(url: externalURL, modifiedAt: Date(), size: snapshotData.count)
            let snapshotDirectory = snapshot.url.deletingLastPathComponent()
            try FileManager.default.removeItem(at: snapshotDirectory)
            try Data("blocked directory".utf8).write(to: snapshotDirectory)
            let element = try #require(model.elements.last)
            model.binding(for: element).wrappedValue = "Keep me"
            let before = model.document
            let saveURL = try #require(model.saveURL)
            let saved = try Data(contentsOf: saveURL)
            model.restoreSnapshot(external)
            #expect(model.document == before)
            #expect(try Data(contentsOf: saveURL) == saved)
            #expect(model.errorMessage?.hasPrefix("Could not restore snapshot:") == true)
        }
    }

    @Test func legacySnapshotsAreFilteredByProjectIdentity() throws {
        try withModel { model, directory, _ in
            model.newDocument()
            model.createSnapshot()
            let snapshot = try #require(model.snapshots.first)
            let firstURL = try #require(model.saveURL)
            let legacy = directory.appendingPathComponent("ScreenplayOS Snapshots/legacy.snapshot.open-screenplay.json")
            try FileManager.default.copyItem(at: snapshot.url, to: legacy)
            model.newDocument()
            model.createSnapshot()
            #expect(!model.snapshots.contains { $0.url.standardizedFileURL == legacy.standardizedFileURL })
            model.loadOpenScreenplay(at: firstURL)
            #expect(model.snapshots.contains { $0.url.standardizedFileURL == legacy.standardizedFileURL })
        }
    }

    @Test func failedRestoreWriteKeepsLiveDocumentAndHistory() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.createSnapshot()
            let snapshot = try #require(model.snapshots.first)
            let element = try #require(model.elements.last)
            model.binding(for: element).wrappedValue = "Keep current version"
            let current = model.document
            let url = try #require(model.saveURL)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            model.restoreSnapshot(snapshot)
            #expect(model.document == current)
            #expect(model.errorMessage?.hasPrefix("Could not save screenplay:") == true)
            try FileManager.default.removeItem(at: url)
            model.undo()
            #expect(model.elements.last?.text == "")
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
