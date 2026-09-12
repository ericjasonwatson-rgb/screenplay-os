import Foundation
import ScreenplayDomain

public enum FDXImportError: Error, LocalizedError {
    case unreadableXML

    public var errorDescription: String? {
        switch self {
        case .unreadableXML:
            return "The FDX file could not be parsed as XML."
        }
    }
}

public struct FDXImportResult: Equatable {
    public var document: OpenScreenplayDocument
    public var warnings: [String]

    public init(document: OpenScreenplayDocument, warnings: [String] = []) {
        self.document = document
        self.warnings = warnings
    }
}

public final class FDXImporter: NSObject, XMLParserDelegate {
    private var paragraphs: [FDXParagraph] = []
    private var currentParagraph: FDXParagraph?
    private var currentText = ""
    private var insideText = false
    private var elementStack: [String] = []
    private var activeParagraphDepth: Int?
    private var activeTextDepth: Int?
    private var parseError: Error?

    public func importFile(at url: URL, title: String? = nil, author: String = "") throws -> FDXImportResult {
        let data = try Data(contentsOf: url)
        return try importData(data, title: title ?? url.deletingPathExtension().lastPathComponent, author: author)
    }

    public func importData(_ data: Data, title: String, author: String = "") throws -> FDXImportResult {
        paragraphs = []
        currentParagraph = nil
        currentText = ""
        insideText = false
        elementStack = []
        activeParagraphDepth = nil
        activeTextDepth = nil
        parseError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse(), parseError == nil else {
            throw parseError ?? FDXImportError.unreadableXML
        }

        let importedParagraphs = paragraphs.filter {
            $0.type == "Page Break" || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let elements = importedParagraphs.map { paragraph in
            ScreenplayElement(
                id: UUID(),
                type: ElementType(fdxParagraphType: paragraph.type),
                text: paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines),
                externalIDs: paragraph.id.map { ["fdx_paragraph_id": $0] } ?? [:]
            )
        }

        let screenplay = Screenplay(
            metadata: ScreenplayMetadata(title: title),
            elements: elements
        )
        let project = Project(
            metadata: ProjectMetadata(title: title, author: author),
            screenplayID: screenplay.id
        )

        return FDXImportResult(
            document: OpenScreenplayDocument(project: project, screenplay: screenplay),
            warnings: warnings(for: importedParagraphs)
        )
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let parentElement = elementStack.last
        elementStack.append(elementName)

        switch elementName {
        case "Paragraph" where parentElement == "Content":
            currentParagraph = FDXParagraph(
                type: attributeDict["Type"] ?? "General",
                id: attributeDict["id"],
                text: ""
            )
            activeParagraphDepth = elementStack.count
        case "Text" where activeParagraphDepth != nil:
            insideText = true
            activeTextDepth = elementStack.count
            currentText = ""
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText, activeTextDepth != nil {
            currentText += string
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "Text" where activeTextDepth == elementStack.count:
            currentParagraph?.text += currentText
            insideText = false
            activeTextDepth = nil
            currentText = ""
        case "Paragraph" where activeParagraphDepth == elementStack.count:
            if let paragraph = currentParagraph {
                paragraphs.append(paragraph)
            }
            currentParagraph = nil
            activeParagraphDepth = nil
        default:
            break
        }

        _ = elementStack.popLast()
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private func warnings(for paragraphs: [FDXParagraph]) -> [String] {
        let unknownTypes = Set(
            paragraphs
                .map(\.type)
                .filter { ElementType(fdxParagraphType: $0) == .general && $0 != "General" }
        )
        return unknownTypes.sorted().map { "Mapped unsupported FDX paragraph type '\($0)' to general." }
    }
}

private struct FDXParagraph: Equatable {
    var type: String
    var id: String?
    var text: String
}

private extension ElementType {
    init(fdxParagraphType: String) {
        switch fdxParagraphType {
        case "Scene Heading":
            self = .sceneHeading
        case "Action":
            self = .action
        case "Character":
            self = .character
        case "Dialogue":
            self = .dialogue
        case "Parenthetical":
            self = .parenthetical
        case "Transition":
            self = .transition
        case "Shot":
            self = .shot
        case "Page Break":
            self = .pageBreak
        default:
            self = .general
        }
    }
}
