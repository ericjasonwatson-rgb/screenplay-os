import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Campaign agency offline document extraction")
struct CampaignAgencyDocumentExtractionTests {
    typealias Extractor = CampaignAgencyDocumentExtraction
    typealias Failure = CampaignAgencyDocumentExtraction.Failure

    @Test func docxPreservesUnicodeSpacesTabsBreaksAndEmptyParagraphs() throws {
        let source = """
        <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:t xml:space="preserve">  Café &amp; 東京 🚀  </w:t><w:tab/><w:t>Next</w:t><w:br/><w:t>Line</w:t><w:cr/><w:noBreakHyphen/><w:softHyphen/></w:r></w:p>
        <w:p/>
        <w:p><w:r><w:t>Last</w:t></w:r></w:p>
        """
        let result = try Extractor.extract(data: docx(body: source), filename: "Agency.DOCX")
        let expected = "  Café & 東京 🚀  \tNext\nLine\n\u{2011}\u{00ad}\n\n\n\nLast"
        #expect(Data(result.text.utf8) == Data(expected.utf8))
        #expect(result.sections == [expected])
        #expect(result.formatRawValue == "docx")
        #expect(result.extractor == "docx-body-text-v1")
        #expect(result.notices.contains { $0.contains("not visual reading order") })
    }

    @Test func docxFlattensTableAndWordTextBoxParagraphsInXMLOrder() throws {
        let body = """
        <w:p><w:r><w:t>Start</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Cell B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:r><w:pict><w:txbxContent><w:p><w:r><w:t>Box</w:t></w:r></w:p></w:txbxContent></w:pict></w:r></w:p>
        """
        let result = try Extractor.extract(data: docx(body: body, extras: [Member(name: "word/header1.xml", text: "<w:hdr xmlns:w=\"\(wordNamespace)\"><w:p><w:r><w:t>Header excluded</w:t></w:r></w:p></w:hdr>")]), filename: "Brief.docx")
        #expect(result.text == "Start\n\nCell A\n\nCell B\n\n\n\nBox")
        #expect(!result.text.contains("Header excluded"))
        #expect(result.notices.contains { $0.contains("headers, footers") })
    }

    @Test func docxXMLLineEndingNormalizationIsExplicit() throws {
        let result = try Extractor.extract(data: docx(body: "<w:p><w:r><w:t>A\r\nB\rC&#13;D</w:t></w:r></w:p>"), filename: "Brief.docx")
        #expect(result.text == "A\nB\nC\rD")
        #expect(result.notices.contains { $0.contains("XML line-ending normalization") })
    }

    @Test func docxSeparatesTextResumingAfterNestedParagraph() throws {
        let body = "<w:p><w:r><w:t>A</w:t><w:pict><w:txbxContent><w:p><w:r><w:t>B</w:t></w:r></w:p></w:txbxContent></w:pict><w:t>C</w:t></w:r></w:p>"
        #expect(try Extractor.extract(data: docx(body: body), filename: "Brief.docx").text == "A\n\nB\n\nC")
    }

