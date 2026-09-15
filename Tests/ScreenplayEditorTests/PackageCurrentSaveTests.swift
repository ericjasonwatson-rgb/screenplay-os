import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Current package saves", .serialized) @MainActor
struct PackageCurrentSaveTests {
    enum Injected: Error { case stop }
    @Test func repeatedSavesRetainPreviousGenerationsAndUndo() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor(source: source)
        let original = try PackageEditedCopy.snapshot(source)
        editor.select(id); editor.draft = "First save 👩🏽‍🚀"
        #expect(editor.saveCurrent(), "\(editor.message ?? "")")
        #expect(!editor.dirty && editor.currentURL?.resolvingSymlinksInPath().path == source.resolvingSymlinksInPath().path)
        let previous = try #require(editor.previousVersionURL)
        #expect(try PackageEditedCopy.snapshot(previous) == original)
        let first = try PackageEditedCopy.snapshot(source)
        editor.draft = "Second save"
        #expect(editor.saveCurrent(), "\(editor.message ?? "")")
        #expect(try PackageEditedCopy.snapshot(editor.previousVersionURL!) == first)
        #expect(try PackageEditedCopy.load(source).text(for: id) == "Second save")
        editor.undo(); #expect(editor.dirty && editor.draft == "First save 👩🏽‍🚀")
        #expect(editor.saveCurrent())
        #expect(try PackageEditedCopy.load(source).text(for: id) == "First save 👩🏽‍🚀")
    }
    @Test func conflictsKeepExternalFileAndAllowSaveAs() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: recovery)
        editor.select(id); editor.draft = "Our edit"
        var outside = try PackageEditedCopy.load(source)
        try outside.replaceText(elementID: id, expectedRevision: outside.revision, expectedText: outside.text(for: id), replacement: "External edit")
        try outside.screenplayBytes.write(to: source.appendingPathComponent("screenplay.json"), options: .atomic)
        #expect(!editor.saveCurrent() && editor.dirty)
        #expect(try PackageEditedCopy.load(source).text(for: id) == "External edit")
        #expect(!PackageRecovery.list(recovery).isEmpty)
        let copy = root.appendingPathComponent("Both preserved.screenplay")
        #expect(editor.save(to: copy) && editor.currentURL == copy)
        editor.draft = "Continue copy"
        #expect(editor.saveCurrent())
        #expect(try PackageEditedCopy.load(copy).text(for: id) == "Continue copy")
        #expect(try PackageEditedCopy.load(source).text(for: id) == "External edit")
    }
    @Test func interruptedSavesKeepCompleteGenerationsAndRecovery() throws {
        for phase in ["staging_created", "write:manifest.json", "write:screenplay.json", "before_publish", "published", "published_readback"] {
            let (root, source, _, id) = try PackageEditedCopyTests().fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("Recovery")
            let editor = try PackageEditor(source: source, recoveryDirectory: store)
            let original = try PackageEditedCopy.snapshot(source)
            editor.select(id); editor.draft = "Retain these edits"
            var staged: URL?
            #expect(!editor.saveCurrent { point, url in
                if point == "staging_created" { staged = url }
                if point == phase { throw Injected.stop }
            })
            #expect(editor.dirty && !PackageRecovery.list(store).isEmpty)
            if ["published", "published_readback"].contains(phase) {
                #expect(try PackageEditedCopy.snapshot(try #require(staged)) == original)
                #expect(try PackageEditedCopy.load(source).text(for: id) == "Retain these edits")
            } else { #expect(try PackageEditedCopy.snapshot(source) == original) }
        }
    }
    @Test func lateConflictAndUnsupportedCompanionsAreNotOverwritten() throws {
        let (root, source, edited, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try PackageEditedCopy.snapshot(source)
        do {
            _ = try PackageCurrentSave.write(edited, base: base, destination: source, replacing: true) { phase, _ in
                if phase == "before_publish" { try Data("external".utf8).write(to: source.appendingPathComponent("notes.json")) }
            }
            Issue.record("Unsupported companion overwritten")
        } catch {}
        #expect(try Data(contentsOf: source.appendingPathComponent("screenplay.json")) == base["screenplay.json"])
        #expect(try Data(contentsOf: source.appendingPathComponent("notes.json")) == Data("external".utf8))
    }
    @Test func competingSaveAndSymlinkAreRejected() throws {
        let (root, source, edited, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try PackageEditedCopy.snapshot(source)
        var rejected = false
        _ = try PackageCurrentSave.write(edited, base: base, destination: source, replacing: true) { phase, _ in
            if phase == "before_publish" {
                do { _ = try PackageCurrentSave.write(edited, base: base, destination: source, replacing: true) }
                catch { rejected = true }
            }
        }
        #expect(rejected)
        let alias = root.appendingPathComponent("Alias.screenplay")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let current = try PackageEditedCopy.snapshot(source)
        do {
            _ = try PackageCurrentSave.write(edited, base: current, destination: alias, replacing: true)
            Issue.record("Symlink accepted")
        } catch {}
        #expect(try PackageEditedCopy.snapshot(source) == current)
    }
    @Test func newPackageFirstSaveAndRecentReopenPreserveLegacy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PackageCurrentSaveTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: preferences)
        model.newDocument(); let legacy = model.document
        model.newPackage()
        let editor = try #require(model.packageEditor)
        #expect(editor.currentURL == nil && editor.dirty && editor.rows.count == 1)
        let id = editor.rows[0].id
        editor.draft = "INT. TEST ROOM - DAY"
        let target = root.appendingPathComponent("New screenplay.screenplay")
        #expect(editor.save(to: target) && !editor.dirty)
        #expect(model.recentDocuments.first?.url.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path)
        model.packageEditor = nil
        model.openDocument(at: model.recentDocuments[0].url)
        #expect(try model.packageEditor?.session.text(for: id) == "INT. TEST ROOM - DAY")
        #expect(model.document == legacy)
    }
}
