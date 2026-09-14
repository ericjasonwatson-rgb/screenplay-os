import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Package editor workflow")
@MainActor
struct PackageEditorTests {
    @Test func draftSaveUndoAndReopen() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source)
        editor.select(id)
        editor.draft = "Edited in the package editor 👩🏽‍🚀"
        #expect(editor.dirty && editor.pending)
        let target = root.appendingPathComponent("Copy.screenplay")
        #expect(editor.save(to: target))
        #expect(!editor.dirty)
        let reopened = try PackageEditor(source: target)
        #expect(try reopened.session.text(for: id) == "Edited in the package editor 👩🏽‍🚀")
        editor.undo()
        #expect(editor.dirty)
        editor.redo()
        #expect(!editor.dirty)
        editor.draft = "Pending text"
        editor.undo()
        #expect(!editor.pending && !editor.dirty)
    }
    @Test func failedSaveKeepsEditsAndReportsRecovery() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source)
        editor.select(id); editor.draft = "Keep this text"
        let target = root.appendingPathComponent("Occupied.screenplay")
        try Data("competitor".utf8).write(to: target)
        #expect(!editor.save(to: target))
        #expect(editor.dirty)
        #expect(try editor.session.text(for: id) == "Keep this text")
        #expect(editor.message?.contains("Retained output") == true)
        #expect(try Data(contentsOf: target) == Data("competitor".utf8))
    }
    @Test func routingPreservesLegacyDraft() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "PackageEditorTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: preferences)
        model.newDocument()
        let original = model.document
        model.openDocument(at: source)
        #expect(model.packageEditor != nil && model.packagePreview == nil)
        #expect(model.document == original)
        model.packageEditor = nil
        #expect(model.document == original && !model.packageSheetOpen)
    }
}
