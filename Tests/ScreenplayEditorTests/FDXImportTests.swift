import Foundation
import Testing
import ScreenplayDomain
import ScreenplayFDX

@Suite struct FDXImportTests {
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
