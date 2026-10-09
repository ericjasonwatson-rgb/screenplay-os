import AppKit

/// Retains an unpaged TextKit layout with the editor's same break policy. The visible
/// text view must never be switched to natural coordinates just to validate wraps.
@MainActor
// This private layout manager is owned and driven on the main actor. AppKit
// exposes its Objective-C delegate requirements without actor annotations.
final class NativeWrappingValidator: NSObject, @preconcurrency NSLayoutManagerDelegate {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private var lineBreaks: NativeLineBreaks?
    private var initialized = false
    private var cachedStarts: Set<Int>?
    private var dirtyParagraphs: NSRange?

    override init() {
        super.init()
        manager.delegate = self
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    func update(from source: NSTextStorage, changedRange: NSRange?, container sourceContainer: NSTextContainer,
                manager sourceManager: NSLayoutManager, lineBreaks: NativeLineBreaks? = nil) {
        let changedBreakStart = NativeLineBreaks.firstChange(from: self.lineBreaks, to: lineBreaks)
        self.lineBreaks = lineBreaks
        let geometryChanged = container.containerSize != sourceContainer.containerSize ||
            container.lineFragmentPadding != sourceContainer.lineFragmentPadding ||
            manager.usesFontLeading != sourceManager.usesFontLeading ||
            manager.usesDefaultHyphenation != sourceManager.usesDefaultHyphenation
        if geometryChanged { cachedStarts = nil; dirtyParagraphs = nil }
        if container.containerSize != sourceContainer.containerSize { container.containerSize = sourceContainer.containerSize }
        if container.lineFragmentPadding != sourceContainer.lineFragmentPadding { container.lineFragmentPadding = sourceContainer.lineFragmentPadding }
        if manager.usesFontLeading != sourceManager.usesFontLeading { manager.usesFontLeading = sourceManager.usesFontLeading }
        if manager.usesDefaultHyphenation != sourceManager.usesDefaultHyphenation { manager.usesDefaultHyphenation = sourceManager.usesDefaultHyphenation }
        if initialized, let range = changedRange {
            // The supplied range describes the NEW rendered text, including native
            // typing that occurred before the coordinator's paragraph replacement.
            let oldLength = range.length - (source.length - storage.length)
            if oldLength >= 0 && range.location >= 0 && NSMaxRange(range) <= source.length && range.location + oldLength <= storage.length {
                let oldRange = NSRange(location: range.location, length: oldLength)
                let oldParagraphs = (storage.string as NSString).paragraphRange(for: oldRange)
                let newParagraphs = (source.string as NSString).paragraphRange(for: range)
                let delta = source.length - storage.length
                if let starts = cachedStarts, dirtyParagraphs == nil,
                   oldParagraphs.location == newParagraphs.location,
                   NSMaxRange(oldParagraphs) + delta == NSMaxRange(newParagraphs) {
                    cachedStarts = Set(starts.compactMap { offset in
                        if offset < oldParagraphs.location { return offset }
                        if offset >= NSMaxRange(oldParagraphs) { return offset + delta }
                        return nil
                    })
                    dirtyParagraphs = newParagraphs
                } else { cachedStarts = nil; dirtyParagraphs = nil }
                storage.replaceCharacters(in: oldRange,
                    with: source.attributedSubstring(from: range))
                if let changedBreakStart { invalidateBreaks(from: min(changedBreakStart, newParagraphs.location)) }
                return
            }
        } else if initialized && storage.isEqual(to: source) {
            if let changedBreakStart { invalidateBreaks(from: changedBreakStart) }
            return
        }
        cachedStarts = nil; dirtyParagraphs = nil
        storage.setAttributedString(source)
        initialized = true
    }

    private func invalidateBreaks(from offset: Int) {
        let start = min(max(0, min(offset, dirtyParagraphs?.location ?? offset)), storage.length)
        let range = NSRange(location: start, length: storage.length - start)
        if let cachedStarts {
            self.cachedStarts = Set(cachedStarts.filter { $0 < start })
            dirtyParagraphs = range
        }
        manager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    func layoutManager(_ manager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt index: Int) -> Bool {
        lineBreaks?.allows(index) ?? true
    }

    func layoutManager(_ manager: NSLayoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt index: Int) -> Bool {
        lineBreaks?.allows(index) ?? true
    }

    func lineStarts() -> Set<Int> {
        if let cachedStarts, dirtyParagraphs == nil { return cachedStarts }
        var starts: Set<Int>
        let glyphs: NSRange
        if let cached = cachedStarts, let dirty = dirtyParagraphs {
            starts = cached
            manager.ensureLayout(forCharacterRange: dirty)
            glyphs = manager.glyphRange(forCharacterRange: dirty, actualCharacterRange: nil)
        } else {
            starts = []
            manager.ensureLayout(for: container)
            glyphs = manager.glyphRange(for: container)
        }
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, line, _ in
            starts.insert(self.manager.characterIndexForGlyph(at: line.location))
        }
        if storage.length == 0 || storage.string.hasSuffix("\n") { starts.insert(storage.length) }
        else { starts.remove(storage.length) }
        cachedStarts = starts; dirtyParagraphs = nil
        return starts
    }
}
