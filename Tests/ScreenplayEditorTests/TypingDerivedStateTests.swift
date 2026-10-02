import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Typing derived state", .serialized)
@MainActor
struct TypingDerivedStateTests {
    @Test func cachedCoordinatesAndPrintMapsFollowEditsUndoAndTypography() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "DerivedState.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
            with: "INT. STRAßE - DAY\nZoë walks.\nZOE\nHello.\nLast action.")
        func verify() {
            #expect(model.writingText == model.elements.map(\.text).joined(separator: "\n"))
            var offset = 0
            for (element, range) in zip(model.elements, model.writingRanges) {
                #expect(range == NSRange(location: offset, length: (element.text as NSString).length))
                offset = NSMaxRange(range) + 1
            }
            let cached = model.printedLayout
            let fresh = ScriptPrintProjection(pages: cached.pages, source: model.elements,
                preservesWhitespace: model.printPreservesWhitespace, casing: model.screenplayCasing)
            #expect(cached.unmappedElementIDs == fresh.unmappedElementIDs)
            #expect(cached.pages.flatMap(\.elements).map(\.sourceSpan) == fresh.pages.flatMap(\.elements).map(\.sourceSpan))
            for page in cached.pages.indices { #expect(cached.firstSourceCaret(onPage: page) == fresh.firstSourceCaret(onPage: page)) }
        }
        verify()
        model.replaceWritingText(in: NSRange(location: 0, length: 0), with: "A new opening.\n")
        verify()
        model.undo(); verify()
        model.redo(); verify()
        model.changeWritingTypography(size: 18); verify()
        model.changeWritingTypography(size: 12); verify()
    }
    @Test func fontMenuReusesItemsAndDispatchesSelection() throws {
        _ = NSApplication.shared
        var chosen: String?
        let coordinator = FontFamilyPicker.Coordinator { chosen = $0 }
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        coordinator.button = button
        coordinator.refresh(selection: "Courier")
        let item = try #require(button.item(withTitle: "Courier"))
        coordinator.refresh(selection: "Courier")
        #expect(button.item(withTitle: "Courier") === item)
        coordinator.choose(button)
        #expect(chosen == "Courier")
    }
    @Test func casingFastPathsPreserveUnicode() {
        let text = "Straße 👩🏽‍💻 e\u{301}"
        #expect(ScreenplayCasing.render(text, ranges: []) == text)
        #expect(ScreenplayCasing.render(text, ranges: [NSRange(location: 0, length: (text as NSString).length)]) == text.uppercased())
    }
}
