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


    @Test func mergedProductionRangesBecomeParagraphLinksAndNavigationSkipsDeletedRefs() throws {
        try withModel { model, directory, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst action.\nSecond action.")
            let first = model.elements[1]
            let second = model.elements[2]
            model.selectElement(id: first.id)
            model.generateShotListForSelectedScene()
            model.generateBoardsForSelectedScene()
            var fixture = try #require(model.document)
            let refs = [ShotSourceRef(screenplayElementID: UUID()),
                        ShotSourceRef(screenplayElementID: second.id, startOffset: 0, endOffset: 6)]
            fixture.shots[0].sourceRefs = refs
            fixture.boardFrames[0].sourceRefs = refs
            let url = directory.appendingPathComponent("ranges.json")
            try JSONEncoder.openScreenplayEncoder().encode(fixture).write(to: url)
            model.loadOpenScreenplay(at: url)
            model.navigateToShotSource(model.shots[0])
            #expect(model.selectedElementID == second.id)
            model.navigateToBoardSource(model.boardFrames[0])
            #expect(model.selectedElementID == second.id)
            #expect(model.mergeElementWithPrevious(second.id))
            #expect(model.shots[0].sourceRefs[1] == ShotSourceRef(screenplayElementID: first.id))
            #expect(model.boardFrames[0].sourceRefs[1] == ShotSourceRef(screenplayElementID: first.id))
            model.undo()
            #expect(model.shots[0].sourceRefs == refs && model.boardFrames[0].sourceRefs == refs)
        }
    }

    @Test func productionSourcesFollowMergeAndRestoreWithUndo() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst action.\nSecond action.")
            let first = model.elements[1]
            let second = model.elements[2]
            model.selectElement(id: first.id)
            model.generateShotListForSelectedScene()
            model.generateBoardsForSelectedScene()
            let shots = model.shots
            let boards = model.boardFrames
            #expect(shots.contains { $0.sourceRefs.contains { $0.screenplayElementID == second.id } })
            model.replaceWritingText(in: NSRange(location: NSMaxRange(model.writingRanges[1]), length: 1), with: "")
            let mergedShots = model.shots
            let mergedBoards = model.boardFrames
            #expect(mergedShots.allSatisfy { $0.sourceRefs.allSatisfy { $0.screenplayElementID != second.id } })
            #expect(mergedBoards.allSatisfy { $0.sourceRefs.allSatisfy { $0.screenplayElementID != second.id } })
            #expect(mergedShots.map(\.id) == shots.map(\.id))
            #expect(mergedBoards.map(\.shotID) == boards.map(\.shotID))
            #expect(mergedBoards.map(\.prompt) == boards.map(\.prompt))
            model.undo()
            #expect(model.shots == shots && model.boardFrames == boards)
            model.redo()
            #expect(model.shots == mergedShots && model.boardFrames == mergedBoards)
            model.loadOpenScreenplay(at: try #require(model.saveURL))
            #expect(model.shots == mergedShots && model.boardFrames == mergedBoards)
        }
    }

    @Test func deletedProductionSourceDoesNotNavigateToMissingParagraph() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst action.\nSecond action.")
            let second = model.elements[2]
            model.selectElement(id: second.id)
            model.generateShotListForSelectedScene()
            model.generateBoardsForSelectedScene()
            let shot = try #require(model.shots.first { $0.sourceRefs.first?.screenplayElementID == second.id })
            let board = try #require(model.boardFrames.first { $0.shotID == shot.id })
            model.selectElement(id: second.id)
            model.deleteSelectedElement()
            let selection = model.selectedElementID
            model.navigateToShotSource(shot)
            #expect(model.selectedElementID == selection)
            #expect(model.errorMessage?.contains("no longer in the screenplay") == true)
            model.navigateToBoardSource(board)
            #expect(model.selectedElementID == selection)
            #expect(model.shots.contains { $0.id == shot.id })
            #expect(model.boardFrames.contains { $0.id == board.id })
        }
    }

    @Test func unchangedReplacementsPreserveRedoAndSavedBytes() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let element = try #require(model.elements.last)
            model.binding(for: element).wrappedValue = "Original"
            model.binding(for: element).wrappedValue = "Later"
            model.undo()
            model.selectElement(id: element.id)
            let before = model.document
            let url = try #require(model.saveURL)
            let saved = try Data(contentsOf: url)
            for query in ["Missing", "Original", ""] {
                model.findQuery = query
                model.replaceText = "Original"
                model.replaceAllMatches()
                model.replaceSelectedMatch()
                #expect(model.canRedo)
                #expect(model.document == before)
                #expect(try Data(contentsOf: url) == saved)
            }
            model.redo()
            #expect(model.elements.last?.text == "Later")
            model.undo()
            #expect(model.elements.last?.text == "Original")
            model.undo()
            #expect(model.elements.last?.text == "")
        }
    }

    @Test func realReplaceAllIsOneUndoStepAndInvalidatesOldRedo() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nCafé café.\nCAFE.")
            let original = model.elements
            let last = try #require(model.elements.last)
            model.binding(for: last).wrappedValue = "Later"
            model.undo()
            #expect(model.canRedo)
            model.findQuery = "cafe"
            model.replaceText = "tea"
            model.replaceAllMatches()
            #expect(model.elements.map(\.text) == ["INT. ROOM - DAY", "tea tea.", "tea."])
            #expect(model.elements.map(\.id) == original.map(\.id))
            #expect(!model.canRedo)
            model.undo()
            #expect(model.elements == original)
            model.redo()
            #expect(model.elements.map(\.text) == ["INT. ROOM - DAY", "tea tea.", "tea."])
        }
    }

    @Test func selectedReplacementChangesOnlySelectedParagraphAndUndoes() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nOne cat.\nAnother cat.")
            let original = model.elements
            model.selectElement(id: original[1].id)
            model.findQuery = "cat"
            model.replaceText = "dog"
            model.replaceSelectedMatch()
            #expect(model.elements[1].text == "One dog.")
            #expect(model.elements[2].text == "Another cat.")
            model.undo()
            #expect(model.elements == original)
            model.redo()
            #expect(model.elements[1].text == "One dog.")
        }
    }

    @Test func mergingParagraphsKeepsNotesAndUndoRestoresOriginalAttachments() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst.\nSecond.")
            let first = model.elements[1]
            let second = model.elements[2]
            for element in [first, second] {
                model.selectElement(id: element.id)
                model.draftScriptNote = "Note on " + element.text
                model.addNoteToSelectedElement()
            }
            let resolvedID = try #require(model.scriptNotes.first?.id)
            model.setScriptNoteStatus(.resolved, for: resolvedID)
            let before = model.scriptNotes
            let separator = NSRange(location: NSMaxRange(model.writingRanges[1]), length: 1)
            model.replaceWritingText(in: separator, with: "")
            #expect(model.elements[1].text == "First.Second.")
            #expect(model.scriptNotes.allSatisfy { $0.screenplayElementID == first.id })
            #expect(model.scriptNotes.map(\.body) == before.map(\.body))
            #expect(model.scriptNotes.map(\.status) == before.map(\.status))
            #expect(model.scriptNotes.map(\.resolvedAt) == before.map(\.resolvedAt))
            #expect(model.scriptNotes.map(\.id) == before.map(\.id))
            model.undo()
            #expect(model.scriptNotes == before)
            #expect(model.elements[2].id == second.id)
            model.redo()
            #expect(model.scriptNotes.allSatisfy { $0.screenplayElementID == first.id })
            let saved = try #require(model.saveURL)
            model.loadOpenScreenplay(at: saved)
            #expect(model.scriptNotes.allSatisfy { $0.screenplayElementID == first.id })
            model.navigateToScriptNote(try #require(model.scriptNotes.first))
            #expect(model.selectedElementID == first.id)
        }
    }

    @Test func replacingMultipleParagraphsPreservesNotesOnTheReplacement() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst.\nMiddle.\nLast.")
            let source = model.elements
            for element in source.dropFirst() {
                model.selectElement(id: element.id)
                model.draftScriptNote = element.text
                model.addNoteToSelectedElement()
            }
            let start = model.writingRanges[1].location
            let end = model.writingRanges[3].location + 2
            model.replaceWritingText(in: NSRange(location: start, length: end - start), with: "Replacement.\nTail ")
            #expect(model.scriptNotes.count == 3)
            #expect(model.scriptNotes.first { $0.body == "Middle." }?.screenplayElementID == source[1].id)
            #expect(model.scriptNotes.first { $0.body == "Last." }?.screenplayElementID == source[3].id)
            #expect(model.scriptNotes.allSatisfy { note in model.elements.contains { $0.id == note.screenplayElementID } })
        }
    }

    @Test func explicitMergeIncludingEmptyParagraphMovesItsNote() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. ROOM - DAY\nFirst.\nSecond.")
            let first = model.elements[1]
            let second = model.elements[2]
            model.selectElement(id: second.id)
            model.draftScriptNote = "Keep this note"
            model.addNoteToSelectedElement()
            model.binding(for: second).wrappedValue = ""
            let before = model.scriptNotes
            #expect(model.mergeElementWithPrevious(second.id))
            #expect(model.elements[1].text == "First.")
            #expect(model.scriptNotes.first?.screenplayElementID == first.id)
            model.undo()
            #expect(model.scriptNotes == before)
            model.binding(for: second).wrappedValue = "Second."
            #expect(model.mergeElementWithPrevious(second.id))
            #expect(model.elements[1].text == "First. Second.")
            #expect(model.scriptNotes.first?.screenplayElementID == first.id)
        }
    }

    @Test func mergingSceneHeadingUpdatesNotesSceneAssociation() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                     with: "INT. FIRST - DAY\nFirst action.\nINT. SECOND - NIGHT\nLater action.")
            let original = model.elements
            model.selectElement(id: original[3].id)
            model.draftScriptNote = "Scene note"
            model.addNoteToSelectedElement()
            let before = model.scriptNotes
            let separator = NSRange(location: NSMaxRange(model.writingRanges[1]), length: 1)
            model.replaceWritingText(in: separator, with: "")
            #expect(model.scriptNotes.first?.sceneSpineID == original[0].spineID)
            #expect(model.scriptNotes.first?.screenplayElementID == original[3].id)
            model.undo()
            #expect(model.scriptNotes == before)
        }
    }

    @Test func outsideEditsSurviveAutosaveAndBlockDocumentReplacementAndClose() throws {
        try withModel { model, directory, _ in
            model.newDocument()
            model.save()
            let url = try #require(model.saveURL)
            var outside = try #require(model.document)
            outside.screenplay.elements[0].text = "OUTSIDE EDIT"
            let externalData = try JSONEncoder.openScreenplayEncoder().encode(outside)
            try externalData.write(to: url, options: .atomic)
            let element = try #require(model.elements.first)
            model.binding(for: element).wrappedValue = "LOCAL EDIT"
            #expect(try Data(contentsOf: url) == externalData)
            #expect(model.saveProblem != nil)
            #expect(model.hasUnsavedChanges)
            #expect(!model.prepareToClose())
            let draft = model.document
            model.newDocument()
            #expect(model.document == draft)
            model.loadOpenScreenplay(at: url)
            #expect(model.document == draft)
            let recovery = try #require(model.recoveryCopies.first)
            let record = try JSONDecoder.openScreenplayDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: recovery.url))
            #expect(record.document.screenplay.elements.first?.text == "LOCAL EDIT")
            let copyURL = directory.appendingPathComponent("saved-copy.json")
            #expect(model.saveSeparateCopy(to: copyURL))
            #expect(!model.hasUnsavedChanges && model.saveProblem == nil)
            #expect(model.prepareToClose())
            #expect(model.recoveryCopies.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: recovery.url.path))
            #expect(try Data(contentsOf: url) == externalData)
            let copy = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: Data(contentsOf: copyURL))
            #expect(copy.screenplay.elements.first?.text == "LOCAL EDIT")
        }
    }

    @Test func deletedOriginalIsNotSilentlyRecreatedAndRecoverySurvivesRestart() throws {
        try withModel { model, directory, preferences in
            model.newDocument()
            model.save()
            let url = try #require(model.saveURL)
            try FileManager.default.removeItem(at: url)
            let element = try #require(model.elements.first)
            model.binding(for: element).wrappedValue = "FIRST LOCAL EDIT"
            model.binding(for: element).wrappedValue = "LATEST LOCAL EDIT"
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(!model.prepareToClose())
            #expect(model.recoveryCopies.count == 1)
            let reopened = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
            let recovery = try #require(reopened.recoveryCopies.first)
            reopened.openRecoveryCopy(recovery)
            #expect(reopened.elements.first?.text == "LATEST LOCAL EDIT")
            #expect(reopened.saveURL == nil && reopened.sourceURL == nil)
            #expect(reopened.hasUnsavedChanges)
            #expect(reopened.saveSeparateCopy(to: directory.appendingPathComponent("recovered.json")))
            #expect(reopened.recoveryCopies.isEmpty)
        }
    }

    @Test func recoveryFailureStillBlocksClose() throws {
        try withModel { model, directory, _ in
            model.newDocument()
            model.save()
            let url = try #require(model.saveURL)
            try FileManager.default.removeItem(at: url)
            try Data("blocked".utf8).write(to: directory.appendingPathComponent("Recovery"))
            let element = try #require(model.elements.first)
            model.binding(for: element).wrappedValue = "KEEP IN MEMORY"
            #expect(!model.prepareToClose())
            #expect(model.saveProblem?.contains("recovery copy also failed") == true)
            #expect(model.elements.first?.text == "KEEP IN MEMORY")
        }
    }

    @Test func overwriteRequiresExactReadVersionButAllowsUnchangedBytes() throws {
        try withModel { _, directory, _ in
            let url = directory.appendingPathComponent("version.json")
            let before = Data("before".utf8)
            let after = Data("after".utf8)
            try before.write(to: url)
            #expect(throws: (any Error).self) {
                try DocumentFileWriter.write(after, to: url, overwriteExisting: true)
            }
            #expect(throws: (any Error).self) {
                try DocumentFileWriter.write(after, to: url, overwriteExisting: true, expectedExistingData: after)
            }
            #expect(try Data(contentsOf: url) == before)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(100)], ofItemAtPath: url.path)
            try DocumentFileWriter.write(after, to: url, overwriteExisting: true, expectedExistingData: before)
            #expect(try Data(contentsOf: url) == after)
        }
    }

    @Test func crossParagraphReplacementAndUndoPreserveIdentityAndSelection() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let initial = try #require(model.elements.first)
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nMara opens the door.\nShe leaves.")
            let before = model.elements
            let ranges = model.writingRanges
            let selection = NSRange(location: ranges[1].location + 5, length: ranges[2].location + 4 - ranges[1].location - 5)
            model.replaceWritingText(in: selection, with: "waits.")
            #expect(model.elements.count == 2)
            #expect(model.elements[1].text == "Mara waits.leaves.")
            #expect(model.elements.first?.id == initial.id)
            #expect(model.elements[1].id == before[1].id)
            model.undo()
            #expect(model.elements == before)
            #expect(model.documentCaret == selection)
            model.redo()
            #expect(model.elements[1].text == "Mara waits.leaves.")
        }
    }

    @Test func multilinePastePreservesUntouchedSuffixIdentity() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nFirst action.\nLast action.")
            let before = model.elements
            let ranges = model.writingRanges
            let range = NSRange(location: ranges[1].location + 6, length: ranges[2].location + 5 - ranges[1].location - 6)
            model.replaceWritingText(in: range, with: "new.\nNext ")
            #expect(model.elements.map(\.text) == ["INT. ROOM - DAY", "First new.", "Next action."])
            #expect(model.elements.map(\.id) == before.map(\.id))
            model.undo()
            #expect(model.elements == before)
        }
    }

    @Test func wholeDocumentCutLeavesEditableElementAndUndoRestoresAll() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nA visitor arrives.\n")
            let before = model.elements
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "")
            #expect(model.elements.count == 1)
            #expect(model.writingText.isEmpty)
            model.undo()
            #expect(model.elements == before)
        }
    }

    @Test func continuousTypingGroupsAndUnicodeCaretIsCorrect() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\n")
            let start = try #require(model.writingRanges.last).location
            let date = Date()
            let first = model.replaceWritingText(in: NSRange(location: start, length: 0), with: "👩🏽‍🚀", groupable: true, now: date)
            let second = model.replaceWritingText(in: first, with: "!", groupable: true, now: date.addingTimeInterval(0.1))
            #expect(second.location == start + ("👩🏽‍🚀!" as NSString).length)
            model.undo()
            #expect(model.elements.last?.text == "")
            model.redo()
            #expect(model.elements.last?.text == "👩🏽‍🚀!")
        }
    }

    @Test func typedCrossParagraphReplacementIsOneUndoGroup() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nMara opens the door.\nShe leaves.")
            let before = model.elements
            let ranges = model.writingRanges
            let selection = NSRange(location: ranges[1].location + 5, length: ranges[2].location + 4 - ranges[1].location - 5)
            let now = Date()
            let caret = model.replaceWritingText(in: selection, with: "w", groupable: true, now: now)
            model.replaceWritingText(in: caret, with: "a", groupable: true, now: now.addingTimeInterval(0.1))
            model.undo()
            #expect(model.elements == before)
            #expect(model.documentCaret == selection)
        }
    }

    @Test func continuousBackspacesAreGroupedAndRestoreOriginalCaret() throws {
        try withModel { model, _, _ in
            model.newDocument()
            model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nMara")
            let end = (model.writingText as NSString).length
            let now = Date()
            model.replaceWritingText(in: NSRange(location: end - 1, length: 1), with: "", groupable: true, selection: NSRange(location: end, length: 0), now: now)
            model.replaceWritingText(in: NSRange(location: end - 2, length: 1), with: "", groupable: true, selection: NSRange(location: end - 1, length: 0), now: now.addingTimeInterval(0.1))
            model.undo()
            #expect(model.elements.last?.text == "Mara")
            #expect(model.documentCaret == NSRange(location: end, length: 0))
        }
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

    @Test func adjacentTypingUndoesAsOneGroupAndRestoresCaret() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let id = try #require(model.elements.last?.id)
            model.selectedElementID = id
            let time = Date(timeIntervalSince1970: 100)
            for (offset, value) in ["a", "ab", "abc"].enumerated() {
                model.editText(id: id, text: value, before: NSRange(location: offset, length: 0),
                    after: NSRange(location: offset + 1, length: 0), groupable: true,
                    now: time.addingTimeInterval(Double(offset) * 0.1))
            }
            model.undo()
            #expect(model.elements.last?.text == "")
            #expect(model.caretRestoration?.range == NSRange(location: 0, length: 0))
            model.redo()
            #expect(model.elements.last?.text == "abc")
            #expect(model.caretRestoration?.range == NSRange(location: 3, length: 0))
        }
    }

    @Test func pauseAndPasteStartSeparateUndoGroups() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let id = try #require(model.elements.last?.id)
            model.selectedElementID = id
            model.editText(id: id, text: "a", before: NSRange(location: 0, length: 0), after: NSRange(location: 1, length: 0), groupable: true, now: Date(timeIntervalSince1970: 100))
            model.editText(id: id, text: "ab", before: NSRange(location: 1, length: 0), after: NSRange(location: 2, length: 0), groupable: true, now: Date(timeIntervalSince1970: 102))
            model.editText(id: id, text: "ab pasted", before: NSRange(location: 2, length: 0), after: NSRange(location: 9, length: 0), groupable: false, now: Date(timeIntervalSince1970: 102.1))
            model.undo()
            #expect(model.elements.last?.text == "ab")
            model.undo()
            #expect(model.elements.last?.text == "a")
        }
    }

    @Test func caretMovementSeparatesTypingEvenWhenReturningToSamePosition() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let id = try #require(model.elements.last?.id)
            model.selectedElementID = id
            let time = Date(timeIntervalSince1970: 100)
            model.editText(id: id, text: "a", before: NSRange(location: 0, length: 0), after: NSRange(location: 1, length: 0), groupable: true, now: time)
            model.rememberCaret(NSRange(location: 0, length: 0), for: id)
            model.rememberCaret(NSRange(location: 1, length: 0), for: id)
            model.editText(id: id, text: "ab", before: NSRange(location: 1, length: 0), after: NSRange(location: 2, length: 0), groupable: true, now: time.addingTimeInterval(0.1))
            model.undo()
            #expect(model.elements.last?.text == "a")
        }
    }

    @Test func typedWordReplacementRestoresOriginalSelectionInOneUndo() throws {
        try withModel { model, _, _ in
            model.newDocument()
            let element = try #require(model.elements.last)
            model.selectedElementID = element.id
            model.binding(for: element).wrappedValue = "Mara opens the door."
            let time = Date(timeIntervalSince1970: 100)
            for (offset, word) in ["g", "ga", "gat", "gate"].enumerated() {
                let before = offset == 0 ? NSRange(location: 15, length: 4) : NSRange(location: 15 + offset, length: 0)
                model.editText(id: element.id, text: "Mara opens the \(word).", before: before,
                    after: NSRange(location: 16 + offset, length: 0), groupable: true,
                    now: time.addingTimeInterval(Double(offset) * 0.1))
            }
            model.undo()
            #expect(model.elements.last?.text == "Mara opens the door.")
            #expect(model.caretRestoration?.range == NSRange(location: 15, length: 4))
            model.redo()
            #expect(model.elements.last?.text == "Mara opens the gate.")
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
            // Restore the expected original version before retrying a normal save.
            try FileManager.default.removeItem(at: originalURL)
            try originalData.write(to: originalURL)
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