    @Test func docxRejectsEncodingDeclarationThatHidesDTDMarkup() throws {
        let utf7 = "<?xml version=\"1.0\" encoding=\"UTF-7\"?>\n+ADwAIQ-DOCTYPE r [ +ADwAIQ-ELEMENT r ANY+AD4- ]+AD4-\n<r>ok</r>"
        #expect(throws: Failure.unsafeXML) {
            try Extractor.extract(data: docx(extras: [Member(name: "customXml/item1.xml", text: utf7)]), filename: "Brief.docx")
        }
        let utf8 = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><r>ok</r>"
        #expect(try Extractor.extract(data: docx(extras: [Member(name: "customXml/item1.xml", text: utf8)]), filename: "Brief.docx").text == "Agency brief")
    }

    @Test func docxRejectsRepeatedUnclosedXMLDeclarationsWithBoundedPreflight() throws {
        let repeated = String(repeating: "<?xml ", count: 100_000)
        #expect(throws: Failure.unsafeXML) {
            try Extractor.extract(data: docx(extras: [Member(name: "customXml/item1.xml", text: repeated)]), filename: "Brief.docx")
        }
    }

    @Test func docxAcceptsKnownDeflatedArchiveAndChecksCRCVector() throws {
        // Python zipfile-generated deterministic raw-DEFLATE ZIP fixture, no
        // external fixture file or compressor needed during the tests.
        let fixture = "UEsDBBQAAAAIAAAAIVCsbhJangAAANwAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbF2PsQ7CMBBDf6XKitqrGBhQ24UdGPiBU3JtI5pLlBwF/p4EpA6Mlu1nubu9A6Xq5RZOvZpFwhEg6ZkcpsYH4uyMPjqULOMEAfUdJ4J92x5AexZiqaUw1NBdVorRGqquGOWMjnoFTx8NGK8fLiebTFPV6Vcry73CEBarUaxnWNn8bdZ+HK2mrV9oIXpNKVme3NJsjkPLu4KHoYPvqeEDUEsDBBQAAAAIAAAAIVBhey9DiQAAAPIAAAALAAAAX3JlbHMvLnJlbHONzzsOAiEQBuCrEA6ws1pYGKCy2dZ4AQLDIy6PDBj19lJYrMbCcuaffH9GnHHVPZbcQqyNPdKam+Sh93oEaCZg0m0qFfNIXKGk+xjJQ9Xmqj3Cfp4PQFuDK7E12WIlp8XuOLs8K/5jF+eiwVMxt4S5/6j4uhiyJo9d8nshC/a9ngbLQQn4eFG9AFBLAwQUAAAACAAAACFQdb9S5IQAAACiAAAAEQAAAHdvcmQvZG9jdW1lbnQueG1ssym3SslPLs1NzStRqMjNySu2KrdVyigpKbDS1y9OzkjNTSzWyy9IzQPKpeUX5SaWALlF6frl+UUpBUX5yanFxZl56bk5+kYGBmb6uYmZeUp2NuVWSfkplSC6AEQUgYgSO6eizNQ0heTEtMMrFT7Mn9Vgow8SBZFFYLIATEJ06iNcZQcAUEsBAhQDFAAAAAgAAAAhUKxuElqeAAAA3AAAABMAAAAAAAAAAAAAAKSBAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAAACFQYXsvQ4kAAADyAAAACwAAAAAAAAAAAAAApIHPAAAAX3JlbHMvLnJlbHNQSwECFAMUAAAACAAAACFQdb9S5IQAAACiAAAAEQAAAAAAAAAAAAAApIGBAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAMAAwC5AAAANAIAAAAA"
        let bytes = try #require(Data(base64Encoded: fixture))
        #expect(try Extractor.extract(data: bytes, filename: "Brief.docx").text == "Brief café 🚀")
        #expect(CampaignAgencyDocumentZIP.checksum(Array("123456789".utf8)) == 0xcbf43926)
    }

    @Test func docxAcceptsDataDescriptorsWithoutTrustingTheirSizes() throws {
        var members = standardMembers(body: "<w:p><w:r><w:t>Descriptor</w:t></w:r></w:p>")
        members[2].flags = 8
        #expect(try Extractor.extract(data: zip(members), filename: "Brief.docx").text == "Descriptor")
    }

    @Test func docxRejectsExternalRelationshipsInEveryPart() throws {
        for target in ["https://example.invalid/private", "file:///private/local", "//example.invalid/asset"] {
            let xml = "<Relationships xmlns=\"\(relationshipNamespace)\"><Relationship Id=\"external\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(target)\" TargetMode=\"External\"/></Relationships>"
            #expect(throws: Failure.externalRelationship) {
                try Extractor.extract(data: docx(extras: [Member(name: "word/_rels/document.xml.rels", text: xml)]), filename: "Brief.docx")
            }
        }
    }

    @Test func docxAcceptsExactStandardRootCorePropertiesWithoutExtractingMetadata() throws {
        for mode in [nil, "Internal"] as [String?] {
            let result = try Extractor.extract(data: zip(corePropertiesMembers(mode: mode)), filename: "Brief.docx")
            #expect(result.text == "Agency brief")
            #expect(!result.text.contains("Synthetic Metadata Author"))
        }
    }

    @Test func docxRejectsCorePropertiesRelationshipFromNonRootParts() throws {
        for part in ["word/_rels/document.xml.rels", "customXml/_rels/item1.xml.rels"] {
            #expect(throws: Failure.unsupportedContent) {
                try Extractor.extract(data: zip(corePropertiesMembers(relationshipPart: part)), filename: "Brief.docx")
            }
        }
    }

    @Test func docxRejectsCorePropertiesRelationshipWithUnexpectedTarget() throws {
        for target in ["word/document.xml", "docProps/alternate.xml", "docProps/../core.xml", "./docProps/core.xml", "docProps/CORE.xml"] {
            #expect(throws: Failure.unsupportedContent) {
                try Extractor.extract(data: zip(corePropertiesMembers(target: target)), filename: "Brief.docx")
            }
        }
    }

    @Test func docxRejectsSpoofedMetadataAndEmbeddedPackageRelationshipTypes() throws {
        let rejectedTypes = [
            corePropertiesType + "/extra", corePropertiesType + "-suffix", corePropertiesType + "?metadata",
            corePropertiesType.uppercased(),
            "https://example.invalid/package/2006/relationships/metadata/core-properties",
            "http://schemas.openxmlformats.org/officeDocument/2006/relationships/package",
            "http://purl.oclc.org/ooxml/officeDocument/relationships/package",
            corePropertiesType + "/oleObject"
        ]
        for type in rejectedTypes {
            #expect(throws: Failure.unsupportedContent) {
                try Extractor.extract(data: zip(corePropertiesMembers(type: type)), filename: "Brief.docx")
            }
        }
    }

    @Test func docxRejectsExternalCorePropertiesModesAndTargets() throws {
        for mode in ["External", "EXTERNAL", "internal"] {
            #expect(throws: Failure.externalRelationship) {
                try Extractor.extract(data: zip(corePropertiesMembers(mode: mode)), filename: "Brief.docx")
            }
        }
        for target in ["https://example.invalid/core.xml", "file:///private/core.xml", "/docProps/core.xml"] {
            #expect(throws: Failure.externalRelationship) {
                try Extractor.extract(data: zip(corePropertiesMembers(target: target, mode: "Internal")), filename: "Brief.docx")
            }
        }
    }

    @Test func docxStillRejectsUnsafeAndUnsupportedCorePropertiesXML() throws {
        for xml in [
            "<core xmlns:w=\"\(wordNamespace)\"><w:ins/></core>",
            "<core xmlns:w=\"\(wordNamespace)\"><w:fldSimple/></core>",
            "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"/>",
            "<core><?synthetic instruction?></core>"
        ] {
            #expect(throws: Failure.unsupportedContent) {
                try Extractor.extract(data: zip(corePropertiesMembers(coreXML: xml)), filename: "Brief.docx")
            }
        }
        for xml in [
            "<core><broken></core>",
            "<!DOCTYPE core SYSTEM 'https://example.invalid/never-fetch'><core/>",
            "<!DOCTYPE core [<!ENTITY secret SYSTEM 'file:///never-read'>]><core>&secret;</core>"
        ] {
            #expect(throws: Failure.unsafeXML) {
                try Extractor.extract(data: zip(corePropertiesMembers(coreXML: xml)), filename: "Brief.docx")
            }
        }
        let external = "<Relationships xmlns=\"\(relationshipNamespace)\"><Relationship Id=\"external\" Type=\"\(corePropertiesType)\" Target=\"https://example.invalid/core.xml\" TargetMode=\"External\"/></Relationships>"
        #expect(throws: Failure.externalRelationship) {
            try Extractor.extract(data: zip(corePropertiesMembers(coreXML: external)), filename: "Brief.docx")
        }
    }

    @Test func docxRejectsDTDAndEntitiesEvenInUnusedParts() throws {
        let invalidXML = [
            "<!DOCTYPE data SYSTEM 'https://example.invalid/private'><data/>",
            "<!DOCTYPE data [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><data>&secret;</data>",
            "<!DOCTYPE data [<!ENTITY repeated 'xx'>]><data>&repeated;</data>"
        ]
        for xml in invalidXML {
            #expect(throws: Failure.unsafeXML) {
                try Extractor.extract(data: docx(extras: [Member(name: "customXml/item1.xml", text: xml)]), filename: "Brief.docx")
            }
        }
        let utf16 = Member(name: "customXml/item1.xml", bytes: Data([0xff, 0xfe]) + "<data/>".data(using: .utf16LittleEndian)!)
        #expect(throws: Failure.unsafeXML) { try Extractor.extract(data: docx(extras: [utf16]), filename: "Brief.docx") }
    }

    @Test func docxRejectsTrackedChangesFieldsAndAmbiguousContent() throws {
        for element in ["ins", "del", "moveFrom", "moveTo", "pPrChange", "fldSimple", "fldChar", "instrText", "sdt", "customXml", "altChunk", "object", "sym", "contentPart", "control", "pgNum", "ruby"] {
            #expect(throws: Failure.unsupportedContent) {
                try Extractor.extract(data: docx(body: "<w:p><w:r><w:t>Known</w:t><w:\(element)/></w:r></w:p>"), filename: "Brief.docx")
            }
        }
        let alternate = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"/>"
        #expect(throws: Failure.unsupportedContent) { try Extractor.extract(data: docx(body: alternate), filename: "Brief.docx") }
        #expect(throws: Failure.unsupportedContent) {
            try Extractor.extract(data: docx(extras: [Member(name: "word/embeddings/object.bin", text: "object")]), filename: "Brief.docx")
        }
        #expect(throws: Failure.unsupportedContent) {
            try Extractor.extract(data: docx(body: "<w:p><w:r><a:t xmlns:a=\"urn:drawing\">Hidden facts</a:t></w:r></w:p>"), filename: "Brief.docx")
        }
    }

    @Test func docxRejectsEmptyMalformedAndExcessivelyNestedXML() throws {
        #expect(throws: Failure.noText) { try Extractor.extract(data: docx(body: "<w:p/>"), filename: "Brief.docx") }
        #expect(throws: Failure.unsafeXML) { try Extractor.extract(data: docx(body: "<w:p>"), filename: "Brief.docx") }
        let deep = String(repeating: "<w:wrapper>", count: 65) + String(repeating: "</w:wrapper>", count: 65)
        #expect(throws: Failure.unsafeXML) { try Extractor.extract(data: docx(body: deep), filename: "Brief.docx") }
    }

    @Test func docxTextLimitCountsUTF8BytesAndParagraphSeparators() throws {
        let exact = String(repeating: "é", count: Extractor.maximumTextBytes / 2)
        #expect(try Extractor.extract(data: docx(body: "<w:p><w:r><w:t>\(exact)</w:t></w:r></w:p>"), filename: "Brief.docx").text.utf8.count == Extractor.maximumTextBytes)
        for body in ["<w:p><w:r><w:t>\(exact)é</w:t></w:r></w:p>", "<w:p><w:r><w:t>\(exact)</w:t></w:r></w:p><w:p/>"] {
            #expect(throws: Failure.tooMuchText) { try Extractor.extract(data: docx(body: body), filename: "Brief.docx") }
        }
    }

    @Test func zipRejectsCRCTruncationTrailingDataAndLocalHeaderDisagreement() throws {
        let valid = docx()
        var badCRC = valid
        // First member starts immediately after its local header and filename.
        badCRC[30 + "[Content_Types].xml".utf8.count] ^= 1
        var badLocalMethod = valid
        badLocalMethod[8] = 8
        for data in [Data(valid.dropLast()), valid + Data([0]), badCRC, badLocalMethod, Data("not a zip".utf8)] {
            #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: data, filename: "Brief.docx") }
        }
    }

    @Test func zipRejectsDuplicateTraversalEncryptedZIP64AndNonregularMembers() throws {
        for name in ["../escape.xml", "/absolute.xml", "word/../escape.xml", "word\\escape.xml", "word//empty.xml", "word/./dot.xml", "word/", "WORD/DOCUMENT.XML"] {
            #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: docx(extras: [Member(name: name, text: "X")]), filename: "Brief.docx") }
        }
        #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: docx(extras: [Member(name: "word/document.xml", text: "X")]), filename: "Brief.docx") }
        var encrypted = standardMembers(); encrypted[0].flags = 1
        var zip64 = standardMembers(); zip64[0].extra = Data([1, 0, 0, 0])
        var symlink = standardMembers(); symlink[0].attributes = UInt32(0o120777) << 16
        var directory = standardMembers(); directory[0].attributes = 0x10
        for members in [encrypted, zip64, symlink, directory] {
            #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: zip(members), filename: "Brief.docx") }
        }
    }

    @Test func zipRejectsAdvertisedBombsAndTooManyMembersBeforeInflation() throws {
        var bomb = standardMembers()
        bomb[0].expandedSize = UInt32(CampaignAgencyDocumentZIP.maximumMemberBytes + 1)
        #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: zip(bomb), filename: "Brief.docx") }
        var totalBomb = standardMembers()
        for index in totalBomb.indices { totalBomb[index].expandedSize = UInt32(CampaignAgencyDocumentZIP.maximumMemberBytes) }
        #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: zip(totalBomb), filename: "Brief.docx") }
        let tooMany = (0...CampaignAgencyDocumentZIP.maximumEntries).map { Member(name: "member\($0).txt", text: "X") }
        #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: zip(tooMany), filename: "Brief.docx") }
        // Deflate stream for 100,000 'A' bytes, with a dishonest size of one.
        // The decoder's two-byte output allocation must stop the expansion.
        let compressed = Data(base64Encoded: "7cExAQAAAMKgbOtfyhoeQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACvBg==")!
        var dishonest = standardMembers()
        dishonest[0].bytes = compressed; dishonest[0].method = 8; dishonest[0].expandedSize = 1
        #expect(throws: Failure.unsafeArchive) { try Extractor.extract(data: zip(dishonest), filename: "Brief.docx") }
    }

    @Test func rejectsUnsupportedExtensionsAndOriginalSize() throws {
        #expect(throws: Failure.unsupported) { try Extractor.extract(data: Data("legacy".utf8), filename: "Brief.doc") }
        #expect(throws: Failure.originalTooLarge) { try Extractor.extract(data: Data(), filename: "Brief.pdf") }
        #expect(throws: Failure.originalTooLarge) {
            try Extractor.extract(data: Data(repeating: 0, count: Extractor.maximumOriginalBytes + 1), filename: "Brief.docx")
        }
    }

    @Test func extractionHonorsCancellationBeforeParsing() async throws {
        let data = docx()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try Extractor.extract(data: data, filename: "Brief.docx")
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func pdfExtractionFailsClosedBeforeAnyNativeParser() throws {
        #expect(throws: Failure.pdfDisabled) {
            try Extractor.extract(data: Data("%PDF-1.7\n".utf8), filename: "Agency.PDF")
        }
        #expect(Failure.pdfDisabled.localizedDescription.contains("parser can be isolated safely"))
    }

    private let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private let relationshipNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
    private let corePropertiesType = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"

    private func corePropertiesMembers(relationshipPart: String = "_rels/.rels", type: String? = nil,
                                       target: String = "docProps/core.xml", mode: String? = nil,
                                       coreXML: String? = nil) -> [Member] {
        var members = standardMembers()
        let coreOverride = "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        members[0].bytes = Data(String(decoding: members[0].bytes, as: UTF8.self)
            .replacingOccurrences(of: "</Types>", with: coreOverride + "</Types>").utf8)
        let modeAttribute = mode.map { " TargetMode=\"\($0)\"" } ?? ""
        let relationship = "<Relationship Id=\"rCore\" Type=\"\(type ?? corePropertiesType)\" Target=\"\(target)\"\(modeAttribute)/>"
        if relationshipPart == "_rels/.rels" {
            members[1].bytes = Data(String(decoding: members[1].bytes, as: UTF8.self)
                .replacingOccurrences(of: "</Relationships>", with: relationship + "</Relationships>").utf8)
        } else {
            members.append(Member(name: relationshipPart, text: "<Relationships xmlns=\"\(relationshipNamespace)\">\(relationship)</Relationships>"))
        }
        let metadata = coreXML ?? "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:creator>Synthetic Metadata Author</dc:creator><cp:revision>1</cp:revision></cp:coreProperties>"
        members.append(Member(name: "docProps/core.xml", text: metadata))
        return members
    }

    private func standardMembers(body: String = "<w:p><w:r><w:t>Agency brief</w:t></w:r></w:p>") -> [Member] {
        [
            Member(name: "[Content_Types].xml", text: "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"),
            Member(name: "_rels/.rels", text: "<Relationships xmlns=\"\(relationshipNamespace)\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            Member(name: "word/document.xml", text: "<w:document xmlns:w=\"\(wordNamespace)\"><w:body>\(body)</w:body></w:document>")
        ]
    }

    private func docx(body: String = "<w:p><w:r><w:t>Agency brief</w:t></w:r></w:p>", extras: [Member] = []) -> Data {
        zip(standardMembers(body: body) + extras)
    }

    private struct Member {
        var name: String
        var bytes: Data
        var flags: UInt16 = 0
        var method: UInt16 = 0
        var extra = Data()
        var attributes: UInt32 = UInt32(0o100644) << 16
        var expandedSize: UInt32?
        init(name: String, text: String) { self.name = name; bytes = Data(text.utf8) }
        init(name: String, bytes: Data) { self.name = name; self.bytes = bytes }
    }

    private func zip(_ members: [Member]) -> Data {
        var local = Data()
        var central = Data()
        for member in members {
            let offset = UInt32(local.count)
            let name = Data(member.name.utf8)
            let crc = CampaignAgencyDocumentZIP.checksum(Array(member.bytes))
            let size = UInt32(member.bytes.count)
            let expanded = member.expandedSize ?? size
            let descriptor = member.flags & 8 != 0
            local.appendLE(UInt32(0x04034b50)); local.appendLE(UInt16(20))
            local.appendLE(member.flags); local.appendLE(member.method)
            local.appendLE(UInt32(0)); local.appendLE(descriptor ? UInt32(0) : crc)
            local.appendLE(descriptor ? UInt32(0) : size); local.appendLE(descriptor ? UInt32(0) : expanded)
            local.appendLE(UInt16(name.count)); local.appendLE(UInt16(member.extra.count))
            local.append(name); local.append(member.extra); local.append(member.bytes)
            if descriptor {
                local.appendLE(UInt32(0x08074b50)); local.appendLE(crc); local.appendLE(size); local.appendLE(expanded)
            }
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(0x0314)); central.appendLE(UInt16(20))
            central.appendLE(member.flags); central.appendLE(member.method); central.appendLE(UInt32(0))
            central.appendLE(crc); central.appendLE(size); central.appendLE(expanded)
            central.appendLE(UInt16(name.count)); central.appendLE(UInt16(member.extra.count))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(member.attributes); central.appendLE(offset); central.append(name); central.append(member.extra)
        }
        let offset = UInt32(local.count)
        local.append(central)
        local.appendLE(UInt32(0x06054b50)); local.appendLE(UInt32(0))
        local.appendLE(UInt16(members.count)); local.appendLE(UInt16(members.count))
        local.appendLE(UInt32(central.count)); local.appendLE(offset); local.appendLE(UInt16(0))
        return local
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
