import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Package recovery")
@MainActor
struct PackageRecoveryTests {
    @Test func pendingTextRestoresWithoutOriginalAndSaves() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: store)
        editor.select(id); editor.draft = "Unapplied e\u{301} 👩🏽‍🚀"
        editor.flushRecovery()
        #expect(editor.pending)
        let record = try #require(PackageRecovery.list(store).first)
        // Simulate a later process with no original available; restore from disk alone.
        try FileManager.default.removeItem(at: source)
        let restored = try PackageEditor(recovery: PackageRecovery.read(store.appendingPathComponent(record.id.uuidString + ".json")), directory: store)
        #expect(restored.draft == "Unapplied e\u{301} 👩🏽‍🚀" && restored.dirty)
        let output = root.appendingPathComponent("Recovered Copy.screenplay")
        #expect(restored.save(to: output))
        #expect(try PackageEditedCopy.load(output).text(for: id) == "Unapplied e\u{301} 👩🏽‍🚀")
        #expect(PackageRecovery.list(store).isEmpty)
    }
    @Test func interruptedReplacementKeepsPreviousRecord() throws {
        let (root, _, session, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Recovery")
        let record = PackageRecovery.Record(version: 1, id: UUID(), title: "Test", originalSource: root, savedAt: Date(), selected: nil, files: session.originalFiles)
        try PackageRecovery.write(record, directory: directory)
        let path = directory.appendingPathComponent(record.id.uuidString + ".json")
        let before = try Data(contentsOf: path)
        #expect(throws: (any Error).self) {
            try PackageRecovery.write(record, directory: directory) { throw CocoaError(.fileWriteOutOfSpace) }
        }
        #expect(try Data(contentsOf: path) == before)
        #expect(PackageRecovery.list(directory).count == 1)
    }
    @Test func failureIsVisibleAndUndoClearsRecovery() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let editor = try PackageEditor(source: source, recoveryDirectory: store)
        editor.select(id); editor.draft = "pending"; editor.flushRecovery()
        #expect(PackageRecovery.list(store).count == 1)
        editor.undo(); editor.flushRecovery()
        #expect(PackageRecovery.list(store).isEmpty)
        let occupied = root.appendingPathComponent("Occupied")
        try Data().write(to: occupied)
        let failing = try PackageEditor(source: source, recoveryDirectory: occupied)
        failing.draft = "Keep this text"; failing.flushRecovery()
        #expect(failing.dirty && failing.recoveryStatus?.contains("failed") == true)
    }
    @Test func debouncedTypingPersistsAndSeparateSessionsDoNotCollide() async throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let a = try PackageEditor(source: source, recoveryDirectory: store)
        let b = try PackageEditor(source: source, recoveryDirectory: store)
        a.select(id); b.select(id)
        a.draft = "one"; a.draft = "latest"; b.draft = "other session"
        // Other native layout tests can occupy the main actor before the debounce
        // task starts. Await the observable result, with a bounded failure deadline.
        let deadline = ContinuousClock.now + .seconds(5)
        while PackageRecovery.list(store).count != 2 && ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(PackageRecovery.list(store).count == 2)
        #expect(a.recoveryStatus == "Recovery saved locally")
        #expect(b.recoveryStatus == "Recovery saved locally")
    }
}
