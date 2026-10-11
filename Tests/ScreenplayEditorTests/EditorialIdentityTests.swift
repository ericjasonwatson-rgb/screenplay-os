import Foundation
import Testing
import ScreenplayDomain

@Suite("Derived edit guide identity")
struct EditorialIdentityTests {
    private func fixture() -> ScreenplayOSDocument {
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Identity"), elements: [
            ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY", spineID: "S001")
        ])
        return ScreenplayOSDocument(
            project: Project(metadata: ProjectMetadata(title: "Identity", author: ""), screenplayID: script.id),
            screenplay: script,
            shots: [Shot(sceneSpineID: "S001", shotNumber: 1, label: "Wide"),
                    Shot(sceneSpineID: "S001", shotNumber: 2, label: "Close")]
        )
    }

    private func clips(_ document: ScreenplayOSDocument) -> [EditClip] {
        document.editorialSpine.sequences.flatMap { $0.beats.flatMap(\.editClips) }
    }

    @Test func shotOccurrenceIDsSurviveReorderRenameAndRepeatedReopen() throws {
        var document = fixture()
        let original = clips(document)
        document.shots[0].shotNumber = 3
        document.shots[0].label = "Renamed"
        document.ensureEditorialSpine()
        #expect(clips(document).map(\.id) == [original[1].id, original[0].id])
        #expect(clips(document).last?.label == "Renamed")
        for _ in 0..<3 {
            document = try JSONDecoder().decode(ScreenplayOSDocument.self, from: JSONEncoder().encode(document))
            #expect(clips(document).map(\.id) == [original[1].id, original[0].id])
        }
    }

    @Test func boardOccurrenceIDsSurviveTimingChangesAndReopen() throws {
        var document = fixture()
        document.boardFrames = document.shots.enumerated().map { index, shot in
            BoardFrame(shotID: shot.id, sceneSpineID: "S001", frameNumber: index + 1, label: shot.label)
        }
        document.ensureEditorialSpine()
        let original = clips(document)
        document.boardFrames[0].durationSeconds = 7
        document.boardFrames[0].frameNumber = 3
        document.ensureEditorialSpine()
        let updated = clips(document)
        #expect(updated.map(\.id) == [original[1].id, original[0].id])
        #expect(updated[1].timelineDurationSeconds == 7)
        #expect(updated[1].timelineStartSeconds == 4)
        let reopened = try JSONDecoder().decode(ScreenplayOSDocument.self, from: JSONEncoder().encode(document))
        #expect(clips(reopened) == updated)
    }

    @Test func newSourceGetsNewIdentityWithoutReplacingSurvivor() {
        var document = fixture()
        let original = clips(document)
        document.shots.removeFirst()
        document.shots.append(Shot(sceneSpineID: "S001", shotNumber: 1, label: "Wide"))
        document.ensureEditorialSpine()
        let updated = clips(document)
        #expect(updated[1].id == original[1].id)
        #expect(!original.map(\.id).contains(updated[0].id))
        #expect(Set(updated.map(\.id)).count == updated.count)
    }
}
