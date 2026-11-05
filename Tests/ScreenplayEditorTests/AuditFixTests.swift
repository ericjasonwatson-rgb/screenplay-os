import Foundation
import Testing
import AppKit
import ScreenplayDomain
import ScreenplayFDX
@testable import ScreenplayOSApp

/// Regressions for the 0.1.3 (26) audit: legacy round-trip safety, side-field Undo,
/// board-image relocation, provider parsing, and named FDX import losses.
@Suite("Build 26 audit fixes")
@MainActor
struct AuditFixTests {
    @Test func scriptCommandsRejectSideFieldsAndAttachedSheets() throws {
        _ = NSApplication.shared
        // The test runner has no window-server sheet presentation. Supply the
        // same attachedSheet state while exercising real AppKit first responders.
        final class SheetWindow: NSWindow {
            var testSheet: NSWindow?
            override var attachedSheet: NSWindow? { testSheet }
        }
        let window = SheetWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let script = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = script
        defer { window.close() }
        window.makeFirstResponder(script)
        #expect(WritingTextView.acceptsScriptCommands(in: window))
        let field = NSTextView(frame: .zero)
        script.addSubview(field)
        window.makeFirstResponder(field)
        #expect(!WritingTextView.acceptsScriptCommands(in: window))
        window.makeFirstResponder(script)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.testSheet = sheet
        #expect(!WritingTextView.acceptsScriptCommands(in: window))
        #expect(!WritingTextView.acceptsScriptCommands(in: sheet))
        window.testSheet = nil
        #expect(WritingTextView.acceptsScriptCommands(in: window))
        sheet.close()
        #expect(!WritingTextView.acceptsScriptCommands(in: nil))
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Synthetic.open-screenplay.json")
    }

    private func withModel(_ body: (ScreenplayViewModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "AuditFixTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        try body(model, directory)
    }

    /// The fixture with one unknown top-level object, one unknown element field,
    /// and one unknown null value.
    private func fixtureWithUnknownContent() throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        json["future_feature"] = ["kept": true]
        json["empty_note"] = NSNull()
        var screenplay = try #require(json["screenplay"] as? [String: Any])
        var elements = try #require(screenplay["elements"] as? [[String: Any]])
        elements[0]["custom_tag"] = "Keep me"
        screenplay["elements"] = elements
        json["screenplay"] = screenplay
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func currentProjectFormatReportsNoLoss() throws {
        let data = try Data(contentsOf: fixtureURL)
        let document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
        #expect(LegacyRoundTrip.droppedPaths(original: data, document: document).isEmpty)
    }

    @Test func unknownContentIncludingNullIsNamed() throws {
        let data = try fixtureWithUnknownContent()
        let document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
        let dropped = LegacyRoundTrip.droppedPaths(original: data, document: document)
        #expect(dropped.contains("future_feature"))
        #expect(dropped.contains("screenplay.elements[0].custom_tag"))
        #expect(dropped.contains("empty_note"))
    }

    @Test func unknownEmptyValuesProtectOriginalEvenAfterEditing() throws {
        for value: Any in [false, "", [Any](), [String: Any](), NSNull()] {
            try withModel { model, directory in
                var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
                json["future_setting"] = value
                let data = try JSONSerialization.data(withJSONObject: json)
                let url = directory.appendingPathComponent("Future.json")
                try data.write(to: url)
                model.loadScreenplayOSDocument(at: url)
                #expect(model.document != nil)
                #expect(model.saveURL == nil)
                let element = try #require(model.elements.first)
                model.editText(id: element.id, text: element.text + " edited",
                               before: .init(location: 0, length: 0),
                               after: .init(location: 0, length: 0), groupable: false)
                #expect(try Data(contentsOf: url) == data)
                #expect(model.saveURL?.standardizedFileURL != url.standardizedFileURL)
            }
        }
    }

    @Test func changedArrayLengthCannotHideUnknownFields() throws {
        let data = try fixtureWithUnknownContent()
        var document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
        document.screenplay.elements.removeLast()
        #expect(LegacyRoundTrip.droppedPaths(original: data, document: document).contains("screenplay.elements"))
        document.screenplay.elements.append(.init(type: .action, text: "Added"))
        document.screenplay.elements.append(.init(type: .action, text: "Another"))
        #expect(LegacyRoundTrip.droppedPaths(original: data, document: document).contains("screenplay.elements"))
    }

    @Test func migrationExceptionIsScopedAndMalformedComparisonFailsClosed() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        json["ai_settings"] = ["post_enabled": true]
        json["post_enabled"] = "Unrelated future root field"
        let data = try JSONSerialization.data(withJSONObject: json)
        let document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
        let dropped = LegacyRoundTrip.droppedPaths(original: data, document: document)
        #expect(document.aiSettings.editEnabled)
        #expect(!dropped.contains("ai_settings.post_enabled"))
        #expect(dropped.contains("post_enabled"))
        #expect(!LegacyRoundTrip.droppedPaths(original: Data("invalid".utf8), document: document).isEmpty)
    }

