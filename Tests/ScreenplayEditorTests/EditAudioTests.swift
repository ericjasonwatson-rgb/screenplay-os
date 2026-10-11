import Foundation
import ScreenplayDomain
@testable import ScreenplayOSApp
import Testing

@Suite("Edit audio lanes")
struct EditAudioTests {
    private func clip(
        id: UUID = UUID(), lane: EditAudioLane = .dialogue,
        start: Double = 10, sourceIn: Double = 2, duration: Double = 5
    ) -> EditAudioClip {
        EditAudioClip(
            id: id, lane: lane, name: "Guide",
            mediaURL: URL(fileURLWithPath: "/tmp/guide.wav"),
            sha256: String(repeating: "a", count: 64), timelineStartSeconds: start,
            sourceInSeconds: sourceIn, durationSeconds: duration
        )
    }

    @Test func syncMathActivatesClipsAtExactSourceOffsets() throws {
        let dialogue = clip()
        let music = clip(lane: .music, start: 8, sourceIn: 0, duration: 20)
        let ledger = try EditAudioLedger(projectID: UUID(), clips: [dialogue, music]).validated()

        #expect(ledger.activeSlices(at: 7.999).isEmpty)
        let atStart = ledger.activeSlices(at: 10)
        #expect(atStart.map(\.clip.lane) == [.dialogue, .music])
        #expect(atStart.first(where: { $0.clip.id == dialogue.id })?.sourceOffsetSeconds == 2)
        #expect(atStart.first(where: { $0.clip.id == dialogue.id })?.remainingSeconds == 5)
        let later = ledger.activeSlices(at: 13.25)
        #expect(later.first(where: { $0.clip.id == dialogue.id })?.sourceOffsetSeconds == 5.25)
        #expect(later.first(where: { $0.clip.id == dialogue.id })?.remainingSeconds == 1.75)
        #expect(!ledger.activeSlices(at: 15).contains { $0.clip.id == dialogue.id })
    }

    @Test func ledgerPersistsProjectBoundAndRejectsUnsafeRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = root.appendingPathComponent("Audio/audio-v1.json")
        let controller = try EditAudioController(projectID: projectID, storageURL: url)
        let value = clip()
        try await controller.add(value)
        #expect(try EditAudioFileStore.read(from: url).clips == [value])
        try await controller.remove(value.id)
        #expect(try EditAudioFileStore.read(from: url).clips.isEmpty)
        #expect(throws: EditAudioError.projectMismatch) {
            _ = try EditAudioController(projectID: UUID(), storageURL: url)
        }
        var bad = value
        bad.mediaURL = URL(string: "https://example.com/a.wav")!
        #expect(throws: EditAudioError.invalidMedia) {
            try EditAudioLedger(projectID: projectID, clips: [bad]).validated()
        }
    }

    @Test func handoffIncludesImportedAudioWithoutClaimingVideoMedia() throws {
        let segment = TimedEditSegment(
            id: UUID(), sceneSpineID: "S001", label: "Scene", start: 0, duration: 20,
            clip: nil, estimate: nil
        )
        let audio = clip(start: 3, sourceIn: 1, duration: 4)
        let xml = try EditInterchange.fcpxml(title: "Test", segments: [segment], audio: [audio])
        #expect(xml.contains("<asset id=\"a1\""))
        #expect(xml.contains(audio.mediaURL.absoluteString))
        #expect(xml.contains("lane=\"-1\""))
        let edl = try EditInterchange.edl(title: "Test", segments: [segment], audio: [audio])
        #expect(edl.contains("SCREENPLAYOS AUDIO LANE: dialogue"))
        #expect(edl.contains(audio.mediaURL.path))
        #expect(edl.contains("OFFLINE PLACEHOLDERS; NO MEDIA INCLUDED"))
    }
}
