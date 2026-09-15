import AppKit
import PDFKit
import ScreenplayDomain

/// Derived, un-locked US Letter output. Never transforms or writes source content.
@MainActor
enum PackagePrintLayout {
    struct Result {
        let data: Data
        let characterRanges: [NSRange]
        let lineCharacterRanges: [NSRange]
        let text: String
    }
    struct Plan {
        let storage: NSTextStorage
        let layout: NSLayoutManager
        let text: String
        let font: NSFont
        let ranges: [NSRange]
        let glyphRanges: [NSRange]
        let headers: [String?]
        let headerHeights: [CGFloat]
        let footers: [Bool]
        let typography: DocumentTypography
        let relayoutStart: Int
    }
    // Reuse consumes the editor-owned layout cache; callers needing a snapshot use a fresh plan.
    static func plan(_ session: PackageTextSession, reusing previous: Plan? = nil) throws -> Plan {
        let measurementStart = Date()
        let projection = PackageWritingProjection(session)
        let attributed = NSMutableAttributedString(string: projection.text)
        let font = PackageTypography.font(session.typography)
        for entry in projection.entries {
            let style = PackagePageGeometry.paragraphStyle(for: entry.type)
            let range = NSRange(location: entry.range.location, length: entry.range.length + (NSMaxRange(entry.range) < attributed.length ? 1 : 0))
            attributed.addAttributes([.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style], range: range)
        }
        for entry in projection.entries {
            PackageTypography.apply(try session.styledText(for: entry.id), settings: session.typography, to: attributed, offset: entry.range.location)
        }
        let measurementAttributed = Date()
        var replacement: (old: NSRange, new: NSRange)?
        var keptPages = 0
        var relayoutStart = 0
        if let previous, previous.typography == session.typography, previous.text != projection.text,
           previous.storage.string.unicodeScalars.elementsEqual(previous.text.unicodeScalars) {
            let old = Array(previous.text.utf16), new = Array(projection.text.utf16)
            var common = 0
            while common < min(old.count, new.count), old[common] == new[common] { common += 1 }
            // Step back to a complete Unicode boundary before inspecting attributes.
            while common > 0, Range(NSRange(location: 0, length: common), in: projection.text) == nil || Range(NSRange(location: 0, length: common), in: previous.text) == nil { common -= 1 }
            let prefix = NSRange(location: 0, length: common)
            let prefixMatches = attributed.attributedSubstring(from: prefix).isEqual(to: previous.storage.attributedSubstring(from: prefix))
            if prefixMatches,
               let page = previous.ranges.lastIndex(where: { $0.location < common }) {
                // Reconsider the preceding page as well: keep-with-next and continuation
                // rules can pull text back across the boundary before the edit.
                keptPages = max(0, page - 1)
                relayoutStart = previous.ranges[keptPages].location
            }
            // Keep TextKit's containers and replace only the changed attributed span.
            // It can then reuse following layout when line wrapping converges.
            if prefixMatches {
                var suffix = 0
                while suffix < min(old.count, new.count) - common,
                      old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
                while suffix > 0,
                      Range(NSRange(location: new.count - suffix, length: suffix), in: projection.text) == nil ||
                      Range(NSRange(location: old.count - suffix, length: suffix), in: previous.text) == nil { suffix -= 1 }
                if !attributed.attributedSubstring(from: NSRange(location: new.count - suffix, length: suffix)).isEqual(
                    to: previous.storage.attributedSubstring(from: NSRange(location: old.count - suffix, length: suffix))) { suffix = 0 }
                replacement = (NSRange(location: common, length: old.count - common - suffix),
                               NSRange(location: common, length: new.count - common - suffix))
            }
        }
        let storage: NSTextStorage, layout: NSLayoutManager
        if let replacement, let previous {
            storage = previous.storage; layout = previous.layout
            storage.replaceCharacters(in: replacement.old, with: attributed.attributedSubstring(from: replacement.new))
        } else {
            keptPages = 0; relayoutStart = 0
            storage = NSTextStorage(attributedString: attributed)
            layout = NSLayoutManager(); storage.addLayoutManager(layout)
        }
        let measurementLayout = Date()
        // A continuation belongs only to an uninterrupted cue/dialogue/parenthetical
        // block. Never invent a speaker for un-cued dialogue or cross an action/heading.
        var owners: [Int?] = [], owner: Int?
        for (index, entry) in projection.entries.enumerated() {
            if entry.type == "character" { owner = entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : index }
            else if !["dialogue", "parenthetical"].contains(entry.type) { owner = nil }
            owners.append(owner)
        }
        func continuation(at offset: Int) -> String? {
            guard offset > 0, offset < attributed.length,
                  let left = projection.entries.lastIndex(where: { $0.range.location < offset }),
                  let right = projection.entries.lastIndex(where: { $0.range.location <= offset }),
                  let cue = owners[left], owners[right] == cue,
                  ["dialogue", "parenthetical"].contains(projection.entries[left].type),
                  ["dialogue", "parenthetical"].contains(projection.entries[right].type) else { return nil }
            return projection.entries[cue].text
        }
        func continuedCue(_ cue: String) -> String {
            if cue.hasSuffix("(CONT’D)") || cue.hasSuffix("(CONT'D)") { return cue }
            return cue + " (CONT’D)"
        }
        // Measure each split dialogue once at the same width, independently of page
        // height. This includes soft wraps and authored line breaks without editing text.
        var dialogueLines: [Int: [Int]] = [:]
        func lineStarts(for index: Int) -> [Int] {
            if let cached = dialogueLines[index] { return cached }
            let entry = projection.entries[index]
            let sample = NSTextStorage(attributedString: attributed.attributedSubstring(from: entry.range))
            let measuring = NSLayoutManager()
            sample.addLayoutManager(measuring)
            let area = NSTextContainer(containerSize: NSSize(width: PackagePageGeometry.textWidth, height: CGFloat.greatestFiniteMagnitude))
            area.lineFragmentPadding = 0
            measuring.addTextContainer(area)
            measuring.ensureLayout(for: area)
            var starts: [Int] = []
            measuring.enumerateLineFragments(forGlyphRange: measuring.glyphRange(for: area)) { _, _, _, range, _ in
                starts.append(entry.range.location + measuring.characterIndexForGlyph(at: range.location))
            }
            dialogueLines[index] = starts
            return starts
        }
        var ranges = Array(previous?.ranges.prefix(keptPages) ?? [])
        var glyphRanges = Array(previous?.glyphRanges.prefix(keptPages) ?? [])
        var headers = Array(previous?.headers.prefix(keptPages) ?? [])
        var headerHeights = Array(previous?.headerHeights.prefix(keptPages) ?? [])
        var footers = Array(previous?.footers.prefix(keptPages) ?? [])
        var previousEnd = glyphRanges.last.map(NSMaxRange) ?? 0
        var incoming: String? = keptPages > 0 ? continuation(at: relayoutStart) : nil
        repeat {
            let header = incoming.map(continuedCue)
            let headerHeight: CGFloat = header.map {
                ceil(($0 as NSString).boundingRect(with: NSSize(width: 288, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height) + 8
            } ?? 0
            guard headerHeight < 500 else { throw PrintPDFError.renderFailed }
            let size = NSSize(width: PackagePageGeometry.textWidth, height: PackagePageGeometry.textHeight - headerHeight)
            let container: NSTextContainer
            if ranges.count < layout.textContainers.count {
                container = layout.textContainers[ranges.count]
                if container.containerSize != size { container.containerSize = size }
            } else {
                container = NSTextContainer(containerSize: size)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
            }
            layout.ensureLayout(for: container)
            var glyphs = layout.glyphRange(for: container)
            func keepGroups() {
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
            }
            keepGroups()
            var chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            if continuation(at: NSMaxRange(chars)) != nil {
                // Reserve a real line for MORE before deciding the final page boundary.
                container.containerSize.height = min(container.containerSize.height, PackagePageGeometry.textHeight - headerHeight - 24)
                layout.ensureLayout(for: container)
                glyphs = layout.glyphRange(for: container)
                keepGroups()
                chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            }
            let boundary = NSMaxRange(chars)
            if let index = projection.entries.lastIndex(where: { $0.range.location < boundary }),
               projection.entries[index].type == "dialogue",
               boundary < NSMaxRange(projection.entries[index].range) {
                let starts = lineStarts(for: index)
                let onPage = starts.filter { $0 >= chars.location && $0 < boundary }
                let remaining = starts.filter { $0 >= boundary }
                var moveFrom: Int?
                if onPage.count < 2 {
                    moveFrom = onPage.first
                } else if remaining.count == 1 {
                    // Move one line back unless that would strand a line here; in
                    // that case move the short paragraph together with its cue.
                    moveFrom = onPage.count == 2 ? onPage.first : onPage.last
                }
                if let moveFrom, moveFrom > chars.location {
                    let glyph = layout.glyphIndexForCharacter(at: moveFrom)
                    let y = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                    if y > 0 {
                        container.containerSize.height = y
                        layout.ensureLayout(for: container)
                        glyphs = layout.glyphRange(for: container)
                        keepGroups()
                        chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                    }
                }
            }
            incoming = continuation(at: NSMaxRange(chars))
            headers.append(header); headerHeights.append(headerHeight); footers.append(incoming != nil)
            glyphRanges.append(glyphs); ranges.append(chars)
            let end = NSMaxRange(glyphs)
            if end >= layout.numberOfGlyphs { break }
            guard end > previousEnd, ranges.count < 10_000 else { throw PrintPDFError.renderFailed }
            previousEnd = end
        } while true
        while layout.textContainers.count > ranges.count { layout.removeTextContainer(at: layout.textContainers.count - 1) }
        if ProcessInfo.processInfo.environment["PACKAGE_BENCHMARK"] == "1" {
            print("PLAN_MS attributed=\(measurementAttributed.timeIntervalSince(measurementStart) * 1000) setup=\(measurementLayout.timeIntervalSince(measurementAttributed) * 1000) pages=\(Date().timeIntervalSince(measurementLayout) * 1000)")
        }
        return Plan(storage: storage, layout: layout, text: projection.text, font: font, ranges: ranges,
                    glyphRanges: glyphRanges, headers: headers, headerHeights: headerHeights, footers: footers, typography: session.typography, relayoutStart: relayoutStart)
    }
    static func make(_ session: PackageTextSession) throws -> Result {
        let plan = try plan(session)
        let layout = plan.layout, font = plan.font, ranges = plan.ranges, glyphRanges = plan.glyphRanges
        let headers = plan.headers, headerHeights = plan.headerHeights, footers = plan.footers
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw PrintPDFError.renderFailed }
        var media = CGRect(x: 0, y: 0, width: PackagePageGeometry.width, height: PackagePageGeometry.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw PrintPDFError.renderFailed }
        for (index, range) in glyphRanges.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: 792); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            // TextKit containers each have a local origin; page margins are added here.
            if let header = headers[index] {
                (header as NSString).draw(with: NSRect(x: 252, y: 72, width: 288, height: headerHeights[index]),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .foregroundColor: NSColor.black])
            }
            layout.drawGlyphs(forGlyphRange: range, at: NSPoint(x: PackagePageGeometry.left, y: PackagePageGeometry.top + headerHeights[index]))
            if footers[index] {
                ("(MORE)" as NSString).draw(at: NSPoint(x: 252, y: 700), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            }
            ("\(index + 1)." as NSString).draw(at: NSPoint(x: 516, y: 36), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState(); context.endPDFPage()
        }
        context.closePDF()
        guard let pdf = PDFDocument(data: data as Data), pdf.pageCount == ranges.count else { throw PrintPDFError.renderFailed }
        var lines: [NSRange] = []
        for glyphRange in glyphRanges {
            layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, range, _ in
                lines.append(layout.characterRange(forGlyphRange: range, actualGlyphRange: nil))
            }
        }
        return Result(data: data as Data, characterRanges: ranges, lineCharacterRanges: lines, text: plan.text)
    }
}
