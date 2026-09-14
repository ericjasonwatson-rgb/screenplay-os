import AppKit
import PDFKit
import ScreenplayDomain

/// Derived, un-locked US Letter output. Never transforms or writes source content.
@MainActor
enum PackagePrintLayout {
    struct Result {
        let data: Data
        let characterRanges: [NSRange]
        let text: String
    }
    static func make(_ session: PackageTextSession) throws -> Result {
        let projection = PackageWritingProjection(session)
        let attributed = NSMutableAttributedString(string: projection.text)
        let font = NSFont(name: "Courier", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for entry in projection.entries {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = 14
            style.paragraphSpacing = 12
            switch entry.type {
            case "character": style.firstLineHeadIndent = 144; style.headIndent = 144; style.paragraphSpacing = 0
            case "dialogue": style.firstLineHeadIndent = 72; style.headIndent = 72; style.tailIndent = -108; style.paragraphSpacing = 0
            case "parenthetical": style.firstLineHeadIndent = 108; style.headIndent = 108; style.tailIndent = -144; style.paragraphSpacing = 0
            case "transition": style.alignment = .right
            default: break
            }
            let range = NSRange(location: entry.range.location, length: entry.range.length + (NSMaxRange(entry.range) < attributed.length ? 1 : 0))
            attributed.addAttributes([.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style], range: range)
        }
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var ranges: [NSRange] = [], glyphRanges: [NSRange] = []
        var previousEnd = 0
        repeat {
            let container = NSTextContainer(containerSize: NSSize(width: 432, height: 648))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            var glyphs = layout.glyphRange(for: container)
            // Keep an ending heading/cue/parenthetical with at least the first line
            // of its following paragraph. Oversized blocks still make forward progress.
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            if let index = projection.entries.indices.last(where: { index in
                let entry = projection.entries[index]
                guard ["scene_heading", "character", "parenthetical"].contains(entry.type),
                      index + 1 < projection.entries.count,
                      entry.range.location > characters.location,
                      entry.range.location < NSMaxRange(characters) else { return false }
                return projection.entries[index + 1].range.location >= NSMaxRange(characters)
            }) {
                // Include a preceding cue when the stranded paragraph is parenthetical.
                var first = index
                while first > 0, ["character", "scene_heading"].contains(projection.entries[first - 1].type),
                      projection.entries[first - 1].range.location > characters.location { first -= 1 }
                let glyph = layout.glyphIndexForCharacter(at: projection.entries[first].range.location)
                let y = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                if y > 0 {
                    container.containerSize.height = y
                    layout.ensureLayout(for: container)
                    glyphs = layout.glyphRange(for: container)
                }
            }
            glyphRanges.append(glyphs)
            ranges.append(layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
            let end = NSMaxRange(glyphs)
            if end >= layout.numberOfGlyphs { break }
            guard end > previousEnd, ranges.count < 10_000 else { throw PrintPDFError.renderFailed }
            previousEnd = end
        } while true
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw PrintPDFError.renderFailed }
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw PrintPDFError.renderFailed }
        for (index, range) in glyphRanges.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: 792); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            // TextKit containers each have a local origin; page margins are added here.
            layout.drawGlyphs(forGlyphRange: range, at: NSPoint(x: 108, y: 72))
            ("\(index + 1)." as NSString).draw(at: NSPoint(x: 516, y: 36), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState(); context.endPDFPage()
        }
        context.closePDF()
        guard let pdf = PDFDocument(data: data as Data), pdf.pageCount == ranges.count else { throw PrintPDFError.renderFailed }
        return Result(data: data as Data, characterRanges: ranges, text: projection.text)
    }
}
