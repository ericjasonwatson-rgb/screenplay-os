import AppKit
import Testing
@testable import ScreenplayOSApp

@Suite("Package window isolation", .serialized) @MainActor
struct PackageWindowTests {
    @Test func startupRecognizesRecentPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = try PackageEditor.newPackage(directory: root)
        let target = root.appendingPathComponent("Startup.screenplay")
        #expect(editor.save(to: target))
        let suite = "PackageWindowTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set([target.path], forKey: "ScreenplayOSRecentDocuments")
        let model = ScreenplayViewModel(autosaveDirectory: root, preferences: preferences)
        #expect(model.packageEditor?.currentURL?.path == target.path)
        #expect(model.document != nil && model.errorMessage == nil)
    }
    @Test func recoveryListExcludesEveryOpenWindowAndRejectsStaleActions() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PackageWindowTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: preferences)
        let owner = PackageWindows(model: model); model.packageWindows = owner
        let store = root.appendingPathComponent("Recovery/Packages")
        let first = try PackageEditor.newPackage(directory: root, recoveryDirectory: store)
        let second = try PackageEditor.newPackage(directory: root, recoveryDirectory: store)
        first.draft = "First window"; first.flushRecovery()
        second.draft = "Second window"; second.flushRecovery()
        let records = PackageRecovery.list(store)
        #expect(records.count == 2)
        owner.present(first, show: false); owner.present(second, show: false)
        defer { for controller in owner.controllers { controller.close() } }
        model.refreshPackageRecoveries()
        #expect(model.packageRecoveries.isEmpty)
        for record in records { model.openPackageRecovery(record) }
        #expect(owner.controllers.count == 2)
        owner.removed(owner.controllers[0])
        #expect(model.packageRecoveries.map(\.id) == [first.recoveryID])
    }
    @Test func separateEditorsKeepHistoryAndDestination() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root)
        let owner = PackageWindows(model: model)
        let first = try PackageEditor.newPackage(directory: root)
        let second = try PackageEditor.newPackage(directory: root)
        owner.present(first, show: false); owner.present(second, show: false)
        defer { for controller in owner.controllers { controller.close() } }
        #expect(owner.controllers.count == 2)
        first.draft = "INT. FIRST - DAY"; #expect(first.apply())
        second.draft = "INT. SECOND - NIGHT"; #expect(second.apply())
        let selection = first.selected
        owner.controllers[0].windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(model.packageEditor === first)
        model.packageEditor?.undo()
        #expect(first.draft == "" && second.draft == "INT. SECOND - NIGHT")
        first.redo(); #expect(first.selected == selection)
        let target = root.appendingPathComponent("First.screenplay")
        #expect(first.save(to: target))
        #expect(!first.dirty && second.dirty && second.currentURL == nil)
        let duplicate = try PackageEditor(source: target)
        owner.present(duplicate, show: false)
        #expect(owner.controllers.count == 2 && owner.existing(at: target)?.editor === first)
        owner.controllers[1].windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(model.packageEditor === second)
        owner.removed(owner.controllers[0])
        #expect(model.packageEditor === second && owner.controllers.count == 1)
    }
}
