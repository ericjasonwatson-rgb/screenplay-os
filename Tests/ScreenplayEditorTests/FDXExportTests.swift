import Foundation
import Testing
import ScreenplayDomain
import ScreenplayFDX
@testable import ScreenplayOSApp

@Suite struct FDXExportTests {
    @Test func typesUnicodeStylesAndPageBreaksRoundTrip() throws {
        let types: [ElementType] = [.sceneHeading, .action, .character, .dialogue, .parenthetical, .transition, .general, .shot]
        var elements = types.map { ScreenplayElement(type: $0, text: " e\u{301} 😀 <&>\"'\t\r\nEND ") }
        elements[1].setStyledText(try StyledText(text: elements[1].text, runs: [
            .init(start: 1, length: 5, style: .init(bold: true)),
            .init(start: 3, length: 6, style: .init(italic: true, underline: true)),
            .init(start: 4, length: 1, style: .init(bold: false, strikethrough: true))]))
        elements.insert(.init(type: .pageBreak, text: ""), at: 2)
        elements.append(.init(type: .action, text: ""))
        let result = try FDXExporter.export(elements: elements, titlePage: nil)
        let imported = try FDXImporter().importData(result.data, title: "Test").document.screenplay.elements
        #expect(imported.map(\.type) == elements.map(\.type))
        for (before, after) in zip(elements, imported) {
            #expect(before.text.unicodeScalars.elementsEqual(after.text.unicodeScalars))
            #expect(before.styledText.resolvedRuns == after.styledText.resolvedRuns)
            if before.type != .pageBreak { #expect(after.externalIDs["fdx_paragraph_id"] == before.id.uuidString) }
        }
    }
    @Test func titlePageStaysSeparateAndLimitationsAreExplicit() throws {
        let title = TitlePage(title: "A & B", subtitle: "Subtitle", author: "Writer", contact: "Contact", draftDate: "October 8")
        let result = try FDXExporter.export(elements: [.init(type: .action, text: "Script only")], titlePage: title)
        let imported = try FDXImporter().importData(result.data, title: "File")
        #expect(imported.document.screenplay.elements.map(\.text) == ["Script only"])
        #expect(imported.document.titlePage.title == "A & B")
        for text in ["Subtitle", "Written by", "Writer", "October 8", "Contact"] {
            #expect(imported.document.titlePage.subtitle.contains(text))
        }
        #expect(result.warnings.contains { $0.contains("Dual dialogue") })
        #expect(result.warnings.contains { $0.contains("page locks") })
        #expect(imported.warnings.contains { $0.contains("author/contact") })
    }
    @Test func unsupportedCharactersAndBreaksFailWithoutLoss() throws {
        #expect(throws: (any Error).self) {
            try FDXExporter.export(elements: [.init(type: .action, text: "Bad\u{0}text")], titlePage: nil)
        }
        for elements: [ScreenplayElement] in [
            [.init(type: .pageBreak, text: "")],
            [.init(type: .pageBreak, text: ""), .init(type: .pageBreak, text: ""), .init(type: .action, text: "End")],
            [.init(type: .pageBreak, text: "Authored text"), .init(type: .action, text: "End")]
        ] {
            #expect(throws: (any Error).self) { try FDXExporter.export(elements: elements, titlePage: nil) }
        }
    }
    @Test func defendersFixtureRoundTripsWithoutChangingSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx")
        let bytes = try Data(contentsOf: source)
        let document = try FDXImporter().importData(bytes, title: "Defenders").document
        let result = try FDXExporter.export(elements: document.screenplay.elements, titlePage: document.titlePage)
        let reopened = try FDXImporter().importData(result.data, title: "Export").document
        #expect(reopened.screenplay.elements.map(\.type) == document.screenplay.elements.map(\.type))
        #expect(reopened.screenplay.elements.map(\.styledText) == document.screenplay.elements.map(\.styledText))
        #expect(try Data(contentsOf: source) == bytes)
    }
    @MainActor @Test func legacyExportProtectsImportedSourceAndDocumentState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FDXExportTests." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: prefs)
        let original = try FDXExporter.export(elements: [.init(type: .sceneHeading, text: "INT. AUDIT ROOM - DAY")], titlePage: nil).data
        let source = root.appendingPathComponent("Original.fdx")
        try original.write(to: source)
        model.loadFDX(at: source)
        let before = model.document
        let snapshot = try #require(try model.fdxExportSnapshot())
        #expect(model.document == before)
        #expect(throws: (any Error).self) { try model.writeFDX(snapshot.data, to: source, approvedExistingData: original) }
        #expect(try Data(contentsOf: source) == original)
        let destination = root.appendingPathComponent("Export.fdx")
        try model.writeFDX(snapshot.data, to: destination)
        #expect(try FDXImporter().importFile(at: destination).document.screenplay.elements.first?.type == .sceneHeading)
        #expect(model.document == before)
    }
    @MainActor @Test func packageDraftExportsWithoutMutatingSessionAndWriterRejectsConflicts() throws {
        let (root, source, _, id) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FDXExportTests." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: prefs)
        let editor = try PackageEditor(source: source)
        model.packageEditor = editor
        editor.select(id); editor.draft = "Pending export text"
        let before = editor.session.screenplayBytes
        let snapshot = try #require(try model.fdxExportSnapshot())
        #expect(editor.session.screenplayBytes == before && editor.pending && !editor.session.canUndo)
        let imported = try FDXImporter().importData(snapshot.data, title: "Export")
        #expect(imported.document.screenplay.elements.contains { $0.text == "Pending export text" })
        #expect(throws: (any Error).self) { try model.writeFDX(snapshot.data, to: source) }
        let output = root.appendingPathComponent("Export.fdx")
        try model.writeFDX(snapshot.data, to: output)
        #expect(try Data(contentsOf: output) == snapshot.data)
        #expect(throws: (any Error).self) { try model.writeFDX(snapshot.data, to: output) }
        try Data("External".utf8).write(to: output)
        #expect(throws: (any Error).self) { try model.writeFDX(snapshot.data, to: output, approvedExistingData: snapshot.data) }
        #expect(try Data(contentsOf: output) == Data("External".utf8))
    }
}
