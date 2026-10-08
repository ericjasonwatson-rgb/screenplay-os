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
        #expect(PackageRecovery.list(store).map(\.id) == [record.id])
    }
    @Test func restoredEditorsKeepIndependentCheckpoints() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let original = try PackageEditor(source: source, recoveryDirectory: store)
        original.select(id); original.draft = "original checkpoint"; original.flushRecovery()
        let record = try #require(PackageRecovery.list(store).first)
        let before = try Data(contentsOf: store.appendingPathComponent(record.id.uuidString + ".json"))
        let a = try PackageEditor(recovery: record, directory: store)
        let b = try PackageEditor(recovery: record, directory: store)
        a.draft = "first restored editor"; a.flushRecovery()
        b.draft = "second restored editor"; b.flushRecovery()
        #expect(Set(PackageRecovery.list(store).map(\.id)).count == 3)
        #expect(a.save(to: root.appendingPathComponent("Saved.screenplay")))
        #expect(Set(PackageRecovery.list(store).map(\.id)) == [record.id, b.recoveryID])
        #expect(try Data(contentsOf: store.appendingPathComponent(record.id.uuidString + ".json")) == before)
        #expect(b.dirty && b.draft == "second restored editor")
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
    @Test(.timeLimit(.minutes(1))) func debouncedTypingPersistsAndSeparateSessionsDoNotCollide() async throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Recovery")
        let a = try PackageEditor(source: source, recoveryDirectory: store)
        let b = try PackageEditor(source: source, recoveryDirectory: store)
        a.select(id); b.select(id)
        a.draft = "one"; a.draft = "latest"; b.draft = "other session"
        // Await actual scheduled work, not a wall-clock deadline consumed by
        // unrelated native layout tests on the shared main actor.
        await a.waitForScheduledRecovery()
        await b.waitForScheduledRecovery()
        #expect(PackageRecovery.list(store).count == 2)
        #expect(a.recoveryStatus == "Recovery saved locally")
        #expect(b.recoveryStatus == "Recovery saved locally")
    }
}
