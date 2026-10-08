import Foundation
import ScreenplayDomain

/// Screenplay interchange only. Never serializes project planning or provider data.
public enum FDXExporter {
    public enum Failure: LocalizedError {
        case invalidXMLCharacter, unsupportedPageBreak
        public var errorDescription: String? {
            switch self {
            case .invalidXMLCharacter: return "The screenplay contains a character XML cannot represent. Export stopped without changing your document."
            case .unsupportedPageBreak: return "FDX export cannot safely represent consecutive or trailing page breaks, or a page break containing text. Remove them in a copy before exporting."
            }
        }
    }
    public struct Result {
        public let data: Data
        public let warnings: [String]
    }
    public static func export(elements: [ScreenplayElement], titlePage: TitlePage?) throws -> Result {
        var paragraphs: [String] = []
        var startsNewPage = false
        for element in elements {
            if element.type == .pageBreak {
                guard !startsNewPage, element.text.isEmpty else { throw Failure.unsupportedPageBreak }
                startsNewPage = true
                continue
            }
            let page = startsNewPage ? " StartsNewPage=\"Yes\"" : ""
            paragraphs.append("<Paragraph Type=\"\(name(element.type))\" id=\"\(element.id.uuidString)\"\(page)>\(try textNodes(element.styledText))</Paragraph>")
            startsNewPage = false
        }
        guard !startsNewPage else { throw Failure.unsupportedPageBreak }
        var title = ""
        if let titlePage {
            // Standard title-page paragraphs; do not invent private metadata to imply
            // lossless preservation of field roles or layout across other applications.
            var lines = [titlePage.title, titlePage.subtitle]
            if !titlePage.author.isEmpty { lines += ["Written by", titlePage.author] }
            lines += [titlePage.draftDate, titlePage.contact]
            let values = try lines.filter { !$0.isEmpty }.map {
                "<Paragraph Type=\"General\" Alignment=\"Center\"><Text Font=\"Courier\" Size=\"12\">\(try escaped($0))</Text></Paragraph>"
            }
            if !values.isEmpty { title = "<TitlePage><Content>" + values.joined(separator: "\n") + "</Content></TitlePage>" }
        }
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"6\">\n<Content>\n" + paragraphs.joined(separator: "\n") + "\n</Content>\n" + title + "\n</FinalDraft>\n"
        return Result(data: Data(xml.utf8), warnings: [
            "Exports screenplay text, paragraph types and bold/italic/underline/strikeout. Final Draft controls pagination and font layout; page locks, revision marks, notes, shots, boards and edit data are not transferred. Keep your native project.",
            "Title-page wording is exported separately. Its layout and author/contact field roles need review after reimport.",
            "Dual dialogue is not represented by the native editor. Previously imported dual speeches export sequentially; simultaneous delivery cannot be reconstructed."
        ])
    }
    private static func name(_ type: ElementType) -> String {
        switch type {
        case .sceneHeading: return "Scene Heading"
        case .action: return "Action"
        case .character: return "Character"
        case .dialogue: return "Dialogue"
        case .parenthetical: return "Parenthetical"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .general: return "General"
        case .pageBreak: return "Page Break"
        }
    }
    private static func textNodes(_ value: StyledText) throws -> String {
        let scalars = Array(value.text.unicodeScalars)
        func node(_ range: Range<Int>, _ style: StyledText.Style) throws -> String {
            let styles = [(style.bold, "Bold"), (style.italic, "Italic"), (style.underline, "Underline"), (style.strikethrough, "Strikeout")].compactMap { $0.0 == true ? $0.1 : nil }
            let attribute = styles.isEmpty ? "" : " Style=\"" + styles.joined(separator: "+") + "\""
            return "<Text\(attribute)>\(try escaped(String(String.UnicodeScalarView(scalars[range]))))</Text>"
        }
        var output = "", cursor = 0
        for run in value.resolvedRuns {
            if run.start > cursor { output += try node(cursor..<run.start, .init()) }
            output += try node(run.start..<(run.start + run.length), run.style)
            cursor = run.start + run.length
        }
        if cursor < scalars.count || output.isEmpty { output += try node(cursor..<scalars.count, .init()) }
        return output
    }
    private static func escaped(_ value: String) throws -> String {
        var output = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x26: output += "&amp;"
            case 0x3C: output += "&lt;"
            case 0x3E: output += "&gt;"
            case 0x22: output += "&quot;"
            case 0x27: output += "&apos;"
            case 0xD: output += "&#13;" // XML newline normalization must not alter authored text.
            case 0x9, 0xA, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                output.unicodeScalars.append(scalar)
            default: throw Failure.invalidXMLCharacter
            }
        }
        return output
    }
}
