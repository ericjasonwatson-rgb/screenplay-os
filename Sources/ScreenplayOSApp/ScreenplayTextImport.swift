import AppKit
import PDFKit
import ScreenplayDomain

enum ScreenplayTextImport {
    struct Extraction {
        var pages: [String]
        var notice: String
        var text: String { pages.joined(separator: "\n\n— Page break —\n\n") }
    }
    enum Failure: LocalizedError {
        case unsupported, tooLarge, unreadable, noText, locked, scannedPages
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Choose a DOCX, PDF, or plain-text file."
            case .tooLarge: return "This file exceeds the import limit (20 MB or 500,000 text characters)."
            case .unreadable: return "The document could not be read. Text files must use UTF-8 or BOM-marked UTF-16."
            case .noText: return "No readable text was found. A scanned PDF needs OCR before import."
            case .locked: return "Unlock this PDF before importing it."
            case .scannedPages: return "Some PDF pages have no extractable text. OCR or review those pages first; a partial script was not imported."
            }
        }
    }

    @MainActor static func extract(_ url: URL) throws -> Extraction {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else { throw Failure.tooLarge }
        let data = try Data(contentsOf: url)
        let result: Extraction
        switch url.pathExtension.lowercased() {
        case "txt", "text", "fountain":
            let text: String?
            if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
                text = String(data: data, encoding: .utf16)
            } else {
                let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? Data(data.dropFirst(3)) : data
                text = String(data: bytes, encoding: .utf8)
            }
            guard let text else { throw Failure.unreadable }
            if url.pathExtension.lowercased() == "fountain" {
                result = Extraction(pages: [text], notice: "Fountain markup is not interpreted yet: the file was imported as plain text. Title-page keys, forced elements (!, @, .), [[notes]], /* boneyard */, emphasis markers, and ^ dual dialogue appear as literal text. Review element roles before saving; the original file is unchanged.")
            } else {
                result = Extraction(pages: [text], notice: "Plain text imported. Screenplay roles are not encoded in this format.")
            }
        case "docx":
            let attributed = try NSAttributedString(data: data,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
            result = Extraction(pages: [attributed.string], notice: "DOCX text extracted. Fonts, emphasis, images, comments, and page layout are not imported. Check tables and text boxes in the preview.")
        case "pdf":
            guard let pdf = PDFDocument(data: data) else { throw Failure.unreadable }
            guard !pdf.isLocked else { throw Failure.locked }
            guard pdf.pageCount <= 1_000 else { throw Failure.tooLarge }
            let pages = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
            let empty = pages.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            guard empty < pages.count else { throw Failure.noText }
            guard empty == 0 else { throw Failure.scannedPages }
            result = Extraction(pages: pages, notice: "PDF text extracted from \(pages.count) pages. Reading order, headers, line wrapping, and role detection need review. Page boundaries are retained; typography and images are not imported. No OCR was performed.")
        default: throw Failure.unsupported
        }
        guard result.pages.reduce(0, { $0 + $1.count }) <= 500_000 else { throw Failure.tooLarge }
        guard result.pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw Failure.noText }
        return result
    }

    static func document(_ extraction: Extraction, title: String, detectStructure: Bool) -> ScreenplayOSDocument {
        var elements: [ScreenplayElement] = []
        for (pageIndex, page) in extraction.pages.enumerated() {
            if pageIndex > 0 { elements.append(ScreenplayElement(type: .pageBreak, text: "")) }
            let lines = page.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
            var dialogue = false
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                var type: ElementType = .general
                if detectStructure {
                    let upper = trimmed.uppercased()
                    if trimmed.isEmpty { dialogue = false }
                    else if ["INT.", "EXT.", "INT/EXT.", "INT./EXT.", "I/E."].contains(where: { upper.hasPrefix($0) }) {
                        type = .sceneHeading; dialogue = false
                    } else if ["CUT TO:", "FADE OUT.", "FADE IN:", "DISSOLVE TO:"].contains(upper) {
                        type = .transition; dialogue = false
                    } else if dialogue, trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
                        type = .parenthetical
                    } else if dialogue { type = .dialogue }
                    else if trimmed == upper, trimmed.count <= 40,
                            trimmed.rangeOfCharacter(from: .letters) != nil,
                            index + 1 < lines.count, !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty,
                            (index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty) {
                        type = .character; dialogue = true
                    } else { type = .action }
                }
                elements.append(ScreenplayElement(type: type, text: line))
            }
        }
        let script = Screenplay(metadata: ScreenplayMetadata(title: title), elements: elements)
        return ScreenplayOSDocument(project: Project(metadata: ProjectMetadata(title: title, author: ""), screenplayID: script.id), screenplay: script)
    }
}
