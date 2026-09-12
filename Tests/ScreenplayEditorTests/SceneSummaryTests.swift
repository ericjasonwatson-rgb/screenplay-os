import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Scene summary consistency")
@MainActor
struct SceneSummaryTests {
    @Test func summariesFollowEditsHistoryContextPagesAndDocumentReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "SceneSummaryTests.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let heading = ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY")
        let action = ScreenplayElement(type: .action, text: "A key lies on the desk.")
        let second = ScreenplayElement(type: .sceneHeading, text: "EXT. ROAD - NIGHT")
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Summary test"), elements: [heading, action, second])
        var document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Summary test", author: ""), screenplayID: script.id), screenplay: script)
        let prop = ProductionEntity(kind: .prop, name: "Key", sourceElementIDs: [action.id])
        let note = ProductionNote(title: "Track the key", body: "", sourceElementIDs: [action.id])
        document.productionContext = ProductionContext(entities: [prop], notes: [note])
        let url = folder.appendingPathComponent("script.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.loadOpenScreenplay(at: url)
        let original = model.sceneBreakdowns
        #expect(original.count == 2)
        #expect(original[0].props == ["Key"] && original[0].notes == ["Track the key"])
        model.binding(for: action).wrappedValue = "A changed action."
        #expect(model.sceneBreakdowns[0].firstAction == "A changed action.")
        model.undo()
        #expect(model.sceneBreakdowns == original)
        model.redo()
        #expect(model.sceneBreakdowns[0].firstAction == "A changed action.")
        model.setProductionEntityStatus(prop.id, status: .ignored)
        #expect(model.sceneBreakdowns[0].props.isEmpty)
        model.setProductionNoteStatus(note.id, status: .ignored)
        #expect(model.sceneBreakdowns[0].notes.isEmpty)
        model.undo()
        #expect(model.sceneBreakdowns[0].notes == ["Track the key"])
        model.setType(.action, for: second.id)
        #expect(model.sceneBreakdowns.count == 1)
        model.undo()
        #expect(model.sceneBreakdowns.count == 2)
        model.lockProductionPages()
        model.binding(for: action).wrappedValue = String(repeating: "A long action passage. ", count: 600)
        for summary in model.sceneBreakdowns {
            let page = model.printedPages.first { $0.elements.contains { $0.element.id == summary.elementID } }
            #expect(summary.pageNumber == page?.label)
        }
        let summaries = model.sceneBreakdowns
        model.selectElement(id: second.id)
        for mode in [WorkflowMode.outline, .directing, .boards, .edit, .writing] {
            model.setWorkflowMode(mode)
            #expect(model.sceneBreakdowns == summaries)
            #expect(model.selectedSceneBreakdown?.elementID == second.id)
        }
        model.unlockProductionPages()
        for summary in model.sceneBreakdowns {
            let page = model.printedPages.first { $0.elements.contains { $0.element.id == summary.elementID } }
            #expect(summary.pageNumber == page?.label)
        }
        model.loadOpenScreenplay(at: url)
        #expect(model.sceneBreakdowns.count == 2)
        model.newDocument()
        #expect(!model.sceneBreakdowns.contains { $0.elementID == heading.id })
    }
}
