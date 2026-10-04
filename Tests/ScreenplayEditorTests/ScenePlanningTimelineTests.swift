import Foundation
import AppKit
import SwiftUI
@testable import ScreenplayOSApp
import Testing
import ScreenplayDomain

@Suite("Initial scene timing spine")
struct ScenePlanningTimelineTests {
    private func estimate(_ words: Int) throws -> SceneDurationEstimate {
        try #require(SceneDurationEstimate(elements: [.init(type: .dialogue, text: Array(repeating: "word", count: words).joined(separator: " "))]))
    }
    @Test func scriptOnlyScenesHaveProportionalDurationsAndCumulativePositions() throws {
        let beats = [EditorialBeat(order: 1, sceneSpineID: "A", title: "First"), EditorialBeat(order: 2, sceneSpineID: "B", title: "Second")]
        let original = beats
        let estimates = ["A": try estimate(180), "B": try estimate(360)]
        let plan = ScenePlanningTimeline(beats: beats, estimates: estimates)
        #expect(plan.entries.map(\.midpointSeconds) == [75, 150])
        #expect(plan.entries.map(\.midpointStart) == [0, 75])
        #expect(plan.minimumSeconds == 180 && plan.maximumSeconds == 270)
        #expect(plan.untimedCount == 0 && plan.hasEstimates)
        let moved = ScenePlanningTimeline(beats: beats.reversed(), estimates: estimates)
        #expect(moved.entries.map(\.sceneSpineID) == ["B", "A"])
        #expect(moved.entries.map(\.midpointStart) == [0, 150])
        #expect(beats == original)
    }
    @Test func unknownScenesDoNotInventDurationsOrLaterStartTimes() throws {
        let beats = [EditorialBeat(order: 1, sceneSpineID: "A", title: "Empty"), EditorialBeat(order: 2, sceneSpineID: "B", title: "Known")]
        let plan = ScenePlanningTimeline(beats: beats, estimates: ["B": try estimate(180)])
        #expect(plan.untimedCount == 1)
        #expect(plan.entries[0].midpointSeconds == nil)
        #expect(plan.entries[1].midpointStart == nil)
        #expect(plan.minimumSeconds == 60 && plan.maximumSeconds == 90)
    }
    @Test func mediaTimingReplacesOnlyItsSceneAndRejectsPlannedOrInvalidClips() throws {
        var first = EditorialBeat(order: 1, sceneSpineID: "A", title: "First")
        let second = EditorialBeat(order: 2, sceneSpineID: "B", title: "Second")
        let estimates = ["A": try estimate(180), "B": try estimate(180)]
        first.editClips = [.init(sceneSpineID: "A", label: "Cut", sourceKind: .productionMedia, timelineStartSeconds: 0, timelineDurationSeconds: 40, status: .assembled)]
        let plan = ScenePlanningTimeline(beats: [first, second], estimates: estimates)
        #expect(plan.entries[0].usesMedia)
        #expect(plan.entries.map(\.midpointSeconds) == [40, 75])
        #expect(plan.entries[1].midpointStart == 40)
        #expect(plan.minimumSeconds == 100 && plan.maximumSeconds == 130)
        for status in [EditClipStatus.omitted, .planned, .placeholder] {
            first.editClips[0].status = status
            #expect(ScenePlanningTimeline.mediaDuration(for: first) == nil)
        }
        first.editClips[0].status = .assembled
        first.editClips[0].sourceKind = .boardFrame
        #expect(ScenePlanningTimeline.mediaDuration(for: first) == nil)
        first.editClips[0].sourceKind = .productionMedia
        for value in [Double.nan, .infinity, -1, 0] {
            first.editClips[0].timelineDurationSeconds = value
            #expect(ScenePlanningTimeline.mediaDuration(for: first) == nil)
        }
    }

    @Test @MainActor func planningLaneRendersWithoutChangingDocument() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "PlanningLane.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: folder); prefs.removePersistentDomain(forName: suite) }
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Timing review"), elements: [
            .init(type: .sceneHeading, text: "INT. FIRST - DAY", spineID: "S001"),
            .init(type: .dialogue, text: Array(repeating: "word", count: 180).joined(separator: " ")),
            .init(type: .sceneHeading, text: "EXT. SECOND - NIGHT", spineID: "S002"),
            .init(type: .dialogue, text: Array(repeating: "word", count: 360).joined(separator: " ")),
            .init(type: .sceneHeading, text: "INT. UNTYPED - DAY", spineID: "S003")])
        let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Timing review", author: ""), screenplayID: script.id), screenplay: script)
        let url = folder.appendingPathComponent("review.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.loadOpenScreenplay(at: url)
        let before = model.document
        model.showEditEstimates = true
        _ = NSApplication.shared
        let host = NSHostingView(rootView: EditTimeLane(model: model, zoom: 1).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        host.layoutSubtreeIfNeeded()
        model.selectEditorialBeat(model.editorialBeats[1])
        try await Task.sleep(nanoseconds: 50_000_000)
        host.layoutSubtreeIfNeeded()
        #expect(model.selectedSceneBreakdown?.editSpineID == "S002")
        #expect(model.document == before)
        #expect(model.editDuration == 225)
        if let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_PLANNING_CAPTURE"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
