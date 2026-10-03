import AppKit

/// Retains one natural (unpaged) TextKit layout for the current editor. The visible
/// text view must never be switched to natural coordinates just to validate wraps.
@MainActor
final class NativeWrappingValidator {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private var initialized = false

    init() {
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    func update(from source: NSTextStorage, changedRange: NSRange?, container sourceContainer: NSTextContainer,
                manager sourceManager: NSLayoutManager) {
        if container.containerSize != sourceContainer.containerSize { container.containerSize = sourceContainer.containerSize }
        if container.lineFragmentPadding != sourceContainer.lineFragmentPadding { container.lineFragmentPadding = sourceContainer.lineFragmentPadding }
        if manager.usesFontLeading != sourceManager.usesFontLeading { manager.usesFontLeading = sourceManager.usesFontLeading }
        if manager.usesDefaultHyphenation != sourceManager.usesDefaultHyphenation { manager.usesDefaultHyphenation = sourceManager.usesDefaultHyphenation }
        if initialized, let range = changedRange {
            // The supplied range describes the NEW rendered text, including native
            // typing that occurred before the coordinator's paragraph replacement.
            let oldLength = range.length - (source.length - storage.length)
            if oldLength >= 0 && range.location >= 0 && NSMaxRange(range) <= source.length && range.location + oldLength <= storage.length {
                storage.replaceCharacters(in: NSRange(location: range.location, length: oldLength),
                    with: source.attributedSubstring(from: range))
                return
            }
        } else if initialized && storage.isEqual(to: source) {
            return
        }
        storage.setAttributedString(source)
        initialized = true
    }

    func lineStarts() -> Set<Int> {
        manager.ensureLayout(for: container)
        var starts = Set<Int>()
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphs, _ in
            starts.insert(self.manager.characterIndexForGlyph(at: glyphs.location))
        }
        if storage.length == 0 || storage.string.hasSuffix("\n") { starts.insert(storage.length) }
        return starts
    }
}
