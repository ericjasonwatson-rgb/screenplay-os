import Foundation
import Testing
import ScreenplayDomain
import ScreenplayFDX

@Suite struct FDXImportTests {
    @Test func finalDraftGeneratedDualDialogueRequiresReviewAndRetainsEverySpeech() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Docs/AuditEvidence/fd13-dual-dialogue.fdx")
        let bytes = try Data(contentsOf: source)
        let importer = FDXImporter()
        #expect(throws: FDXImportError.dualDialogueRequiresReview) { try importer.importData(bytes, title: "Dual") }
        let result = try importer.importData(bytes, title: "Dual", allowSequentialDualDialogue: true)
        #expect(result.document.screenplay.elements.map(\.text) == ["INT. AUDIT ROOM - DAY", "Two speakers interrupt each other.", "ALICE", "AUDIT LEFT WORDS.", "BOB", "AUDIT RIGHT WORDS."])
        #expect(result.document.screenplay.elements.map(\.type) == [.sceneHeading, .action, .character, .dialogue, .character, .dialogue])
        #expect(result.document.screenplay.elements.allSatisfy { $0.externalIDs["fdx_paragraph_id"] != nil })
        #expect(result.warnings.contains { $0.contains("simultaneous delivery") })
        let reopened = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self,
            from: JSONEncoder.openScreenplayEncoder().encode(result.document))
        #expect(reopened.screenplay.elements == result.document.screenplay.elements)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func sequentialConversionKeepsBoundariesStylesAndMultipleBlocks() throws {
        let block = """
        <Paragraph Type="General" StartsNewPage="Yes"><DualDialogue><SpellCheckIgnoreLists><IgnoredWords><Text>NOT SCRIPT</Text></IgnoredWords></SpellCheckIgnoreLists>
        <Paragraph Type="Character"><Text>A</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(quietly)</Text></Paragraph>
        <Paragraph Type="Dialogue" id="speech"><Text Style="Italic"> é 😀 </Text></Paragraph>
        <Paragraph Type="Character"><Text>B</Text></Paragraph><Paragraph Type="Dialogue"><Text>Right.</Text></Paragraph>
        </DualDialogue></Paragraph>
        """
        let xml = "<FinalDraft><Content>" + block + "<Paragraph Type=\"Action\"><Text>Between.</Text></Paragraph>" + block + "<Paragraph Type=\"Action\"><Text>After.</Text></Paragraph></Content></FinalDraft>"
        let result = try FDXImporter().importData(Data(xml.utf8), title: "Two", allowSequentialDualDialogue: true)
        let elements = result.document.screenplay.elements
        #expect(elements.map(\.text) == ["", "A", "(quietly)", " é 😀 ", "B", "Right.", "Between.", "", "A", "(quietly)", " é 😀 ", "B", "Right.", "After."])
        #expect(elements.filter { $0.type == .pageBreak }.count == 2)
        #expect(elements[3].runs == [.init(start: 0, length: 6, style: .init(italic: true))])
        #expect(elements[3].externalIDs["fdx_paragraph_id"] == "speech")
    }

    @Test func unsupportedDualShapesFailWithoutPoisoningNextImport() throws {
        let speeches = "<Paragraph Type=\"Character\"><Text>A</Text></Paragraph><Paragraph Type=\"Dialogue\"><Text>Left.</Text></Paragraph><Paragraph Type=\"Character\"><Text>B</Text></Paragraph><Paragraph Type=\"Dialogue\"><Text>Right.</Text></Paragraph>"
        let malformed = [
            "<Paragraph><Text>Mixed wrapper</Text><DualDialogue>" + speeches + "</DualDialogue></Paragraph>",
            "<Paragraph><DualDialogue>" + speeches + "</DualDialogue><Text>Trailing wrapper</Text></Paragraph>",
            "<Paragraph><DualDialogue><Text>Unstructured</Text>" + speeches + "</DualDialogue></Paragraph>",
            "<Paragraph><DualDialogue><Paragraph Type=\"Action\"><Text>Unknown</Text></Paragraph></DualDialogue></Paragraph>",
            "<Paragraph><DualDialogue><Paragraph Type=\"Character\"><Text>Only cue</Text></Paragraph></DualDialogue></Paragraph>",
            "<DualDialogue>" + speeches + "</DualDialogue>"
        ]
        let importer = FDXImporter()
        for body in malformed {
            let data = Data(("<FinalDraft><Content>" + body + "</Content></FinalDraft>").utf8)
            #expect(throws: FDXImportError.unsupportedDualDialogue) { try importer.importData(data, title: "Bad", allowSequentialDualDialogue: true) }
        }
        let result = try importer.importData(Data("<FinalDraft><Content><Paragraph Type=\"Action\"><Text>Safe</Text></Paragraph></Content></FinalDraft>".utf8), title: "Safe")
        #expect(result.document.screenplay.elements.map(\.text) == ["Safe"])
    }

    @Test func appliesDeclaredAllCapsAfterReadingSettings() throws {
        let xml = """
        <FinalDraft><Content><Paragraph Type="Character"><Text Style="Italic">Straße</Text></Paragraph><Paragraph Type="Action"><Text>Mixed case</Text></Paragraph></Content><ElementSettings Type="Character"><FontSpec Style="AllCaps"/></ElementSettings></FinalDraft>
        """
        let result = try FDXImporter().importData(Data(xml.utf8), title: "Caps")
        #expect(result.document.screenplay.elements.map(\.text) == ["STRASSE", "Mixed case"])
        #expect(result.document.screenplay.elements[0].runs == [.init(start: 0, length: 7, style: .init(italic: true))])
    }
    @Test func isolatesScriptFromTitleAndNestedMetadata() throws {
        let xml = """
        <FinalDraft DocumentType="Script"><Content>
        <Paragraph Type="Scene Heading" id="s"><SceneProperties><Content><Paragraph><Text>WRONG</Text></Paragraph></Content><Text>ALSO WRONG</Text></SceneProperties><Text>INT. ROOM - DAY</Text></Paragraph>
        <Paragraph Type="Action" id="a"><Text>  A room.  </Text></Paragraph>
        <Paragraph Type="Action" id="blank"/>
        </Content><TitlePage><Content><Paragraph><Text>My Title</Text></Paragraph><Paragraph><Text>Written by Someone</Text></Paragraph></Content></TitlePage>
        <HeaderAndFooter><Header><Paragraph><Text>HEADER</Text></Paragraph></Header></HeaderAndFooter></FinalDraft>
        """
        let result = try FDXImporter().importData(Data(xml.utf8), title: "Filename")
        #expect(result.document.screenplay.elements.map(\.text) == ["INT. ROOM - DAY", "  A room.  ", ""])
        #expect(result.document.screenplay.elements.map { $0.externalIDs["fdx_paragraph_id"] } == ["s", "a", "blank"])
        #expect(result.document.titlePage.title == "My Title")
        #expect(result.document.titlePage.subtitle == "Written by Someone")
        #expect(!result.warnings.isEmpty)
    }

    @Test func preservesUnicodeStylesAndPageBreaksThroughSave() throws {
        let xml = """
        <FinalDraft><Content><Paragraph Type="Action" StartsNewPage="Yes"><Text> 😀 </Text><Text Style="Bold+Italic+Underline">éyes</Text><Text> end </Text></Paragraph><Paragraph Type="Page Break"/></Content></FinalDraft>
        """
        let document = try FDXImporter().importData(Data(xml.utf8), title: "Styles").document
        #expect(document.screenplay.elements.map(\.type) == [.pageBreak, .action, .pageBreak])
        let element = document.screenplay.elements[1]
        #expect(element.text == " 😀 éyes end ")
        #expect(element.runs == [.init(start: 3, length: 5, style: .init(bold: true, italic: true, underline: true))])
        #expect(document.formatVersion == "1.1")
        let reopened = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self,
            from: JSONEncoder.openScreenplayEncoder().encode(document))
        #expect(reopened.screenplay.elements == document.screenplay.elements)
    }

    @Test func rejectsNonScreenplaysAndResetsBetweenImports() throws {
        let importer = FDXImporter()
        #expect(throws: (any Error).self) { try importer.importData(Data("<other><Content/></other>".utf8), title: "Wrong") }
        #expect(throws: (any Error).self) { try importer.importData(Data("<FinalDraft>".utf8), title: "Broken") }
        let valid = Data("<FinalDraft><Content><Paragraph Type=\"Action\"><Text>Valid</Text></Paragraph></Content></FinalDraft>".utf8)
        #expect(try importer.importData(valid, title: "Valid").document.screenplay.elements.map(\.text) == ["Valid"])
        #expect(try importer.importData(valid, title: "Again").document.screenplay.elements.count == 1)
    }
}
