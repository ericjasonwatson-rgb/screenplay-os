import Foundation

/// A bounded, non-rendering WordprocessingML body reader. It intentionally
/// rejects features whose visible text depends on revisions, calculations,
/// linked resources, alternate representations or embedded applications.
enum CampaignAgencyDocumentXML {
    typealias Failure = CampaignAgencyDocumentExtraction.Failure
    private static let wordNamespaces = Set([
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
        "http://purl.oclc.org/ooxml/wordprocessingml/main"
    ])
    private static let relationshipsNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let corePropertiesRelationshipType = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
    private static let contentTypesNamespace = "http://schemas.openxmlformats.org/package/2006/content-types"
    private static let mainContentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
    private static let officeDocumentTypes = Set([
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument",
        "http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument"
    ])

    static func extract(archive: Data) throws -> CampaignAgencyDocumentExtraction.Extraction {
        let members = try CampaignAgencyDocumentZIP.read(archive)
        guard members["[Content_Types].xml"] != nil, members["_rels/.rels"] != nil,
              members["word/document.xml"] != nil else { throw Failure.unreadable }
        var body: Parser?
        var contentTypeFound = false
        var mainRelationshipFound = false
        for name in members.keys.sorted() {
            try Task.checkCancellation()
            let lower = name.lowercased()
            guard !lower.hasSuffix(".bin"), !lower.contains("/embeddings/"),
                  !lower.contains("/activex/"), !lower.hasPrefix("customui/") else {
                throw Failure.unsupportedContent
            }
            guard lower.hasSuffix(".xml") || lower.hasSuffix(".rels") else { continue }
            guard let data = members[name] else { throw Failure.unreadable }
            let parsed = try Parser.parse(data, name: name)
            if name == "word/document.xml" { body = parsed }
            if name == "[Content_Types].xml" { contentTypeFound = parsed.mainContentTypeFound }
            if name == "_rels/.rels" { mainRelationshipFound = parsed.mainRelationshipFound }
        }
        guard contentTypeFound, mainRelationshipFound, let body, body.bodyCount == 1 else {
            throw Failure.unreadable
        }
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noText }
        return CampaignAgencyDocumentExtraction.Extraction(
            formatRawValue: "docx", sections: [body.text], extractor: "docx-body-text-v1", notices: [
                "Local DOCX body-text extraction only. XML text characters and spaces are preserved after XML decoding. Tabs become tabs; explicit breaks become line feeds. Two line feeds separate paragraph starts (including empty paragraphs) and resumed text after nested paragraphs. XML line-ending normalization applies.",
                "Paragraphs in tables and Word text boxes are flattened in XML order, not visual reading order. Hidden body text can appear. Fonts, numbering/bullet labels, page layout, images, drawing text, headers, footers, footnotes, endnotes, comments, and other non-body content are not extracted. Review the extracted text against the original before importing.",
                "External relationships, DTDs, tracked changes, fields, content controls, alternative content, embedded objects, and macros are rejected. No resource was fetched or rendered."
            ])
    }

    private final class Parser: NSObject, XMLParserDelegate {
        let name: String
        var failure: Failure?
        var depth = 0
        var nodes = 0
        var bodyDepth: Int?
        var textDepth: Int?
        var paragraphDepths: [Int] = []
        var paragraphCount = 0
        var bodyCount = 0
        var text = ""
        var textBytes = 0
        var mainContentTypeFound = false
        var mainRelationshipFound = false
        var relationshipIDs = Set<String>()
        var sawRoot = false
        var elementStack: [(name: String, namespace: String)] = []
        var needsResumedParagraphBoundary = false
        var cancelled = false

        init(name: String) { self.name = name }

        static func parse(_ data: Data, name: String) throws -> Parser {
            try Task.checkCancellation()
            // Only UTF-8 XML is supported. This makes the DTD/entity preflight
            // unambiguous even for UTF-16/32 and disguised XML declarations.
            guard let source = String(data: data, encoding: .utf8),
                  !source.unicodeScalars.contains(where: { $0.value == 0 }),
                  source.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
                  source.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
                throw Failure.unsafeXML
            }
            // Valid UTF-8 *bytes* can still declare UTF-7 or another encoding.
            // Such a declaration could conceal DTD syntax from the preflight.
            // Inspect at most one declaration and at most 1 KiB. An unanchored
            // XML-declaration regex over attacker input can scan quadratically.
            let logicalStart = source.first == "\u{feff}" ? source.index(after: source.startIndex) : source.startIndex
            if let start = source.range(of: "<?xml", options: .caseInsensitive) {
                guard start.lowerBound == logicalStart else { throw Failure.unsafeXML }
                let bomBytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? 3 : 0
                let prefix = String(decoding: data.dropFirst(bomBytes).prefix(1_024), as: UTF8.self)
                guard let end = prefix.range(of: "?>") else { throw Failure.unsafeXML }
                let declaration = String(prefix[..<end.upperBound])
                let encoding = try NSRegularExpression(pattern: #"encoding\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
                let range = NSRange(declaration.startIndex..<declaration.endIndex, in: declaration)
                for attribute in encoding.matches(in: declaration, range: range) {
                    guard let range = Range(attribute.range(at: 1), in: declaration), declaration[range].lowercased() == "utf-8" else {
                        throw Failure.unsafeXML
                    }
                }
            }
            let delegate = Parser(name: name)
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            parser.delegate = delegate
            let success = parser.parse()
            if delegate.cancelled { throw CancellationError() }
            try Task.checkCancellation()
            if let failure = delegate.failure { throw failure }
            guard success, delegate.depth == 0, delegate.sawRoot else { throw Failure.unsafeXML }
            return delegate
        }

        func reject(_ parser: XMLParser, _ reason: Failure) {
            if failure == nil { failure = reason }
            parser.abortParsing()
        }

        func append(_ value: String, parser: XMLParser) {
            guard failure == nil else { return }
            if needsResumedParagraphBoundary && !value.isEmpty {
                needsResumedParagraphBoundary = false
                append("\n\n", parser: parser)
                guard failure == nil else { return }
            }
            let count = value.utf8.count
            guard count <= CampaignAgencyDocumentExtraction.maximumTextBytes - textBytes else {
                reject(parser, .tooMuchText)
                return
            }
            text += value
            textBytes += count
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            guard failure == nil else { return }
            depth += 1
            nodes += 1
            if Task.isCancelled {
                cancelled = true
                parser.abortParsing()
                return
            }
            guard depth <= 64, nodes <= 100_000, attributeDict.count <= 128 else {
                reject(parser, .unsafeXML); return
            }
            let namespace = namespaceURI ?? ""
            let parent = elementStack.last
            elementStack.append((elementName, namespace))
            if depth == 1 {
                sawRoot = true
                if name == "word/document.xml" && !(CampaignAgencyDocumentXML.wordNamespaces.contains(namespace) && elementName == "document") {
                    reject(parser, .unreadable); return
                }
                if name == "[Content_Types].xml" && !(namespace == CampaignAgencyDocumentXML.contentTypesNamespace && elementName == "Types") {
                    reject(parser, .unreadable); return
                }
                if name.lowercased().hasSuffix(".rels") && !(namespace == CampaignAgencyDocumentXML.relationshipsNamespace && elementName == "Relationships") {
                    reject(parser, .unsafeXML); return
                }
            }
            if namespace == CampaignAgencyDocumentXML.relationshipsNamespace && elementName == "Relationship" {
                guard let id = attributeDict["Id"], !id.isEmpty, relationshipIDs.insert(id).inserted,
                      let target = attributeDict["Target"], !target.isEmpty,
                      let type = attributeDict["Type"], !type.isEmpty else { reject(parser, .unsafeXML); return }
                let mode = attributeDict["TargetMode"] ?? "Internal"
                if mode != "Internal" || target.hasPrefix("/") || target.contains(":") || target.contains("\\") {
                    reject(parser, .externalRelationship); return
                }
                let lowerType = type.lowercased()
                // Standard package metadata is not an embedded package. Allow
                // only this exact root relationship and local target; its XML
                // still passes the same all-member safety checks as every part.
                let isStandardCoreProperties = name == "_rels/.rels" && mode == "Internal" &&
                    type == CampaignAgencyDocumentXML.corePropertiesRelationshipType && target == "docProps/core.xml"
                if ["oleobject", "vbaproject", "activex", "/control", "attachedtemplate", "afchunk"].contains(where: { lowerType.contains($0) }) ||
                    (lowerType.contains("/package") && !isStandardCoreProperties) {
                    reject(parser, .unsupportedContent); return
                }
                if name == "_rels/.rels", CampaignAgencyDocumentXML.officeDocumentTypes.contains(type) {
                    guard target == "word/document.xml", !mainRelationshipFound else { reject(parser, .unreadable); return }
                    mainRelationshipFound = true
                }
            }
            if namespace == CampaignAgencyDocumentXML.contentTypesNamespace {
                let type = attributeDict["ContentType"] ?? ""
                let lowerType = type.lowercased()
                if ["macroenabled", "vbaproject", "activex", "oleobject"].contains(where: { lowerType.contains($0) }) {
                    reject(parser, .unsupportedContent); return
                }
                if elementName == "Override", attributeDict["PartName"] == "/word/document.xml" {
                    guard type == CampaignAgencyDocumentXML.mainContentType, !mainContentTypeFound else { reject(parser, .unsupportedContent); return }
                    mainContentTypeFound = true
                }
            }
            if elementName == "AlternateContent" && namespace == "http://schemas.openxmlformats.org/markup-compatibility/2006" {
                reject(parser, .unsupportedContent); return
            }
            guard CampaignAgencyDocumentXML.wordNamespaces.contains(namespace) else {
                if textDepth != nil { reject(parser, .unsafeXML) }
                return
            }
            // A revision anywhere in the package is ambiguous, even when not
            // in the main body. Do not choose accepted/original text for users.
            if ["ins", "del", "delText", "delInstrText", "moveFrom", "moveTo", "sdt", "customXml", "altChunk",
                "fldSimple", "fldChar", "instrText", "object", "subDoc", "sym", "contentPart", "control", "pgNum", "ruby"].contains(elementName) ||
                elementName.hasSuffix("Change") || elementName.hasPrefix("moveFromRange") || elementName.hasPrefix("moveToRange") {
                reject(parser, .unsupportedContent); return
            }
            guard name == "word/document.xml" else { return }
            if elementName == "body" {
                guard depth == 2, bodyDepth == nil, bodyCount == 0 else { reject(parser, .unsafeXML); return }
                bodyDepth = depth
                bodyCount += 1
                return
            }
            guard bodyDepth != nil else { return }
            if textDepth != nil { reject(parser, .unsafeXML); return }
            switch elementName {
            case "p":
                needsResumedParagraphBoundary = false
                if paragraphCount > 0 { append("\n\n", parser: parser) }
                paragraphCount += 1
                paragraphDepths.append(depth)
            case "t":
                guard !paragraphDepths.isEmpty, parent?.name == "r",
                      CampaignAgencyDocumentXML.wordNamespaces.contains(parent?.namespace ?? "") else { reject(parser, .unsafeXML); return }
                textDepth = depth
            case "tab", "ptab", "br", "cr", "noBreakHyphen", "softHyphen":
                // w:tab also defines a tab stop inside paragraph properties.
                // Only run children represent characters in the source text.
                if elementName == "tab", parent?.name == "tabs" { return }
                guard !paragraphDepths.isEmpty, parent?.name == "r",
                      CampaignAgencyDocumentXML.wordNamespaces.contains(parent?.namespace ?? "") else { reject(parser, .unsafeXML); return }
                let values = ["tab": "\t", "ptab": "\t", "br": "\n", "cr": "\n", "noBreakHyphen": "\u{2011}", "softHyphen": "\u{00ad}"]
                append(values[elementName] ?? "", parser: parser)
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard failure == nil else { return }
            if textDepth == depth { textDepth = nil }
            if paragraphDepths.last == depth {
                if paragraphDepths.count > 1 { needsResumedParagraphBoundary = true }
                paragraphDepths.removeLast()
            }
            if bodyDepth == depth { bodyDepth = nil }
            elementStack.removeLast()
            depth -= 1
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard failure == nil else { return }
            if textDepth != nil { append(string, parser: parser) }
            else if bodyDepth != nil && !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // E.g. DrawingML text cannot be silently substituted for Word
                // body text or silently dropped when it may carry brief facts.
                reject(parser, .unsupportedContent)
            }
        }

        func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
            if textDepth != nil { append(whitespaceString, parser: parser) }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let string = String(data: CDATABlock, encoding: .utf8) else { reject(parser, .unsafeXML); return }
            self.parser(parser, foundCharacters: string)
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            reject(parser, .unsafeXML)
        }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            reject(parser, .unsafeXML)
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            reject(parser, .unsafeXML)
            return nil
        }
        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            reject(parser, .unsupportedContent)
        }
    }
}
