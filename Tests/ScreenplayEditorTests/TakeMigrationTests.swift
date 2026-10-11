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
                  fileURL: URL(string: "Board%20Images/a.png")!, sha256: "aaa", prompt: "Wide one", model: "image-a"),
            .init(id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                  fileURL: URL(string: "Board%20Images/b.png")!, sha256: "bbb", prompt: "Wide two", model: "image-b")
        ]
        board.selectedImageID = board.imageVersions[1].id
        return board
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
