import AppKit
import PDFKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Legacy formatting", .serialized) @MainActor
struct LegacyFormattingTests {
    private func withModel(_ body: @MainActor (ScreenplayViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "LegacyFormatting.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root, preferences: defaults)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length), with: "INT. ROOM - DAY\nA café 👩🏽‍🚀 waits.\nAnother action.")
        await Task.yield()
        try await body(model)
        await Task.yield()
    }
    private func creativeState(_ document: ScreenplayOSDocument?) throws -> Data {
        let value = try #require(document)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder.screenplayOSEncoder().encode(value)) as! [String: Any]
        var project = json["project"] as! [String: Any]
        var metadata = project["metadata"] as! [String: Any]
        metadata.removeValue(forKey: "modified_at")
        project["metadata"] = metadata; json["project"] = project
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
    @Test func stylesTypographySaveReopenAndUndoPreserveDocument() async throws {
        try await withModel { model in
            let original = try #require(model.document)
            #expect(original.typography == nil && original.formatVersion == "1.0")
            let range = model.writingRanges[1]
            model.rememberDocumentCaret(range)
            model.toggleWritingEmphasis(\.bold)
            model.toggleWritingEmphasis(\.italic)
            model.toggleWritingEmphasis(\.underline)
            model.changeWritingTypography(font: "Helvetica", size: 16)
            let formatted = try #require(model.document)
            #expect(formatted.formatVersion == "1.1")
            #expect(formatted.screenplay.elements.map(\.id) == original.screenplay.elements.map(\.id))
            #expect(formatted.typography?.fontSize == 16)
            #expect(model.writingEmphasisActive(\.bold) && model.writingEmphasisActive(\.italic) && model.writingEmphasisActive(\.underline))
            let url = try #require(model.saveURL)
            let saved = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: Data(contentsOf: url))
            #expect(try creativeState(saved) == creativeState(formatted))
            for _ in 0..<4 { model.undo(); await Task.yield() }
            #expect(try creativeState(model.document) == creativeState(original))
            for _ in 0..<4 { model.redo(); await Task.yield() }
            #expect(try creativeState(model.document) == creativeState(formatted))
            model.loadScreenplayOSDocument(at: url)
            #expect(try creativeState(model.document) == creativeState(formatted))
        }
    }
    @Test func repeatedTextExactInsertionSplitJoinAndCrossParagraphUndo() async throws {
        try await withModel { model in
            let range = model.writingRanges[1]
            model.replaceWritingText(in: range, with: "aaaa")
            model.rememberDocumentCaret(NSRange(location: range.location, length: 1))
            model.toggleWritingEmphasis(\.bold)
            let baseline = try creativeState(model.document)
            model.rememberDocumentCaret(NSRange(location: range.location, length: 0))
            model.formatWritingSelection(.init(bold: false))
            model.replaceWritingText(in: NSRange(location: range.location, length: 0), with: "a")
            #expect(model.elements[1].runs?.first?.start == 1)
            model.undo(); #expect(try creativeState(model.document) == baseline)
            let id = model.elements[1].id
            model.splitElement(id, at: 1)
            #expect(model.elements[1].runs?.first?.length == 1)
            #expect(model.elements[2].runs == nil)
            #expect(model.mergeElementWithPrevious(model.elements[2].id))
            #expect(model.elements[1].runs?.first?.length == 1)
            model.undo(); model.undo(); #expect(try creativeState(model.document) == baseline)
            let from = model.writingRanges[1].location + 1, to = model.writingRanges[2].location + 3
            model.replaceWritingText(in: NSRange(location: from, length: to - from), with: "x\n👩🏽‍🚀")
            #expect(model.elements[1].runs?.first?.start == 0)
            model.undo(); #expect(try creativeState(model.document) == baseline)
            model.selectElement(id: model.elements[0].id)
            model.duplicateSelectedScene()
            #expect(model.elements.count == 6)
            #expect(model.elements[4].runs == model.elements[1].runs)
            #expect(model.elements[4].id != model.elements[1].id)
        }
    }
    @Test func defaultCourierMatchesPDFAndZoomDoesNotChangeDocument() async throws {
        try await withModel { model in
            let original = try creativeState(model.document)
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            @MainActor func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for zoom in [1.0, 2.0] {
                model.pageZoom = zoom
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let text = try #require(find(host))
                for range in model.writingRanges.prefix(2) {
                    let font = try #require(text.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                    #expect(font.familyName == "Courier" && font.pointSize == 12)
                    #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
                }
                let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
                let page = try #require(pdf.page(at: 1)?.attributedString)
                let heading = (page.string as NSString).range(of: "INT. ROOM - DAY")
                #expect(heading.location != NSNotFound)
                if heading.location != NSNotFound {
                    let font = try #require(page.attribute(.font, at: heading.location, effectiveRange: nil) as? NSFont)
                    #expect(font.familyName == "Courier" && abs(font.pointSize - 12) < 0.01)
                    #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
                }
                #expect(try creativeState(model.document) == original)
                #expect(model.document?.typography == nil && model.document?.formatVersion == "1.0")
            }
        }
    }
    @Test func nativeStylesSelectionAndTypingAgreeWithSavedRuns() async throws {
        try await withModel { model in
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func refresh() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            @MainActor func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            refresh()
            let text = try #require(find(host)), range = model.writingRanges[1]
            text.setSelectedRange(range); model.rememberDocumentCaret(range)
            model.toggleWritingEmphasis(\.underline); model.changeWritingTypography(font: "Helvetica", size: 16); refresh()
            #expect(text.selectedRange() == range)
            let font = try #require(text.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            #expect(font.pointSize == 16 && font.familyName == "Helvetica")
            #expect(text.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
            text.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0)); refresh()
            text.insertText(" café", replacementRange: text.selectedRange()); refresh()
            #expect(text.string == model.writingText)
            #expect(model.elements[1].runs?.first?.length == model.elements[1].text.unicodeScalars.count)
            model.undo(); refresh(); #expect(text.string == model.writingText)
        }
    }
    @Test func printFragmentsAndProductionLocksRetainStyles() async throws {
        try await withModel { model in
            model.replaceWritingText(in: model.writingRanges[1], with: String(repeating: "A quiet room. ", count: 160))
            let range = model.writingRanges[1]
            model.rememberDocumentCaret(range); model.toggleWritingEmphasis(\.italic)
            _ = model.printedPages // Warm the Courier cache before a typography-only edit.
            model.changeWritingTypography(font: "Helvetica", size: 18)
            for locked in [false, true] {
                await Task.yield()
                if locked { model.lockProductionPages() }
                let fragments = model.printedPages.flatMap(\.elements).filter { $0.element.id == model.elements[1].id && !$0.isContinuation }
                #expect(fragments.count > 1)
                for fragment in fragments {
                    let rich = try #require(fragment.attributed)
                    let font = try #require(rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                    #expect(font.pointSize == 18 && NSFontManager.shared.traits(of: font).contains(.italicFontMask))
                    #expect(fragment.textHeight + fragment.layout.before + fragment.layout.after <= 648)
                }
                let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
                #expect(pdf.pageCount == model.printedPages.count + 1)
                #expect(pdf.string?.contains("A quiet room.") == true)
            }
        }
    }
    @Test func replaceAllRetainsFormattingBetweenMatches() async throws {
        try await withModel { model in
            model.replaceWritingText(in: model.writingRanges[1], with: "cat MIDDLE cat")
            let start = model.writingRanges[1].location
            model.rememberDocumentCaret(NSRange(location: start + 4, length: 6)); model.toggleWritingEmphasis(\.underline)
            let original = try creativeState(model.document)
            model.findQuery = "cat"; model.replaceText = "elephant"; model.replaceAllMatches()
            #expect(model.elements[1].text == "elephant MIDDLE elephant")
            #expect(model.elements[1].runs?.first?.start == 9 && model.elements[1].runs?.first?.length == 6)
            model.undo(); #expect(try creativeState(model.document) == original)
        }
    }
    @Test func malformedRunsRejectedAndUppercaseExpansionRetainsStyles() throws {
        var element = ScreenplayElement(type: .character, text: "aßz")
        var styled = element.styledText
        try styled.format(1..<2, patch: .init(bold: true))
        element.setStyledText(styled); element.text = element.text.uppercased()
        #expect(element.text == "ASSZ" && element.runs?.first?.start == 1 && element.runs?.first?.length == 2)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(element)) as! [String: Any]
        json["runs"] = [["start": 500, "length": 2, "style": ["bold": true]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ScreenplayElement.self, from: data) }
    }
}
