import AppKit
import Testing
@testable import ScreenplayOSApp

@Suite("Retained natural wrapping")
@MainActor
struct NativeWrappingValidatorTests {
    @Test func changingBreakPoliciesMatchFreshLayoutAcrossEdits() {
        let source = NSTextStorage(string: String(repeating: "One two three four five six seven eight nine ten.\n", count: 12),
                                   attributes: [.font: NSFont(name: "Courier", size: 12)!])
        let manager = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: 180, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        source.addLayoutManager(manager); manager.addTextContainer(container)
        let retained = NativeWrappingValidator()
        func policy(_ variant: Int) -> NativeLineBreaks? {
            if variant == 0 { return nil }
            let text = source.string as NSString
            var ranges: [NSRange] = [], starts = Set<Int>()
            var offset = 0, index = 0
            while offset < text.length {
                let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
                if index % 3 == variant % 3 {
                    ranges.append(range); starts.insert(offset)
                    for point in offset..<NSMaxRange(range) where text.character(at: point) == 32 {
                        starts.insert(point + 1)
                    }
                    // Change allowed word breaks without changing paragraph ranges.
                    if variant > 3 { starts.remove(offset + 8) }
                }
                offset = NSMaxRange(range); index += 1
            }
            return NativeLineBreaks(starts: starts, paragraphs: ranges)
        }
        func check(_ changed: NSRange?, _ variant: Int) {
            let breaks = policy(variant)
            retained.update(from: source, changedRange: changed, container: container, manager: manager, lineBreaks: breaks)
            let fresh = NativeWrappingValidator()
            fresh.update(from: source, changedRange: nil, container: container, manager: manager, lineBreaks: breaks)
            #expect(retained.lineStarts() == fresh.lineStarts())
        }
        for variant in [0, 1, 4, 2, 0, 3] { check(nil, variant) }
        for iteration in 0..<30 {
            let offset = iteration % 2 == 0 ? 0 : source.length / 2
            let addition = iteration % 3 == 0 ? "New paragraph.\n" : "café "
            source.replaceCharacters(in: NSRange(location: offset, length: 0), with: addition)
            check(NSRange(location: offset, length: (addition as NSString).length), iteration % 5)
            source.replaceCharacters(in: NSRange(location: offset, length: (addition as NSString).length), with: "")
            check(NSRange(location: offset, length: 0), (iteration + 1) % 5)
        }
        container.containerSize.width = 240
        check(nil, 2)
        source.addAttribute(.font, value: NSFont(name: "Courier-Bold", size: 12)!, range: NSRange(location: 0, length: 80))
        check(NSRange(location: 0, length: 80), 4)
        source.setAttributedString(NSAttributedString(string: ""))
        check(NSRange(location: 0, length: 0), 0)
    }

    @Test func incrementalWrappingMatchesIndependentLayoutThroughEditsAndGeometryChanges() {
        let source = NSTextStorage(string: String(repeating: "A café 👩🏽‍🚀 waits by the road. ", count: 30) + "\nLast paragraph.\n",
                                   attributes: [.font: NSFont(name: "Courier", size: 12)!])
        let manager = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: 432, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        source.addLayoutManager(manager); manager.addTextContainer(container)
        let retained = NativeWrappingValidator()
        func freshStarts() -> Set<Int> {
            let copy = NSTextStorage(attributedString: source), layout = NSLayoutManager()
            let area = NSTextContainer(size: container.containerSize)
            area.lineFragmentPadding = container.lineFragmentPadding
            layout.usesFontLeading = manager.usesFontLeading
            layout.usesDefaultHyphenation = manager.usesDefaultHyphenation
            copy.addLayoutManager(layout); layout.addTextContainer(area)
            layout.ensureLayout(for: area)
            var result = Set<Int>()
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: area)) { _, _, _, range, _ in
                result.insert(layout.characterIndexForGlyph(at: range.location))
            }
            if copy.length == 0 || copy.string.hasSuffix("\n") { result.insert(copy.length) }
            return result
        }
        @MainActor func check(_ changed: NSRange?) {
            retained.update(from: source, changedRange: changed, container: container, manager: manager)
            #expect(retained.lineStarts() == freshStarts())
        }
        check(nil)
        for position in [0, source.length / 2, source.length] {
            let addition = " Another café 👩🏽‍🚀.\n"
            source.replaceCharacters(in: NSRange(location: position, length: 0), with: addition)
            check(NSRange(location: position, length: (addition as NSString).length))
        }
        source.replaceCharacters(in: NSRange(location: 0, length: 80), with: "Short.\n")
        check(NSRange(location: 0, length: 7))
        source.addAttribute(.font, value: NSFont(name: "Courier", size: 18)!, range: NSRange(location: 0, length: source.length))
        check(NSRange(location: 0, length: source.length))
        // Exercise cached suffix offsets through repeated paragraph splits, merges,
        // same-length replacements, and empty trailing paragraphs.
        for iteration in 0..<60 {
            let text = source.string as NSString
            let middle = text.length / 2
            let paragraph = text.paragraphRange(for: NSRange(location: middle, length: 0))
            let location = paragraph.location
            let addition = iteration % 3 == 0 ? "New line.\n" : "x"
            source.replaceCharacters(in: NSRange(location: location, length: 0), with: addition)
            check(NSRange(location: location, length: (addition as NSString).length))
            if iteration % 2 == 0 {
                source.replaceCharacters(in: NSRange(location: location, length: (addition as NSString).length), with: "")
                check(NSRange(location: location, length: 0))
            }
            #expect(retained.lineStarts() == freshStarts()) // Unchanged cached reads too.
        }
        container.containerSize.width = 280
        check(nil)
        // An unspecified update must also catch equal-length changes.
        source.replaceCharacters(in: NSRange(location: 0, length: 1), with: "\n")
        check(nil)
        source.replaceCharacters(in: NSRange(location: 0, length: source.length), with: "")
        check(NSRange(location: 0, length: 0))
    }
}
