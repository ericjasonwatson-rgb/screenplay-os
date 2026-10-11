import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Duration target planning")
@MainActor
struct DurationTargetTests {
    private func sample(version: String = "1.0") -> ScreenplayOSDocument {
        let elements = (1...3).flatMap { number in
            [ScreenplayElement(type: .sceneHeading, text: "INT. SCÈNE \(number) – DAY", spineID: "S00\(number)"),
             ScreenplayElement(type: .dialogue, text: Array(repeating: "word", count: 60 * number).joined(separator: " "))]
        }
        let script = Screenplay(metadata: .init(title: "Two minutes"), elements: elements)
        return ScreenplayOSDocument(formatVersion: version,
            project: .init(metadata: .init(title: "Two minutes", author: ""), screenplayID: script.id),
            screenplay: script,
            outline: (1...3).map { .init(template: "Test", order: $0, name: "Beat \($0)", purpose: "Plan", linkedSceneSpineIDs: ["S00\($0)"]) })
    }

    private func fixture(_ body: (ScreenplayViewModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "DurationTargets.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: suite) }
        let url = directory.appendingPathComponent("Plan.json")
        try JSONEncoder.screenplayOSEncoder().encode(sample()).write(to: url)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        model.loadScreenplayOSDocument(at: url)
        try body(model, url)
    }

    @Test func parsesWholeSecondsAndClocksWithoutInventingZero() {
        for (text, expected) in [("120", 120), (" 2:00 ", 120), ("0:01", 1), ("1440:00", 86400)] {
            #expect(DurationTarget.parse(text) == expected)
        }
        for text in ["", "0", "-1", "1.5", "NaN", "1:60", "1:2", "1:02:03", "999999999999999999999", "86401", ":30"] {
            #expect(DurationTarget.parse(text) == nil)
        }
        #expect(DurationTarget.clock(120) == "2:00")
    }

    @Test func legacyVersionsRemainUntargetedAndNewTargetsRoundTrip() throws {
        for version in ["1.0", "1.1", "1.2"] {
            let original = sample(version: version)
            let oldData = try JSONEncoder.screenplayOSEncoder().encode(original)
            #expect(!String(decoding: oldData, as: UTF8.self).contains("duration_target"))
            var loaded = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: oldData)
            #expect(loaded.sceneDurationTargets == nil)
            #expect(loaded.outline.allSatisfy { $0.targetDurationSeconds == nil })
            #expect(LegacyRoundTrip.droppedPaths(original: oldData, document: loaded).isEmpty)
            loaded.outline[0].targetDurationSeconds = 40
            loaded.sceneDurationTargets = [loaded.screenplay.elements[0].id.uuidString: 40]
            let data = try JSONEncoder.screenplayOSEncoder().encode(loaded)
            let reopened = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
            #expect(reopened == loaded)
            #expect(reopened.formatVersion == version)
            #expect(reopened.screenplay == original.screenplay)
            #expect(LegacyRoundTrip.droppedPaths(original: data, document: reopened).isEmpty)
        }
    }

