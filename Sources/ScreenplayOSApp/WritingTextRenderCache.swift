import AppKit
import ScreenplayDomain

/// Retains only the current document's paragraph renderings. Native typing has already
/// changed NSTextStorage; account for that edit before replacing the affected paragraphs.
@MainActor
final class WritingTextRenderCache {
    @MainActor private final class Paragraph {
        let element: ScreenplayElement
        let displayed: String
        let attributed: NSAttributedString
        let typing: [NSAttributedString.Key: Any]

        init(element: ScreenplayElement, displayed: String, body: String, typography: DocumentTypography, dark: Bool) {
            self.element = element
            self.displayed = displayed
            var attributes: [NSAttributedString.Key: Any] = [
                .font: PackageTypography.font(typography),
                .foregroundColor: StudioAppearance.ink(dark),
                .paragraphStyle: ScreenplayBodyLayout.editorStyle(for: element.type, scale: 1)
            ]
            if let mark = element.revisionMark {
                attributes[.backgroundColor] = mark.color.nsColor.withAlphaComponent(0.15)
            }
            typing = attributes
            let value = NSMutableAttributedString(string: displayed, attributes: attributes)
            if element.runs != nil {
                PackageTypography.apply((try? element.styledText.replacingText(body)) ?? element.styledText,
                    settings: typography, to: value, offset: 0)
            }
            attributed = value
        }
    }

    private var paragraphs: [Paragraph] = []
    private var typography: DocumentTypography?
    private var dark: Bool?
    private(set) var lastReplacementRange: NSRange?

    func update(_ storage: NSTextStorage, elements: [ScreenplayElement], projection: ScreenplayWritingProjection,
                typography: DocumentTypography, dark: Bool, selectedID: UUID?, nativeEdit: NSRange?) -> [NSAttributedString.Key: Any] {
        let canReuse = self.typography == typography && self.dark == dark
        let byID = canReuse ? Dictionary(uniqueKeysWithValues: paragraphs.map { ($0.element.id, $0) }) : [:]
        let string = projection.text as NSString
        let next: [Paragraph] = elements.enumerated().map { index, element in
            var range = projection.ranges[index]
            if index + 1 < elements.count { range.length += 1 }
            let displayed = string.substring(with: range)
            if let previous = byID[element.id], previous.element == element, previous.displayed == displayed {
                return previous
            }
            return Paragraph(element: element, displayed: displayed, body: string.substring(with: projection.ranges[index]), typography: typography, dark: dark)
        }

        var prefix = 0, suffix = 0
        while prefix < min(paragraphs.count, next.count), paragraphs[prefix] === next[prefix] { prefix += 1 }
        while suffix < min(paragraphs.count, next.count) - prefix,
              paragraphs[paragraphs.count - 1 - suffix] === next[next.count - 1 - suffix] { suffix += 1 }
        let oldLength = paragraphs.reduce(0) { $0 + $1.attributed.length }
        let start = paragraphs.prefix(prefix).reduce(0) { $0 + $1.attributed.length }
        let end = oldLength - paragraphs.suffix(suffix).reduce(0) { $0 + $1.attributed.length }
        let delta = storage.length - oldLength
        let accountedFor = nativeEdit.map { $0.location >= start && NSMaxRange($0) <= end } ?? (delta == 0)
        lastReplacementRange = nil
        if accountedFor && end - start + delta >= 0 && end + delta <= storage.length {
            let replacement = NSMutableAttributedString(string: "")
            for paragraph in next[prefix..<(next.count - suffix)] { replacement.append(paragraph.attributed) }
            let range = NSRange(location: start, length: end - start + delta)
            if range.length > 0 || replacement.length > 0 {
                storage.replaceCharacters(in: range, with: replacement)
                lastReplacementRange = range
            }
        } else {
            // Unexpected native changes (including marked-text reconciliation) get a safe full render.
            let replacement = NSMutableAttributedString(string: "")
            for paragraph in next { replacement.append(paragraph.attributed) }
            lastReplacementRange = NSRange(location: 0, length: storage.length)
            storage.setAttributedString(replacement)
        }
        paragraphs = next
        self.typography = typography
        self.dark = dark
        return next.first(where: { $0.element.id == selectedID })?.typing ?? [:]
    }
}
