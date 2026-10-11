import Foundation
import ScreenplayDomain
import Testing

@Suite("Board image take migration")
struct TakeMigrationTests {
    private func fixture() -> BoardFrame {
        var board = BoardFrame(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            shotID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            sceneSpineID: "S001", frameNumber: 1, label: "Wide", durationSeconds: 3.5,
            notes: "Director review", sourceRefs: []
        )
        board.imageVersions = [
            .init(id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                  fileURL: URL(string: "Board%20Images/a.png")!, sha256: String(repeating: "a", count: 64),
                  prompt: "Wide one", model: "image-a"),
            .init(id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                  fileURL: URL(string: "Board%20Images/b.png")!, sha256: String(repeating: "b", count: 64),
                  prompt: "Wide two", model: "image-b")
        ]
        board.selectedImageID = board.imageVersions[1].id
        return board
    }

    @Test func takeSidecarPersistsProjectBoundSnapshotAndRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("AI/takes-v1.json")
        let projectID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let takes = try BoardTakeMigration.project([fixture()])
        let ledger = TakeLedger(projectID: projectID, sourceRevision: String(repeating: "c", count: 64), takes: takes)

        try TakeFileStore.write(ledger, to: url)
        #expect(try TakeFileStore.read(from: url) == ledger)
        let permissions = try #require((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)
        #expect(permissions.intValue & 0o077 == 0)

        let link = root.appendingPathComponent("takes-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: TakeValidationError.invalidFile) { try TakeFileStore.read(from: link) }
        #expect(throws: TakeValidationError.invalidFile) { try TakeFileStore.write(ledger, to: link) }
        #expect(try TakeFileStore.read(from: url) == ledger)

        let linkedDirectory = root.appendingPathComponent("linked-directory")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: url.deletingLastPathComponent())
        #expect(throws: TakeValidationError.invalidFile) {
            try TakeFileStore.write(ledger, to: linkedDirectory.appendingPathComponent("escaped.json"))
        }
    }

    @Test func takeLedgerRejectsUnsafeOrAmbiguousRecords() throws {
        let projectID = UUID()
        let revision = String(repeating: "c", count: 64)
        var takes = try BoardTakeMigration.project([fixture()])
        takes[0].mediaURL = URL(string: "https://example.com/asset.png")!
        #expect(throws: TakeValidationError.invalidMedia) {
            try TakeLedger(projectID: projectID, sourceRevision: revision, takes: takes).validated()
        }

        takes = try BoardTakeMigration.project([fixture()])
        takes[0].status = .selected
        #expect(throws: TakeValidationError.multipleSelectedTakes) {
            try TakeLedger(projectID: projectID, sourceRevision: revision, takes: takes).validated()
        }

        takes = try BoardTakeMigration.project([fixture()])
        takes[0].inPointSeconds = 4
        #expect(throws: TakeValidationError.invalidTiming) {
            try TakeLedger(projectID: projectID, sourceRevision: revision, takes: takes).validated()
        }
    }

    @Test func controllerPersistsSelectionBeforePublishingSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("AI/takes-v1.json")
        let projectID = UUID()
        let revision = String(repeating: "d", count: 64)
        let takes = try BoardTakeMigration.project([fixture()])
        let controller = try TakeController(projectID: projectID, storageURL: url)

        try await controller.replaceAll(with: takes, sourceRevision: revision)
        try await controller.select(takes[0].id)
        let saved = try TakeFileStore.read(from: url)
        #expect(saved.takes.first(where: { $0.id == takes[0].id })?.status == .selected)
        #expect(saved.takes.first(where: { $0.id == takes[1].id })?.status == .candidate)
        #expect(await controller.snapshot() == saved)

        #expect(throws: TakeValidationError.projectMismatch) {
            _ = try TakeController(projectID: UUID(), storageURL: url)
        }
    }

    @Test func legacyImagesProjectToTakesAndRoundTripWithoutLoss() throws {
        let board = fixture()
        let takes = try BoardTakeMigration.project([board])
        #expect(takes.map(\.id) == board.imageVersions.map(\.id))
        #expect(takes.map(\.order) == [0, 1])
        #expect(takes.map(\.status) == [.candidate, .selected])
        #expect(takes.allSatisfy { $0.kind == .boardStill && $0.boardFrameID == board.id && $0.shotID == board.shotID })
        #expect(takes.allSatisfy { $0.durationSeconds == 3.5 && $0.outPointSeconds == 3.5 })
        #expect(takes[1].provenance.source == .legacyBoardImage)
        #expect(takes[1].provenance.modelID == "image-b")
        #expect(takes[1].provenance.prompt == "Wide two")
        #expect(try BoardTakeMigration.applyingImageTakes(takes, to: [board]) == [board])

        let data = try JSONEncoder().encode(takes)
        #expect(try JSONDecoder().decode([Take].self, from: data) == takes)
    }

    @Test func legacyNonstandardDigestStillProjectsButCannotEnterStrictLedger() throws {
        var board = fixture()
        board.imageVersions[0].sha256 = "legacy-digest"
        let takes = try BoardTakeMigration.project([board])
        #expect(takes[0].sha256 == "legacy-digest")
        #expect(try BoardTakeMigration.applyingImageTakes(takes, to: [board]) == [board])
        #expect(throws: TakeValidationError.invalidMedia) {
            try TakeLedger(projectID: UUID(), sourceRevision: String(repeating: "a", count: 64), takes: takes).validated()
        }
    }

    @Test func sourceRevisionIsDeterministicAndChangesWithBoardSelection() throws {
        let board = fixture()
        let first = try BoardTakeMigration.sourceRevision([board])
        #expect(first.count == 64)
        #expect(first == (try BoardTakeMigration.sourceRevision([board])))
        var changed = board
        changed.selectedImageID = changed.imageVersions[0].id
        #expect(first != (try BoardTakeMigration.sourceRevision([changed])))
    }

    @Test func corruptLegacySelectionAndDuplicateIDsFailClosed() throws {
        var missing = fixture()
        missing.selectedImageID = UUID()
        #expect(throws: BoardTakeMigrationError.missingSelectedImage) { try BoardTakeMigration.project([missing]) }

        var duplicate = fixture()
        duplicate.imageVersions[1].id = duplicate.imageVersions[0].id
        duplicate.selectedImageID = duplicate.imageVersions[0].id
        #expect(throws: BoardTakeMigrationError.duplicateTakeID) { try BoardTakeMigration.project([duplicate]) }
    }

    @Test func reverseProjectionRejectsVideoWrongShotsAndAmbiguousSelection() throws {
        let board = fixture()
        var takes = try BoardTakeMigration.project([board])
        takes[0].kind = .generatedVideo
        #expect(throws: BoardTakeMigrationError.unsupportedTakeKind) {
            try BoardTakeMigration.applyingImageTakes(takes, to: [board])
        }

        takes = try BoardTakeMigration.project([board])
        takes[0].shotID = UUID()
        #expect(throws: BoardTakeMigrationError.wrongShot) {
            try BoardTakeMigration.applyingImageTakes(takes, to: [board])
        }

        takes = try BoardTakeMigration.project([board])
        takes[0].status = .selected
        #expect(throws: BoardTakeMigrationError.multipleSelectedTakes) {
            try BoardTakeMigration.applyingImageTakes(takes, to: [board])
        }
    }
}