    @Test func invalidSavedTargetsAreRejectedRatherThanClamped() throws {
        let data = try JSONEncoder.screenplayOSEncoder().encode(sample())
        for invalid: Any in [0, -1, 86401, 1.5, "one minute"] {
            var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["scene_duration_targets"] = [sample().screenplay.elements[0].id.uuidString: invalid]
            let sceneData = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) { try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: sceneData) }
            json.removeValue(forKey: "scene_duration_targets")
            var beats = try #require(json["outline"] as? [[String: Any]])
            beats[0]["target_duration_seconds"] = invalid
            json["outline"] = beats
            let beatData = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) { try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: beatData) }
        }
    }

    @Test func sceneTargetKeysAreCanonicalAndAmbiguousKeysAreRejected() throws {
        let original = sample()
        let heading = try #require(UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder.screenplayOSEncoder().encode(original)) as? [String: Any])
        json["scene_duration_targets"] = [heading.uuidString.lowercased(): 45]
        let lowercase = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: lowercase)
        #expect(loaded.sceneDurationTargets?[heading.uuidString] == 45)
        // Normalization opens a copy rather than rewriting keys in the external source.
        #expect(!LegacyRoundTrip.droppedPaths(original: lowercase, document: loaded).isEmpty)
        json["scene_duration_targets"] = [heading.uuidString.lowercased(): 45, heading.uuidString: 30]
        let ambiguous = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: ambiguous) }
        var document = original
        let sceneAccepted = document.setSceneDurationTarget(headingID: document.screenplay.elements[1].id, seconds: 40)
        let beatAccepted = document.setOutlineDurationTarget(beatID: UUID(), seconds: 40)
        #expect(!sceneAccepted && !beatAccepted)
        #expect(document == original)
    }

    @Test func threeBeatAndScenePlansSaveReopenWithoutRetimingTheEdit() throws {
        try fixture { model, url in
            let original = try #require(model.document)
            let headings = model.elements.filter { $0.type == .sceneHeading }
            let edit = model.editTimeline.map(\.duration)
            for index in 0..<3 {
                #expect(model.setBeatTarget(original.outline[index].id, seconds: (index + 1) * 20))
                #expect(model.setSceneTarget(headings[index].id, seconds: (index + 1) * 20))
            }
            #expect(model.beatTargetTotal == 120 && model.sceneTargetTotal == 120)
            #expect(model.document?.screenplay == original.screenplay)
            #expect(model.document?.editorialSpine == original.editorialSpine)
            #expect(model.editTimeline.map(\.duration) == edit)
            model.save()
            model.loadScreenplayOSDocument(at: url)
            #expect(model.saveURL == url)
            #expect(model.beatTargetTotal == 120 && model.sceneTargetTotal == 120)
            #expect(model.outlineBeats.map(\.targetDurationSeconds) == [20, 40, 60])
            #expect(headings.map { model.sceneTargetSeconds($0.id) } == [20, 40, 60])
            #expect(!model.setSceneTarget(headings[0].id, seconds: 0))
            #expect(!model.setBeatTarget(original.outline[0].id, seconds: -1))
            #expect(model.sceneTargetTotal == 120)
        }
    }

    @Test func editsChangeEstimatesNotTargetsAndUndoRestoresBoth() throws {
        try fixture { model, _ in
            let heading = model.elements[0], speech = model.elements[1]
            let beat = model.outlineBeats[0]
            #expect(model.setBeatTarget(beat.id, seconds: 20))
            #expect(model.setSceneTarget(heading.id, seconds: 20))
            let estimate = try #require(model.scenePlanningEstimates["S001"])
            model.editText(id: speech.id, text: speech.text + " " + speech.text,
                           before: .init(location: 0, length: 0), after: .init(location: 0, length: 0), groupable: false)
            #expect(model.scenePlanningEstimates["S001"]?.minimumSeconds == estimate.minimumSeconds * 2)
            #expect(model.sceneTargetSeconds(heading.id) == 20)
            #expect(model.outlineBeats[0].targetDurationSeconds == 20)
            model.undo()
            #expect(model.scenePlanningEstimates["S001"] == estimate)
            #expect(model.sceneTargetSeconds(heading.id) == 20)
            model.undo()
            #expect(model.sceneTargetSeconds(heading.id) == nil)
            model.redo()
            #expect(model.sceneTargetSeconds(heading.id) == 20)
            #expect(model.setSceneTarget(heading.id, seconds: nil))
            model.undo()
            #expect(model.sceneTargetSeconds(heading.id) == 20)
            #expect(model.setBeatTarget(beat.id, seconds: nil))
            model.undo()
            #expect(model.outlineBeats[0].targetDurationSeconds == 20)
        }
    }

    @Test func sceneTargetsFollowIdentityThroughReorderDuplicateDeleteAndUndo() throws {
        try fixture { model, _ in
            let heading = model.elements[0]
            #expect(model.setSceneTarget(heading.id, seconds: 40))
            model.selectElement(id: heading.id)
            model.moveSelectedSceneLater()
            #expect(model.sceneTargetSeconds(heading.id) == 40)
            #expect(model.sceneTargetTotal == 40)
            model.selectElement(id: heading.id)
            model.duplicateSelectedScene()
            #expect(model.sceneTargetTotal == 80)
            let duplicate = try #require(model.selectedSceneBreakdown)
            #expect(duplicate.elementID != heading.id)
            #expect(model.sceneTargetSeconds(duplicate.elementID) == 40)
            model.deleteSelectedScene()
            #expect(model.sceneTargetTotal == 40)
            #expect(model.sceneTargetSeconds(duplicate.elementID) == nil)
            model.undo()
            #expect(model.sceneTargetTotal == 80)
            model.undo()
            #expect(model.sceneTargetTotal == 40)
        }
    }

    @Test func estimatesDeduplicateLinksAndExposeMissingScenes() throws {
        let estimates = SceneDurationEstimate.byScene(in: sample().screenplay.elements)
        let summary = PlanningDurationSummary(target: 120, sceneIDs: ["S001", "S002", "S003", "S003"], estimates: estimates)
        #expect(summary.sceneCount == 3 && summary.knownCount == 3)
        #expect(summary.estimateText == "Estimate 2:00–3:00")
        #expect(summary.gapText == "Target is within the estimated range")
        let partial = PlanningDurationSummary(target: 120, sceneIDs: ["S001", "MISSING"], estimates: estimates)
        #expect(partial.estimateText == "Known estimate 0:20–0:30 · 1 untimed")
        #expect(partial.gapText == nil)
        #expect(PlanningDurationSummary(target: 10, sceneIDs: ["S001"], estimates: estimates).gapText == "Estimate exceeds target by at least 0:10")
        #expect(PlanningDurationSummary(target: 40, sceneIDs: ["S001"], estimates: estimates).gapText == "Target exceeds estimate by at least 0:10")
        #expect(PlanningDurationSummary(target: nil, sceneIDs: [], estimates: estimates).estimateText == "Estimate unavailable")
    }

    @Test func cachedEstimatesMatchFreshPassAfterEditsSceneMovesAndDeletion() {
        var elements = sample().screenplay.elements
        var cache = SceneDurationEstimateCache()
        var cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements[1].text += " " + elements[1].text
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements.swapAt(0, 2)
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements[2].type = .action
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements.removeSubrange(2...4)
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements.append(.init(type: .sceneHeading, text: "EMPTY", spineID: "S009"))
        cached = cache.estimates(in: elements)
        #expect(cached == SceneDurationEstimate.byScene(in: elements))
        elements.removeAll()
        cached = cache.estimates(in: elements)
        #expect(cached.isEmpty)
    }

    @Test func unknownFieldsProtectOriginalWhenTargetsAreEdited() throws {
        try fixture { model, url in
            var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var beats = try #require(json["outline"] as? [[String: Any]])
            beats[0]["future_plan"] = false
            json["outline"] = beats
            json["future_setting"] = ["number": "9007199254740993"]
            let original = try JSONSerialization.data(withJSONObject: json)
            try original.write(to: url)
            model.loadScreenplayOSDocument(at: url)
            #expect(model.saveURL == nil)
            #expect(model.setBeatTarget(model.outlineBeats[0].id, seconds: 40))
            #expect(model.setSceneTarget(model.elements[0].id, seconds: 40))
            #expect(try Data(contentsOf: url) == original)
            #expect(model.saveURL != url)
        }
    }
}