    @Test func projectWithUnknownContentOpensAsCopyAndOriginalIsNeverRewritten() throws {
        try withModel { model, directory in
            let data = try fixtureWithUnknownContent()
            let url = directory.appendingPathComponent("Future.open-screenplay.json")
            try data.write(to: url)
            model.loadScreenplayOSDocument(at: url)
            #expect(model.document != nil)
            #expect(model.saveURL == nil)
            #expect(model.errorMessage?.contains("opened as a copy") == true)
            let element = try #require(model.elements.first)
            let edited = element.text + " edited"
            let end = NSRange(location: (edited as NSString).length, length: 0)
            model.editText(id: element.id, text: edited, before: end, after: end, groupable: false)
            #expect(try Data(contentsOf: url) == data)
            #expect(model.saveURL?.standardizedFileURL != url.standardizedFileURL)
        }
    }

    @Test func sideFieldTypingIsOneUndoStepAndKeepsScriptHistory() throws {
        try withModel { model, _ in
            model.newDocument()
            let element = try #require(model.elements.first)
            let heading = "INT. HOUSE - DAY"
            let end = NSRange(location: (heading as NSString).length, length: 0)
            model.editText(id: element.id, text: heading, before: NSRange(location: 0, length: 0), after: end, groupable: false)
            let scriptText = model.elements.first?.text
            let original = model.titlePage.author
            let author = model.titlePageBinding(.author)
            for count in 1...150 { author.wrappedValue = String(repeating: "a", count: count) }
            model.undo()
            #expect(model.titlePage.author == original)
            #expect(model.elements.first?.text == scriptText)
            model.undo()
            #expect(model.elements.first?.text != scriptText)
        }
    }

    @Test func saveCopiesOutsideBoardImagesBesideTheProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let old = root.appendingPathComponent("Old/Project.open-screenplay.json")
        let new = root.appendingPathComponent("New/Project.open-screenplay.json")
        try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = try BoardImageStorage.store(png, beside: old)
        let screenplay = Screenplay(metadata: .init(title: "Moved"), elements: [])
        var doc = ScreenplayOSDocument(project: Project(metadata: .init(title: "Moved", author: ""), screenplayID: screenplay.id), screenplay: screenplay)
        var board = BoardFrame(shotID: UUID(), sceneSpineID: "S001", frameNumber: 1, label: "Test")
        let version = BoardImageVersion(fileURL: image, sha256: BoardImageStorage.digest(png), prompt: "Approved", model: "test")
        let missing = BoardImageVersion(fileURL: root.appendingPathComponent("Gone/x.png"), sha256: BoardImageStorage.digest(png), prompt: "Gone", model: "test")
        board.imageVersions = [version, missing]; board.selectedImageID = version.id; doc.boardFrames = [board]

