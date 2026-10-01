import Foundation
import ScreenplayDomain

public enum FDXImportError: Error, LocalizedError, Equatable {
    case unreadableXML
    case notScreenplay
    case dualDialogueRequiresReview
    case unsupportedDualDialogue

    public var errorDescription: String? {
        switch self {
        case .dualDialogueRequiresReview:
            return "This screenplay contains dual dialogue. Review a sequential-text copy before importing; side-by-side dialogue is not supported yet."
        case .unsupportedDualDialogue:
            return "This dual-dialogue structure cannot be safely converted. The screenplay was not imported and the original FDX is unchanged."
        case .notScreenplay:
            return "This file is not a Final Draft screenplay with a script Content section."
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
    private var titleParagraphs: [FDXParagraph] = []
    private var paragraphIsTitle = false
    private var textStyle = StyledText.Style()
    private var validRoot = false
    private var hasContent = false
    private var importWarnings: Set<String> = []
    private var settingType: String?
    private var capsTypes: Set<String> = []
    private var textAllCaps = false
    private var dualWrapper: FDXParagraph?
    private var dualChildTypes: [String] = []
    private var hasDualDialogue = false
    private var wrapperHasDualDialogue = false

    public func importFile(at url: URL, title: String? = nil, author: String = "", allowSequentialDualDialogue: Bool = false) throws -> FDXImportResult {
        let data = try Data(contentsOf: url)
        return try importData(data, title: title ?? url.deletingPathExtension().lastPathComponent, author: author, allowSequentialDualDialogue: allowSequentialDualDialogue)
    }

    public func importData(_ data: Data, title: String, author: String = "", allowSequentialDualDialogue: Bool = false) throws -> FDXImportResult {
        paragraphs = []
        currentParagraph = nil
        currentText = ""
        insideText = false
        elementStack = []
        activeParagraphDepth = nil
        activeTextDepth = nil
        parseError = nil
        titleParagraphs = []
        validRoot = false
        hasContent = false
        importWarnings = []
        capsTypes = []
        settingType = nil
        textAllCaps = false
        dualWrapper = nil
        dualChildTypes = []
        hasDualDialogue = false
        wrapperHasDualDialogue = false

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse(), parseError == nil else {
            throw parseError ?? FDXImportError.unreadableXML
        }

        guard validRoot, hasContent else { throw FDXImportError.notScreenplay }
        if hasDualDialogue, !allowSequentialDualDialogue { throw FDXImportError.dualDialogueRequiresReview }
        if hasDualDialogue {
            importWarnings.insert("Dual dialogue was converted to sequential speeches in source order. Both speakers and their text are retained, but simultaneous delivery and side-by-side layout are not represented. Keep the original FDX.")
        }
        let importedParagraphs = paragraphs
        var elements: [ScreenplayElement] = []
        for paragraph in importedParagraphs {
            if paragraph.startsNewPage, paragraph.type != "Page Break" {
                elements.append(ScreenplayElement(type: .pageBreak, text: ""))
            }
            var element = ScreenplayElement(
                type: ElementType(fdxParagraphType: paragraph.type),
                text: paragraph.text,
                externalIDs: paragraph.id.map { ["fdx_paragraph_id": $0] } ?? [:]
            )
            var styled = try StyledText(text: paragraph.text, runs: paragraph.runs)
            if capsTypes.contains(paragraph.type) {
                styled = try styled.replacingText(styled.text.uppercased())
            }
            element.setStyledText(styled)
            elements.append(element)
        }

        let screenplay = Screenplay(
            metadata: ScreenplayMetadata(title: title),
            elements: elements
        )
        let project = Project(
            metadata: ProjectMetadata(title: title, author: author),
            screenplayID: screenplay.id
        )

        var document = OpenScreenplayDocument(project: project, screenplay: screenplay)
        if elements.contains(where: { !($0.runs ?? []).isEmpty }) { document.formatVersion = "1.1" }
        let titleLines = titleParagraphs.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !titleLines.isEmpty {
            // Preserve arbitrary title-page wording separately, without guessing author/contact roles.
            document.titlePage = TitlePage(title: titleLines[0], subtitle: titleLines.dropFirst().joined(separator: "\n"))
            importWarnings.insert("Title-page text was kept separately; its layout and author/contact fields need review in Title Page.")
        }
        if !capsTypes.isEmpty {
            importWarnings.insert("Final Draft AllCaps element settings were applied to imported text.")
        }
        importWarnings.insert("Import uses ScreenplayOS page layout and fonts. Final Draft pagination, production metadata, and custom title-page layout are not reproduced.")
        return FDXImportResult(document: document,
            warnings: warnings(for: importedParagraphs) + importWarnings.sorted())
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        if elementStack.count == 1 {
            validRoot = elementName == "FinalDraft" && (attributeDict["DocumentType"] ?? "Script") == "Script"
        }
        if elementStack == ["FinalDraft", "Content"] { hasContent = true }
        if elementStack == ["FinalDraft", "ElementSettings"] { settingType = attributeDict["Type"] }
        if elementStack == ["FinalDraft", "ElementSettings", "FontSpec"],
           (attributeDict["Style"] ?? "").split(separator: "+").contains("AllCaps"), let settingType {
            capsTypes.insert(settingType)
        }
        let scriptParagraph = elementStack == ["FinalDraft", "Content", "Paragraph"]
        let titleParagraph = elementStack == ["FinalDraft", "TitlePage", "Content", "Paragraph"]
        let dualPath = ["FinalDraft", "Content", "Paragraph", "DualDialogue"]
        if elementName == "DualDialogue", elementStack.starts(with: ["FinalDraft", "Content"]), elementStack != dualPath {
            parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
        }
        let dualChild = elementStack == dualPath + ["Paragraph"]
        if elementStack.starts(with: dualPath),
           (elementStack.count == 5 && !["Paragraph", "SpellCheckIgnoreLists"].contains(elementName) ||
            elementStack.count == 6 && elementStack[4] == "Paragraph" && elementName != "Text") {
            parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
        }
        if elementStack == dualPath {
            guard !wrapperHasDualDialogue, let wrapper = currentParagraph, wrapper.text.isEmpty else {
                parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
            }
            wrapperHasDualDialogue = true
            hasDualDialogue = true
            dualWrapper = wrapper
            dualChildTypes = []
            currentParagraph = nil
            activeParagraphDepth = nil
        }
        if scriptParagraph || titleParagraph || dualChild {
            paragraphIsTitle = titleParagraph
            currentParagraph = FDXParagraph(type: attributeDict["Type"] ?? "General",
                id: attributeDict["id"], text: "", startsNewPage: attributeDict["StartsNewPage"] == "Yes")
            activeParagraphDepth = elementStack.count
            if dualChild {
                let type = attributeDict["Type"] ?? "General"
                guard ["Character", "Dialogue", "Parenthetical"].contains(type) else {
                    parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
                }
                if dualChildTypes.isEmpty, dualWrapper?.startsNewPage == true { currentParagraph?.startsNewPage = true }
                dualChildTypes.append(type)
            }
        } else if elementName == "Text", let depth = activeParagraphDepth, elementStack.count == depth + 1 {
            insideText = true
            activeTextDepth = elementStack.count
            currentText = ""
            let styles = Set((attributeDict["Style"] ?? "").split(separator: "+").map(String.init))
            textAllCaps = styles.contains("AllCaps")
            textStyle = StyledText.Style(bold: styles.contains("Bold") ? true : nil,
                italic: styles.contains("Italic") ? true : nil,
                underline: styles.contains("Underline") ? true : nil,
                strikethrough: styles.contains("Strikeout") ? true : nil)
            let unsupported = styles.subtracting(["Bold", "Italic", "Underline", "Strikeout", "Normal", "AllCaps"])
            if !paragraphIsTitle, !unsupported.isEmpty {
                importWarnings.insert("Unsupported text styles: " + unsupported.sorted().joined(separator: ", ") + ". Text was retained.")
            }
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
            if textAllCaps { currentText = currentText.uppercased() }
            if textStyle != StyledText.Style(), !currentText.isEmpty {
                let start = currentParagraph?.text.unicodeScalars.count ?? 0
                currentParagraph?.runs.append(StyledText.Run(start: start,
                    length: currentText.unicodeScalars.count, style: textStyle))
            }
            currentParagraph?.text += currentText
            insideText = false
            activeTextDepth = nil
            currentText = ""
        case "DualDialogue" where elementStack == ["FinalDraft", "Content", "Paragraph", "DualDialogue"]:
            // Each side must begin with a cue and contain dialogue. Unknown shapes fail closed.
            let cues = dualChildTypes.indices.filter { dualChildTypes[$0] == "Character" }
            guard cues.count == 2, cues.first == 0,
                  dualChildTypes[1..<cues[1]].contains("Dialogue"),
                  dualChildTypes[(cues[1] + 1)...].contains("Dialogue") else {
                parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
            }
            currentParagraph = dualWrapper
            activeParagraphDepth = 3
            dualWrapper = nil
        case "Paragraph" where activeParagraphDepth == elementStack.count:
            if wrapperHasDualDialogue, elementStack.count == 3 {
                guard currentParagraph?.text.isEmpty == true else {
                    parseError = FDXImportError.unsupportedDualDialogue; parser.abortParsing(); return
                }
                wrapperHasDualDialogue = false
            } else if let paragraph = currentParagraph {
                if paragraphIsTitle { titleParagraphs.append(paragraph) } else { paragraphs.append(paragraph) }
            }
            currentParagraph = nil
            activeParagraphDepth = nil
        default:
            break
        }

        _ = elementStack.popLast()
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil { self.parseError = parseError }
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
    var startsNewPage: Bool = false
    var runs: [StyledText.Run] = []
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
