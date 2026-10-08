import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Scene duration planning")
struct SceneDurationTests {
    @Test func rangesExcludeCuesAndFollowSourceEdits() throws {
        var elements = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY", spineID: "S001"),
                        ScreenplayElement(type: .character, text: "A VERY LONG CHARACTER NAME"),
                        ScreenplayElement(type: .dialogue, text: Array(repeating: "word", count: 180).joined(separator: " "))]
        let before = elements
        let estimate = try #require(SceneDurationEstimate.byScene(in: elements)["S001"])
        #expect(estimate.minimumSeconds == 60)
        #expect(estimate.maximumSeconds == 90)
        #expect(elements == before)
        elements[2].text += " " + elements[2].text
        let revised = try #require(SceneDurationEstimate.byScene(in: elements)["S001"])
        #expect(revised.minimumSeconds == 120)
        #expect(revised.maximumSeconds == 180)
        elements.append(ScreenplayElement(type: .sceneHeading, text: "EXT. FIELD - DAY", spineID: "S002"))
        #expect(SceneDurationEstimate.byScene(in: elements)["S002"] == nil)
    }
    @Test func emptyAndActionOnlyScenesStayHonest() throws {
        #expect(SceneDurationEstimate(elements: [.init(type: .action, text: "  \n ")]) == nil)
        let action = try #require(SceneDurationEstimate(elements: [.init(type: .action, text: "She walks away.")]))
        #expect(action.minimumSeconds == 5)
        #expect(action.maximumSeconds == 10)
    }
    @Test func actionPlanningPageCentersOnOneMinuteAndCombinesWithDialogue() throws {
        let line = Array(repeating: "word", count: 12).joined(separator: " ")
        let text = Array(repeating: line, count: 53).joined(separator: "\n")
        let action = ScreenplayElement(type: .action, text: text)
        let page = try #require(SceneDurationEstimate(elements: [action]))
        #expect(page.minimumSeconds == 45 && page.maximumSeconds == 75)
        let speech = ScreenplayElement(type: .dialogue, text: Array(repeating: "word", count: 180).joined(separator: " "))
        let mixed = try #require(SceneDurationEstimate(elements: [action, speech]))
        #expect(mixed.minimumSeconds == 105 && mixed.maximumSeconds == 165)
        let continuous = try #require(SceneDurationEstimate(elements: [.init(type: .action, text: Array(repeating: line, count: 53).joined(separator: " "))]))
        #expect(continuous == page)
        let longToken = try #require(SceneDurationEstimate(elements: [.init(type: .action, text: String(repeating: "x", count: 3180))]))
        #expect(longToken == page)
    }
    @Test func placeholdersOmissionsAndUnconformedMediaNeverSupplyPlaybackTime() {
        var beat = EditorialBeat(order: 1, sceneSpineID: "S001", title: "Test")
        beat.editClips = [
            .init(sceneSpineID: "S001", label: "Shot", sourceKind: .shotPlaceholder, timelineStartSeconds: 0, timelineDurationSeconds: 4),
            .init(sceneSpineID: "S001", label: "Omitted board", sourceKind: .boardFrame, timelineStartSeconds: 4, timelineDurationSeconds: 5, status: .omitted),
            .init(sceneSpineID: "S001", label: "Planned media", sourceKind: .productionMedia, timelineStartSeconds: 9, timelineDurationSeconds: 9),
            .init(sceneSpineID: "S001", label: "Board", sourceKind: .boardFrame, timelineStartSeconds: 18, timelineDurationSeconds: 3)]
        #expect(ScenePlanningTimeline.playableClips(in: beat).map(\.label) == ["Board"])
        let display = SceneTimingDisplay(beat: beat, scriptEstimate: nil, showEstimate: false)
        #expect(display.timing == "Boards: 3.0s · 1 clip · omitted clips excluded")
        beat.editClips = [beat.editClips[3]]
        for duration in [Double.nan, .infinity, 0, -1] {
            beat.editClips[0].timelineDurationSeconds = duration
            #expect(ScenePlanningTimeline.playableClips(in: beat).isEmpty)
        }
        beat.editClips[0].timelineDurationSeconds = 3
        beat.editClips[0].status = .placeholder
        #expect(ScenePlanningTimeline.playableClips(in: beat).isEmpty)
    }
    @Test func toggleAndTimingPrecedenceDoNotChangeClips() throws {
        let estimate = try #require(SceneDurationEstimate(elements: [.init(type: .dialogue, text: "Hello there.")]))
        var beat = EditorialBeat(order: 1, sceneSpineID: "S001", title: "Scene")
        #expect(SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: false).estimate == nil)
        #expect(SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: true).estimate == "Est. 0:05–0:10")
        beat.editClips = [.init(sceneSpineID: "S001", label: "Board", sourceKind: .boardFrame, timelineStartSeconds: 0, timelineDurationSeconds: 4)]
        let original = beat
        let board = SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: true)
        #expect(board.timing == "Boards: 4.0s · 1 clip")
        #expect(board.estimate != nil)
        #expect(beat == original)
        beat.editClips[0].timelineDurationSeconds = 7
        #expect(SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: true).timing.contains("7.0s"))
        beat.editClips[0].sourceKind = .productionMedia
        beat.editClips[0].status = .assembled
        let media = SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: true)
        #expect(media.timing.hasPrefix("Media edit:"))
        #expect(media.estimate == nil)
        beat.editClips[0].status = .omitted
        let omitted = SceneTimingDisplay(beat: beat, scriptEstimate: estimate, showEstimate: true)
        #expect(omitted.timing == "No timed clips")
        #expect(omitted.estimate != nil)
    }
}
