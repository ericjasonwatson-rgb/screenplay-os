import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Incremental native text rendering")
@MainActor
struct WritingTextRenderCacheTests {
    @Test func nativeEditsAndStructuralChangesMatchFreshAttributes() throws {
        var elements = [ScreenplayElement(type: .sceneHeading, text: "int. straße - day"),
            ScreenplayElement(type: .action, text: "A café 👩🏽‍🚀."),
            ScreenplayElement(type: .dialogue, text: "A final sentence.")]
        let cache = WritingTextRenderCache(), storage = NSTextStorage()
        let typography = try DocumentTypography()
        @MainActor func render(_ native: NSRange? = nil, dark: Bool = false) {
            let projection = ScreenplayWritingProjection(elements: elements)
            _ = cache.update(storage, elements: elements, projection: projection, typography: typography,
                             dark: dark, selectedID: elements.last?.id, nativeEdit: native)
            let fresh = NSTextStorage()
            _ = WritingTextRenderCache().update(fresh, elements: elements, projection: projection,
                typography: typography, dark: dark, selectedID: elements.last?.id, nativeEdit: nil)
            #expect(storage.isEqual(to: fresh))
            #expect(storage.string == projection.text)
        }
        render()
        render()
        #expect(cache.lastReplacementRange == nil)
        let insert = NSRange(location: storage.length, length: 0)
        storage.replaceCharacters(in: insert, with: " More.")
        elements[2].text += " More."
        render(insert)
        #expect(cache.lastReplacementRange?.location == ScreenplayWritingProjection(elements: elements).ranges[2].location)
        // Same-text cross-paragraph paste can overwrite paragraph attributes.
        let paste = NSRange(location: 2, length: storage.length - 3)
        let same = (storage.string as NSString).substring(with: paste)
        storage.replaceCharacters(in: paste, with: NSAttributedString(string: same))
        render(paste)
        elements.remove(at: 1)
        render()
        elements.insert(ScreenplayElement(type: .character, text: "Alice (v.o.)"), at: 1)
        render()
        render(dark: true)
        // Changing an earlier introduction must invalidate an unchanged later action.
        elements = [ScreenplayElement(type: .character, text: "Alice"),
                    ScreenplayElement(type: .action, text: "Alice arrives."),
                    ScreenplayElement(type: .action, text: "Alice leaves.")]
        render()
        elements[1].text = "Someone arrives."
        render()
        #expect(storage.string.contains("ALICE leaves."))
        // An unchanged final paragraph gains/loses its newline when structure changes.
        elements.append(ScreenplayElement(type: .action, text: "The end."))
        render()
        elements.removeLast()
        render()
        elements = []
        render()
    }
}