        let gathered = BoardImageStorage.gathered(doc, beside: new)
        let moved = gathered.document.boardFrames[0].imageVersions[0].fileURL
        #expect(gathered.unavailable == 1)
        #expect(moved.deletingLastPathComponent().lastPathComponent == BoardImageStorage.folder)
        #expect(moved.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == new.deletingLastPathComponent().standardizedFileURL)
        try FileManager.default.removeItem(at: old.deletingLastPathComponent())
        #expect(try BoardImageStorage.read(gathered.document.boardFrames[0].imageVersions[0]) == png)
        let relative = BoardImageStorage.portableReferences(gathered.document, at: new)
        #expect(relative.boardFrames[0].imageVersions[0].fileURL.scheme == nil)
    }

    @Test func sceneHeadingNeverEndsAPageBeforeACharacterCue() throws {
        // Sweep the filler so the heading lands at every position near the page foot.
        for filler in 30...60 {
            let heading = ScreenplayElement(type: .sceneHeading, text: "INT. KITCHEN - NIGHT")
            let cue = ScreenplayElement(type: .character, text: "MARA")
            let speech = ScreenplayElement(type: .dialogue, text: "We stay.")
            let elements = (1...filler).map { ScreenplayElement(type: .action, text: "Line \($0).") } + [heading, cue, speech]
            try withModel { model, directory in
                let script = Screenplay(metadata: ScreenplayMetadata(title: "Keep"), elements: elements)
                let document = ScreenplayOSDocument(project: Project(metadata: ProjectMetadata(title: "Keep", author: ""), screenplayID: script.id), screenplay: script)
                let url = directory.appendingPathComponent("keep.json")
                try JSONEncoder.screenplayOSEncoder().encode(document).write(to: url)
                model.loadScreenplayOSDocument(at: url)
                let pages = model.printedPages
                let headingPage = pages.firstIndex { $0.elements.contains { !$0.isContinuation && $0.element.id == heading.id } }
                let cuePage = pages.firstIndex { $0.elements.contains { !$0.isContinuation && $0.element.id == cue.id } }
                #expect(headingPage != nil && headingPage == cuePage, "filler \(filler)")
            }
        }
    }

    @Test func cueExtensionsAreKeptWhenRenamingACharacter() {
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN").name == "JOHN")
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN").suffix == "")
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN (V.O.)").name == "JOHN")
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN (V.O.)").suffix == " (V.O.)")
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN (CONT'D) ^").name == "JOHN")
        #expect(ScreenplayViewModel.cueNameAndSuffix("JOHN (CONT'D) ^").suffix == " (CONT'D) ^")
    }

    @Test func finderMetadataInsideAPackageDoesNotBlockOpeningOrSaving() throws {
        let (root, source, _, _) = try PackageEditedCopyTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0, 1, 2]).write(to: source.appendingPathComponent(".DS_Store"))
        try Data([3]).write(to: source.appendingPathComponent("._screenplay.json"))
        _ = try PackageEditedCopy.load(source)
        let editor = try PackageEditor(source: source)
        #expect(editor.save(to: root.appendingPathComponent("With Metadata Copy.screenplay")))
    }

    @Test func dialogueRepliesWrappedInFencesOrProseStillParse() throws {
        let lines = ["One.", "Two.", "Three."]
        let array = String(decoding: try JSONEncoder().encode(lines), as: UTF8.self)
        #expect(DialogueAPI.dialogueLines(in: "```json\n" + array + "\n```") == lines)
        #expect(DialogueAPI.dialogueLines(in: "Here are three options: " + array) == lines)
        #expect(DialogueAPI.dialogueLines(in: "No array here") == nil)
    }

    @Test func fdxImportNamesSceneNumbersNotesAndRevisionsItDoesNotKeep() throws {
        let xml = """
        <FinalDraft DocumentType="Script"><Content>
        <Paragraph Number="12A" Type="Scene Heading"><Text>INT. ROOM - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text RevisionID="2">Changed line.</Text></Paragraph>
        </Content><ScriptNotes><ScriptNote><Paragraph><Text>Note</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>
        """
        let result = try FDXImporter().importData(Data(xml.utf8), title: "Numbers")
        #expect(result.document.screenplay.elements.map(\.text) == ["INT. ROOM - DAY", "Changed line."])
        #expect(result.warnings.contains { $0.contains("scene numbers") })
        #expect(result.warnings.contains { $0.contains("script notes") })
        #expect(result.warnings.contains { $0.contains("revision marks") })
    }
}
