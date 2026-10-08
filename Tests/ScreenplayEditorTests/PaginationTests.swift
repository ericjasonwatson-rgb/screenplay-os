import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Printed pagination")
@MainActor
struct PaginationTests {
    private func withDocument(_ elements: [ScreenplayElement], body: (ScreenplayViewModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "PaginationTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Pagination Review"), elements: elements)
        let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Pagination Review", author: ""), screenplayID: script.id), screenplay: script)
        let url = directory.appendingPathComponent("script.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        model.loadOpenScreenplay(at: url)
        try body(model, directory)
    }

    @Test func displayedCasingCoversIntroductionsCuesAndExtensionsWithoutChangingProse() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "int. room - day"),
            ScreenplayElement(type: .action, text: "Alice (30s) enters. Alice waits for Bob."),
            ScreenplayElement(type: .character, text: "Alice (v.o.)"),
            ScreenplayElement(type: .parenthetical, text: "(whispers)"),
            ScreenplayElement(type: .dialogue, text: "Alice is here."),
            ScreenplayElement(type: .character, text: "Bob (o.s.)"),
            ScreenplayElement(type: .parenthetical, text: "(v.o.)"),
            ScreenplayElement(type: .transition, text: "fade in:")]
        try withDocument(source) { model, _ in
            let expected = ["INT. ROOM - DAY", "ALICE (30s) enters. Alice waits for BOB.",
                "ALICE (V.O.)", "(whispers)", "Alice is here.", "BOB (O.S.)", "(V.O.)", "FADE IN:"]
            #expect(ScreenplayWritingProjection(elements: source).text == expected.joined(separator: "\n"))
            #expect(model.printedPages.flatMap(\.elements).map(\.text) == expected)
            #expect(model.printedLayout.unmappedElementIDs.isEmpty)
            #expect(model.elements.map(\.text) == source.map(\.text))
        }
    }

    @Test func importedTitleTailMovesSeparatelyWithSnapshotUndoAndPDF() throws {
        let body = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY"), ScreenplayElement(type: .action, text: "The end.")]
        let source = body + ["Script Title", "Written by", "Name of First Writer", "Based on, If Any", "Address", "Phone Number"].map { ScreenplayElement(type: .general, text: $0) }
        try withDocument(source) { model, _ in
            let original = model.document
            #expect(model.hasImportedTitlePageTail)
            model.moveImportedTitlePageTail()
            #expect(!model.hasImportedTitlePageTail)
            #expect(model.elements == Array(original!.screenplay.elements.prefix(body.count)))
            #expect(model.titlePage.subtitle.contains("Name of First Writer"))
            #expect(!model.snapshots.isEmpty)
            let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
            #expect(pdf.page(at: 0)?.string?.contains("Name of First Writer") == true)
            #expect(pdf.page(at: 1)?.string?.contains("Name of First Writer") == false)
            model.undo()
            #expect(model.elements == original?.screenplay.elements)
            #expect(model.titlePage == original?.titlePage)
            model.redo()
            let url = try #require(model.saveURL)
            model.loadOpenScreenplay(at: url)
            #expect(model.elements == Array(original!.screenplay.elements.prefix(body.count)))
            #expect(model.titlePage.subtitle.contains("Phone Number"))
        }
    }

    @Test func editablePageLinesMatchPrintedFragmentsAtEveryZoom() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "int. room - day"),
            ScreenplayElement(type: .action, text: "Mara (30s) waits."),
            ScreenplayElement(type: .character, text: "Mara (v.o.)"),
            ScreenplayElement(type: .dialogue, text: String(repeating: "Café 👩🏽‍🚀 waits for another day. ", count: 240)),
            ScreenplayElement(type: .action, text: ""), ScreenplayElement(type: .pageBreak, text: ""),
            ScreenplayElement(type: .transition, text: "cut to black.")]
        try withDocument(source) { model, _ in
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let value = view as? WritingTextView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for zoom in [1.0, 1.25, 0.8, 1.0] {
                model.pageZoom = zoom; host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                let editor = try #require(find(host)), plan = try #require(editor.pagePlan)
                let layout = try #require(editor.layoutManager), container = try #require(editor.textContainer)
                layout.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[layout.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                for (start, line) in plan.lines {
                    let y = try #require(actual[start], "Missing native line at \(start), zoom \(zoom)")
                    #expect(abs(y - line.y) < 0.01)
                }
                #expect(plan.labels == model.printedPages.map(\.label))
                #expect(plan.labels.count > 1)
                #expect(!editor.string.contains("PDF 1"))
                #expect(model.elements.map(\.text) == source.map(\.text))
            }
        }
    }

    @Test func importedScriptKeepsPrintedPaginationThroughEdits() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Defenders_of_Cat_Island.open-screenplay.json")
        let document = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: Data(contentsOf: fixture))
        let stressElements = (0..<6).flatMap { _ in document.screenplay.elements.map { source in
            var copy = ScreenplayElement(type: source.type, text: source.text)
            copy.setStyledText(source.styledText)
            return copy
        } }
        try withDocument(stressElements) { model, _ in
            let original = model.elements
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let text = view as? WritingTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for step in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                let editor = try #require(find(host))
                let plan = try #require(editor.pagePlan, "Full imported script must retain printed page positions")
                #expect(plan.labels == model.printedPages.map(\.label))
                let manager = try #require(editor.layoutManager), container = try #require(editor.textContainer)
                manager.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[manager.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                for (offset, line) in plan.lines {
                    #expect(abs(try #require(actual[offset]) - line.y) < 0.01)
                }
                for page in model.printedLayout.pages.indices {
                    let caret = try #require(model.printedLayout.firstSourceCaret(onPage: page))
                    #expect(model.printedLayout.pageIndex(containing: caret.location) == page)
                }
                if step == 0 {
                    editor.setSelectedRange(NSRange(location: editor.string.utf16.count / 2, length: 0))
                    editor.insertText("hyphenated-word ", replacementRange: editor.selectedRange())
                } else if step == 1 { model.undo() }
            }
            #expect(model.elements == original)
        }
    }

    @Test func incrementalNativeLayoutMatchesFreshPlanAfterEdits() throws {
        let source = (0..<8).flatMap { index in
            [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM \(index) - DAY"),
             ScreenplayElement(type: .action, text: String(repeating: "A café 👩🏽‍🚀 waits. ", count: 45))]
        }
        try withDocument(source) { model, _ in
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let text = view as? WritingTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let editor = try #require(find(host))
            for index in [15, 7, 1, 15, -1, -2, -3, -1] {
                let projection = ScreenplayWritingProjection(elements: model.elements)
                if index >= 0 {
                    editor.setSelectedRange(NSRange(location: NSMaxRange(projection.ranges[index]), length: 0))
                    editor.insertText(" More words 👩🏽‍🚀.", replacementRange: editor.selectedRange())
                } else if index == -1 {
                    model.undo()
                } else if index == -2 {
                    model.redo()
                } else {
                    let range = NSRange(location: projection.ranges[2].location,
                        length: NSMaxRange(projection.ranges[8]) - projection.ranges[2].location)
                    editor.setSelectedRange(range)
                    editor.insertText("A shorter replacement.", replacementRange: range)
                }
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                let plan = try #require(editor.pagePlan)
                let fresh = try #require(PrintedWritingLayout(print: model.printedLayout,
                    writing: ScreenplayWritingProjection(elements: model.elements), typography: model.writingTypography))
                #expect(plan.lines == fresh.lines)
                let manager = try #require(editor.layoutManager), container = try #require(editor.textContainer)
                manager.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[manager.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                for (offset, line) in fresh.lines {
                    #expect(abs(try #require(actual[offset]) - line.y) < 0.01)
                }
            }
        }
    }

    @Test func cachedPageMeasurementsFollowTypographyChanges() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY"),
            ScreenplayElement(type: .action, text: String(repeating: "A long changing line. ", count: 80))]
        try withDocument(source) { model, _ in
            let cache = PrintedWritingLayout.MeasurementCache()
            for size in [12.0, 18.0, 12.0] {
                model.changeWritingTypography(size: size)
                let writing = ScreenplayWritingProjection(elements: model.elements)
                let cached = try #require(PrintedWritingLayout(print: model.printedLayout, writing: writing, typography: model.writingTypography, cache: cache))
                let fresh = try #require(PrintedWritingLayout(print: model.printedLayout, writing: writing, typography: model.writingTypography))
                #expect(cached.labels == fresh.labels)
                #expect(Set(cached.lines.keys) == Set(fresh.lines.keys))
                for (start, expected) in fresh.lines {
                    let actual = try #require(cached.lines[start])
                    #expect(actual.y == expected.y)
                    #expect(actual.height == expected.height)
                    #expect(actual.baseline == expected.baseline)
                }
            }
        }
    }

    @Test func trailingBlankCaretUsesPrintedPagePosition() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY")]
            + (0..<65).map { _ in ScreenplayElement(type: .action, text: "") }
        try withDocument(source) { model, _ in
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            func find(_ view: NSView) -> WritingTextView? {
                if let value = view as? WritingTextView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let editor = try #require(find(host)), plan = try #require(editor.pagePlan)
            let line = try #require(plan.lines[(editor.string as NSString).length])
            let layout = try #require(editor.layoutManager)
            #expect(abs(layout.extraLineFragmentRect.minY - line.y) < 0.01)
        }
    }

    @Test func whitespaceAndBlankPagesSurviveNewLocksButOldLocksKeepTheirPolicy() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "  int. café - day  ")]
            + (0..<55).map { _ in ScreenplayElement(type: .action, text: "") }
            + [ScreenplayElement(type: .action, text: "  Last line.  ")]
        try withDocument(source) { model, directory in
            let before = model.printedPages.map { $0.elements.map(\.text) }
            #expect(before.count > 1)
            #expect(before.flatMap { $0 }.count == source.count)
            #expect(before.first?.first == source[0].text.uppercased())
            #expect(model.printedLayout.unmappedElementIDs.isEmpty)
            model.lockProductionPages()
            #expect(model.document?.screenplay.pageLock?.preservesWhitespace == true)
            #expect(model.printedPages.map { $0.elements.map(\.text) } == before)
            let saved = try #require(model.saveURL)
            model.loadOpenScreenplay(at: saved)
            #expect(model.printedPages.map { $0.elements.map(\.text) } == before)
            #expect(model.elements.map(\.text) == source.map(\.text))
            var old = try #require(model.document)
            old.screenplay.pageLock = ProductionPageLock(text: "INT. CAFÉ - DAY\nLast line.", pageStarts: [0])
            let legacyURL = directory.appendingPathComponent("old-lock.json")
            let bytes = try JSONEncoder.openScreenplayEncoder().encode(old)
            try bytes.write(to: legacyURL)
            model.loadOpenScreenplay(at: legacyURL)
            #expect(!model.printPreservesWhitespace)
            #expect(model.printedPages.flatMap(\.elements).map(\.text) == ["INT. CAFÉ - DAY", "Last line."])
            #expect(model.printedLayout.unmappedElementIDs.isEmpty)
            #expect(try Data(contentsOf: legacyURL) == bytes)
        }
    }

    @Test func uppercaseHeadingDisplayPreservesSourceAndMapsNativeEditing() throws {
        let source = [ScreenplayElement(type: .sceneHeading, text: "int. straße 👩🏽‍🚀 - day"),
                      ScreenplayElement(type: .action, text: "A café waits.")]
        try withDocument(source) { model, _ in
            let bytes = try Data(contentsOf: #require(model.saveURL))
            let projection = ScreenplayWritingProjection(elements: model.elements)
            #expect(projection.text == source[0].text.uppercased() + "\n" + source[1].text)
            let sourceSharp = (source[0].text as NSString).range(of: "ß")
            let displaySharp = projection.displayRange(sourceSharp)
            #expect((projection.text as NSString).substring(with: displaySharp) == "SS")
            #expect(projection.sourceRange(displaySharp) == sourceSharp)
            #expect(projection.sourceRange(projection.ranges[1]) == model.writingRanges[1])
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            func find(_ view: NSView) -> WritingTextView? {
                if let value = view as? WritingTextView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let editor = try #require(find(host))
            #expect(editor.string == projection.text)
            #expect(model.elements.map(\.text) == source.map(\.text))
            #expect(try Data(contentsOf: #require(model.saveURL)) == bytes)
            let range = projection.ranges[1]
            editor.setSelectedRange(range)
            #expect(editor.shouldChangeText(in: range, replacementString: "A different café."))
            editor.textStorage?.replaceCharacters(in: range, with: "A different café.")
            editor.didChangeText()
            #expect(model.elements[0].text == source[0].text)
            #expect(model.elements[1].text == "A different café.")
            model.undo()
            #expect(model.elements.map(\.text) == source.map(\.text))
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            editor.setSelectedRange(displaySharp)
            #expect(editor.shouldChangeText(in: displaySharp, replacementString: "x"))
            editor.textStorage?.replaceCharacters(in: displaySharp, with: "x")
            editor.didChangeText()
            #expect(model.elements[0].text == "INT. STRAXE 👩🏽‍🚀 - DAY")
            #expect(model.elements[1].text == source[1].text)
            model.undo()
            #expect(model.elements.map(\.text) == source.map(\.text))
        }
    }

    @Test func beatTemplateReplacementIsUndoableAndKeepsScenes() throws {
        try withDocument([ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY")]) { model, _ in
            let source = model.elements
            model.selectedOutlineTemplate = .saveTheCat
            model.seedSelectedOutlineTemplate()
            #expect(model.outlineBeats.count == 15)
            let beat = try #require(model.outlineBeats.first)
            model.bindingForOutlineNotes(beat).wrappedValue = "Keep this authored note."
            model.linkSelectedScene(to: beat)
            let savedBeats = model.outlineBeats
            model.selectedOutlineTemplate = .heroJourney
            model.seedSelectedOutlineTemplate()
            #expect(model.outlineBeats.count == 12)
            #expect(model.elements == source)
            model.undo()
            #expect(model.outlineBeats == savedBeats)
            #expect(model.selectedOutlineTemplate == .saveTheCat)
            let url = try #require(model.saveURL)
            model.loadOpenScreenplay(at: url)
            #expect(model.outlineBeats == savedBeats)
        }
    }

    @Test func continuousEditorMatchesPrintWrappingAndSpacingWithoutChangingSavedSource() throws {
        let types: [ElementType] = [.sceneHeading, .action, .character, .dialogue, .parenthetical, .transition, .shot, .general]
        let elements = types.map { ScreenplayElement(type: $0, text: "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN ELEVEN TWELVE") }
            + [ScreenplayElement(type: .action, text: ""), ScreenplayElement(type: .pageBreak, text: "")]
        try withDocument(elements) { model, _ in
            // Exercise the actual attributed fragments consumed by PDF drawing.
            model.changeWritingTypography(font: "Courier", size: 12)
            let sourceURL = try #require(model.saveURL)
            let saved = try Data(contentsOf: sourceURL)
            let original = model.document
            let pages = model.printedPages
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            func lines(_ layout: NSLayoutManager, range: NSRange, source: NSString) -> [(String, CGFloat)] {
                var result: [(String, CGFloat)] = []
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { rect, _, _, glyphs, _ in
                    let chars = NSIntersectionRange(range, layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
                    if chars.length > 0 { result.append((source.substring(with: chars), rect.minY + layout.location(forGlyphAt: glyphs.location).y)) }
                }
                return result
            }
            for zoom: CGFloat in [1.0, 2.0, 1.0] {
                model.pageZoom = Double(zoom)
                host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let editor = try #require(find(host))
                let scroll = try #require(editor.enclosingScrollView)
                let expectedWidth = max(576, scroll.contentSize.width / zoom)
                #expect(scroll.magnification == zoom)
                #expect(editor.frame.width == expectedWidth)
                #expect(editor.textContainerInset.width == (expectedWidth - 432) / 2)
                let layout = try #require(editor.layoutManager)
                layout.ensureLayout(for: try #require(editor.textContainer))
                for (index, element) in elements.prefix(types.count).enumerated() {
                    let range = model.writingRanges[index]
                    let printed = try #require(pages.flatMap(\.elements).first { $0.element.id == element.id && !$0.isContinuation })
                    let rich = try #require(printed.attributed)
                    let storage = NSTextStorage(attributedString: rich)
                    let printLayout = NSLayoutManager(); storage.addLayoutManager(printLayout)
                    let container = NSTextContainer(size: NSSize(width: printed.layout.width, height: 10000))
                    container.lineFragmentPadding = 0; printLayout.addTextContainer(container); printLayout.ensureLayout(for: container)
                    let screenLines = lines(layout, range: range, source: editor.string as NSString)
                    let printLines = lines(printLayout, range: NSRange(location: 0, length: rich.length), source: rich.string as NSString)
                    #expect(screenLines.map { $0.0 } == printLines.map { $0.0 }, "Wrapping differs for \(element.type) at \(zoom)")
                    if screenLines.count > 1 && printLines.count > 1 {
                        // TextKit rounds line metrics at the displayed font size.
                        #expect(abs((screenLines[1].1 - screenLines[0].1) - (printLines[1].1 - printLines[0].1)) <= (zoom == 1 ? 0.1 : 0.5))
                    }
                    let style = try #require(editor.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
                    #expect(style.paragraphSpacingBefore == printed.layout.before)
                    #expect(style.paragraphSpacing == printed.layout.after)
                    #expect(style.headIndent == printed.layout.x - 108)
                    #expect((432 + style.tailIndent - style.headIndent) == printed.layout.width)
                }
                #expect(model.document == original)
                #expect(model.elements.suffix(2).map(\.text) == ["", ""])
                #expect(model.printedPages.map { $0.elements.map(\.text) } == pages.map { $0.elements.map(\.text) })
                #expect(try Data(contentsOf: sourceURL) == saved)
            }
        }
    }

    @Test func printProjectionMapsUnicodeFragmentsAndRetainsUnprintedSourceEntries() throws {
        let heading = ScreenplayElement(type: .sceneHeading, text: "  int. straße - day  ")
        let cue = ScreenplayElement(type: .character, text: "MARA")
        let dialogue = ScreenplayElement(type: .dialogue, text: "  " + String(repeating: "Café 👩🏽‍🚀 waits. ", count: 220) + "  ")
        let blank = ScreenplayElement(type: .action, text: "")
        let breakElement = ScreenplayElement(type: .pageBreak, text: "")
        let repeated = ScreenplayElement(type: .action, text: "Same words.")
        let other = ScreenplayElement(type: .action, text: "Same words.")
        let source = [heading, cue, dialogue, blank, breakElement, repeated, other]
        try withDocument(source) { model, _ in
            let before = model.document
            let url = try #require(model.saveURL), saved = try Data(contentsOf: url)
            let projection = model.printedLayout
            #expect(projection.unmappedElementIDs.isEmpty)
            #expect(projection.sourceEntries.map(\.elementID) == source.map(\.id))
            #expect(projection.sourceEntries.map(\.text) == source.map(\.text))
            let text = model.writingText as NSString
            for entry in projection.sourceEntries { #expect(text.substring(with: entry.documentRange) == entry.text) }
            let items = projection.pages.flatMap(\.elements)
            #expect(items.contains { $0.isContinuation })
            for item in items {
                if item.isContinuation { #expect(item.sourceSpan == nil); continue }
                let span = try #require(item.sourceSpan)
                let element = try #require(source.first { $0.id == span.elementID })
                let selected = (element.text as NSString).substring(with: span.elementRange)
                #expect(text.substring(with: span.documentRange) == selected)
                #expect(Range(span.elementRange, in: element.text) != nil)
                #expect(item.text == (element.id == heading.id ? selected.uppercased() : selected))
            }
            let fragments = items.filter { !$0.isContinuation && $0.element.id == dialogue.id }
            #expect(fragments.count > 1)
            let spans = try fragments.map { try #require($0.sourceSpan).elementRange }
            #expect(spans.first?.location == 0)
            for pair in zip(spans, spans.dropFirst()) { #expect(NSMaxRange(pair.0) == pair.1.location) }
            #expect(items.first { $0.element.id == repeated.id }?.sourceSpan?.documentRange != items.first { $0.element.id == other.id }?.sourceSpan?.documentRange)
            #expect(model.document == before)
            #expect(try Data(contentsOf: url) == saved)
        }
    }

    @Test func nativePageGuidesFollowSourceWithoutEnteringEditableText() throws {
        let source = [ScreenplayElement(type: .character, text: "MARA"),
            ScreenplayElement(type: .dialogue, text: String(repeating: "Café 👩🏽‍🚀 waits. ", count: 200))]
        try withDocument(source) { model, _ in
            let before = model.document, url = try #require(model.saveURL)
            let bytes = try Data(contentsOf: url)
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let text = view as? WritingTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for zoom in [1.0, 1.25, 1.0] {
                model.pageZoom = zoom
                host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let text = try #require(find(host))
                #expect(text.pageGuides.count == model.printedPages.count)
                #expect(text.pageGuides.count > 1)
                var previous: CGFloat = -1
                for guide in text.pageGuides {
                    let point = try #require(text.pageGuidePoint(guide))
                    #expect(point.y > previous); previous = point.y
                    #expect(model.printedLayout.pageIndex(containing: guide.offset).map { model.printedPages[$0].label } == guide.label)
                }
                let boundary = text.pageGuides[1].offset
                text.setSelectedRange(NSRange(location: boundary - 1, length: 2))
                #expect(text.selectedRange() == NSRange(location: boundary - 1, length: 2))
                #expect(text.string == model.writingText)
                #expect(!text.string.contains("PDF"))
                #expect(model.document == before)
                #expect(try Data(contentsOf: url) == bytes)
            }
        }
    }

    @Test func viewportTracksScrollingAndZoomWithoutMovingCaretOrSaving() async throws {
        let source = [ScreenplayElement(type: .action, text: String(repeating: "A long road stretches into the distance. ", count: 350))]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = Screenplay(metadata: ScreenplayMetadata(title: "Viewport Test"), elements: source)
        let document = OpenScreenplayDocument(project: Project(metadata: ProjectMetadata(title: "Viewport Test", author: ""), screenplayID: script.id), screenplay: script)
        let file = directory.appendingPathComponent("script.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: file)
        let suite = "ViewportTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
        model.loadOpenScreenplay(at: file)
        do {
            let original = model.document
            let url = try #require(model.saveURL), bytes = try Data(contentsOf: url)
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let text = view as? WritingTextView { return text }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for zoom in [1.0, 1.5, 0.75] {
                model.pageZoom = zoom
                host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100))
                let text = try #require(find(host)), scroll = try #require(text.enclosingScrollView)
                #expect(scroll.hasVerticalScroller)
                #expect(!scroll.autohidesScrollers)
                #expect(scroll.scrollerStyle == .legacy)
                let plan = try #require(text.pagePlan)
                #expect(plan.labels.count > 2)
                let caret = text.selectedRange()
                for index in [1, 2, 0] {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(index) * PrintedWritingLayout.stride + 20))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    try await Task.sleep(for: .milliseconds(50))
                    #expect(model.scriptViewport.pageLabel == plan.labels[index])
                    #expect(text.selectedRange() == caret)
                }
                model.navigateToPrintedPage(2)
                // A field/popover losing focus can report the old native selection
                // before SwiftUI has applied the requested document caret.
                text.delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
                #expect(model.documentCaret == model.printedLayout.firstSourceCaret(onPage: 2))
                // SwiftUI rendering and the viewport notification are separately queued.
                // Await the observable result rather than assuming a fixed frame budget
                // while other native-window tests are sharing the main actor.
                let deadline = Date().addingTimeInterval(2)
                repeat {
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(20))
                } while model.scriptViewport.pageLabel != plan.labels[2] && Date() < deadline
                #expect(model.scriptViewport.pageLabel == plan.labels[2])
                #expect(model.requestedPrintedPageLabel == nil)
                #expect(model.documentCaret == model.printedLayout.firstSourceCaret(onPage: 2))
                #expect(model.document == original)
                #expect(try Data(contentsOf: url) == bytes)
            }
        }
    }

    @Test func pageNavigationUsesSplitFragmentBoundariesAndDoesNotSave() throws {
        let cue = ScreenplayElement(type: .character, text: "MARA")
        let speech = ScreenplayElement(type: .dialogue, text: "  " + String(repeating: "Café 👩🏽‍🚀 returns. ", count: 220) + "  ")
        let blank = ScreenplayElement(type: .action, text: "")
        try withDocument([cue, speech, blank]) { model, _ in
            let original = model.document
            let url = try #require(model.saveURL), bytes = try Data(contentsOf: url)
            let projection = model.printedLayout
            #expect(projection.pages.count > 1)
            for index in projection.pages.indices {
                let caret = try #require(projection.firstSourceCaret(onPage: index))
                #expect(projection.pageIndex(containing: caret.location) == index)
                model.navigateToPrintedPage(index)
                #expect(model.documentCaret == caret)
                #expect(model.currentPrintedPageStatus.hasPrefix("Script page \(projection.pages[index].label) · "))
            }
            let blankEntry = try #require(projection.sourceEntries.last)
            #expect(projection.pageIndex(containing: blankEntry.documentRange.location) == projection.pages.count - 1)
            #expect(projection.pageIndex(containing: -1) == nil)
            #expect(projection.firstSourceCaret(onPage: projection.pages.count) == nil)
            let selected = model.documentCaret
            model.navigateToPrintedPage(-1)
            #expect(model.documentCaret == selected)
            #expect(model.document == original)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func printProjectionRejectsMismatchedAndMissingFragments() throws {
        let first = ScreenplayElement(type: .action, text: "Same words.")
        let second = ScreenplayElement(type: .action, text: "Same words.")
        try withDocument([first, second]) { model, _ in
            let items = model.printedPages.flatMap(\.elements)
            let item = try #require(items.first)
            let wrong = PaginatedElement(element: item.element, text: "Different words.", layout: item.layout,
                textHeight: item.textHeight, blockHeight: item.blockHeight)
            let projection = ScriptPrintProjection(pages: [ScreenplayPage(number: 1, elements: [wrong, items[1]])], source: [first, second])
            #expect(projection.unmappedElementIDs == [first.id])
            #expect(projection.pages[0].elements[0].sourceSpan == nil)
            #expect(projection.pages[0].elements[1].sourceSpan?.elementID == second.id)
            let missing = ScriptPrintProjection(pages: [], source: [first, second])
            #expect(missing.unmappedElementIDs == [first.id, second.id])
            #expect(missing.sourceEntries.count == 2)
        }
    }

    @Test func lockedPrintProjectionMapsRepeatedFragmentsAfterReopen() throws {
        let cue = ScreenplayElement(type: .character, text: "MARA")
        let speech = ScreenplayElement(type: .dialogue, text: String(repeating: "Same café 👩🏽‍🚀 words. ", count: 220))
        try withDocument([cue, speech]) { model, _ in
            model.lockProductionPages()
            let url = try #require(model.saveURL)
            model.loadOpenScreenplay(at: url)
            let before = model.document, bytes = try Data(contentsOf: url)
            let projection = model.printedLayout
            #expect(projection.unmappedElementIDs.isEmpty)
            let fragments = projection.pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == speech.id }
            #expect(fragments.count > 1)
            let spans = try fragments.map { try #require($0.sourceSpan).elementRange }
            #expect(spans.first?.location == 0)
            #expect(spans.last.map(NSMaxRange) == (speech.text as NSString).length)
            for pair in zip(spans, spans.dropFirst()) { #expect(NSMaxRange(pair.0) == pair.1.location) }
            for item in fragments {
                let span = try #require(item.sourceSpan)
                #expect((speech.text as NSString).substring(with: span.elementRange) == item.text)
            }
            #expect(model.document == before)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func convergedPaginationSuffixMatchesFreshPagesAndFallsBackForPageCountChanges() throws {
        let source = (0..<8).flatMap { index in
            [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM \(index) - DAY"),
             ScreenplayElement(type: .action, text: "Alice enters a café 👩🏽‍🚀."),
             ScreenplayElement(type: .character, text: "MARA"),
             ScreenplayElement(type: .dialogue, text: String(repeating: "A long conversation. ", count: 120)),
             ScreenplayElement(type: .pageBreak, text: "")]
        }
        try withDocument(source) { model, directory in
            _ = model.printedPages
            @MainActor func compareFresh() throws {
                let warm = model.printedPages
                let file = directory.appendingPathComponent("fresh-suffix.json")
                try JSONEncoder.openScreenplayEncoder().encode(try #require(model.document)).write(to: file)
                let suite = "SuffixFresh.\(UUID())"
                let prefs = try #require(UserDefaults(suiteName: suite))
                defer { prefs.removePersistentDomain(forName: suite) }
                let fresh = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: prefs)
                fresh.loadOpenScreenplay(at: file)
                let expected = fresh.printedPages
                #expect(warm.map(\.label) == expected.map(\.label))
                #expect(warm.map { $0.elements.map(\.text) } == expected.map { $0.elements.map(\.text) })
                #expect(warm.map { $0.elements.map(\.layout) } == expected.map { $0.elements.map(\.layout) })
                #expect(warm.map { $0.elements.map(\.blockHeight) } == expected.map { $0.elements.map(\.blockHeight) })
                #expect(warm.map { $0.elements.map(\.sourceSpan) } == expected.map { $0.elements.map(\.sourceSpan) })
                let warmPDF = try #require(PDFDocument(data: model.makePrintPDF()))
                let freshPDF = try #require(PDFDocument(data: fresh.makePrintPDF()))
                #expect(warmPDF.pageCount == freshPDF.pageCount)
                #expect(warmPDF.string == freshPDF.string)
            }
            let action = model.elements[1]
            model.binding(for: action).wrappedValue += " She waits."
            try compareFresh()
            #expect(model.lastPaginationReusedSuffixElementCount > 0)
            model.undo()
            try compareFresh()
            model.redo()
            try compareFresh()
            // Growing the first scene by pages must not reuse old page numbers.
            model.binding(for: action).wrappedValue = String(repeating: "A much longer road. ", count: 600)
            try compareFresh()
            #expect(model.lastPaginationReusedSuffixElementCount == 0)
            model.binding(for: action).wrappedValue = "Alice waits."
            try compareFresh()
            #expect(model.lastPaginationReusedSuffixElementCount == 0)
            // Later cue changes can alter earlier display-only introduction casing.
            let cue = model.elements[32]
            model.binding(for: cue).wrappedValue = "ALICE"
            try compareFresh()
            // Explicit default typography also changes the attributed print path.
            model.changeWritingTypography(size: 12)
            try compareFresh()
            #expect(model.lastPaginationReusedSuffixElementCount == 0)
            #expect(model.lastPaginationReusedElementCount == 0)
            model.changeWritingTypography(size: 14)
            try compareFresh()
            #expect(model.lastPaginationReusedSuffixElementCount == 0)
        }
    }

    @Test func reusedScenePrefixMatchesFreshPaginationAcrossEdits() throws {
        let source = (0..<12).flatMap { index in
            [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM \(index) - DAY"),
             ScreenplayElement(type: .action, text: "Alice enters. " + String(repeating: "A long café passage 👩🏽‍🚀. ", count: 60)),
             ScreenplayElement(type: .character, text: "MARA"),
             ScreenplayElement(type: .dialogue, text: String(repeating: "Something worth saying. ", count: 80))]
        }
        try withDocument(source) { model, directory in
            _ = model.printedPages
            @MainActor func compareFresh() throws {
                let warm = model.printedPages
                let url = directory.appendingPathComponent("fresh.json")
                try JSONEncoder.openScreenplayEncoder().encode(try #require(model.document)).write(to: url)
                let suite = "ScenePrefix.\(UUID())"
                let prefs = try #require(UserDefaults(suiteName: suite))
                defer { prefs.removePersistentDomain(forName: suite) }
                let fresh = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: prefs)
                fresh.loadOpenScreenplay(at: url)
                #expect(warm.map(\.label) == fresh.printedPages.map(\.label))
                #expect(warm.map { $0.elements.map(\.text) } == fresh.printedPages.map { $0.elements.map(\.text) })
                #expect(warm.map { $0.elements.map(\.blockHeight) } == fresh.printedPages.map { $0.elements.map(\.blockHeight) })
                #expect(model.printedLayout.unmappedElementIDs.isEmpty)
            }
            let last = try #require(model.elements.last)
            model.binding(for: last).wrappedValue += " Extra words."
            try compareFresh()
            #expect(model.lastPaginationReusedElementCount > 0)
            model.undo()
            try compareFresh()
            model.redo()
            try compareFresh()
            // Changing a late cue changes an earlier first introduction's casing.
            let cue = model.elements[46]
            model.binding(for: cue).wrappedValue = "Alice"
            try compareFresh()
            #expect(model.lastPaginationReusedElementCount == 0)
            let heading = model.elements[24]
            model.binding(for: heading).wrappedValue = "EXT. A DIFFERENT PLACE - NIGHT"
            try compareFresh()
            model.setType(.action, for: heading.id)
            try compareFresh()
        }
    }

    @Test func warmMeasurementsMatchFreshPaginationAfterTextAndTypeChanges() throws {
        let action = ScreenplayElement(type: .action, text: String(repeating: "A passage with many words. ", count: 45))
        try withDocument([ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY"), action]) { model, directory in
            _ = model.printedPages
            model.setType(.dialogue, for: action.id)
            model.binding(for: action).wrappedValue = action.text + "One more line."
            let warm = model.printedPages
            let suite = "PaginationFresh.\(UUID())"
            let preferences = try #require(UserDefaults(suiteName: suite))
            defer { preferences.removePersistentDomain(forName: suite) }
            let fresh = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: preferences)
            fresh.loadOpenScreenplay(at: try #require(model.saveURL))
            #expect(warm.map(\.label) == fresh.printedPages.map(\.label))
            #expect(warm.map { $0.elements.map(\.text) } == fresh.printedPages.map { $0.elements.map(\.text) })
            #expect(warm.map { $0.elements.map(\.blockHeight) } == fresh.printedPages.map { $0.elements.map(\.blockHeight) })
            let cachedPDF = try #require(PDFDocument(data: model.makePrintPDF()))
            let freshPDF = try #require(PDFDocument(data: fresh.makePrintPDF()))
            #expect(cachedPDF.string == freshPDF.string)
            #expect(cachedPDF.pageCount == freshPDF.pageCount)
        }
    }

    @Test func titlePageRetainsLongContactAndRejectsOverflowWithoutReplacingExport() throws {
        let dialogue = (1...280).map { "word\($0)" }.joined(separator: " ")
        let source = [ScreenplayElement(type: .sceneHeading, text: "INT. STUDIO - DAY"),
                      ScreenplayElement(type: .character, text: "MARA"),
                      ScreenplayElement(type: .dialogue, text: dialogue),
                      ScreenplayElement(type: .pageBreak, text: ""),
                      ScreenplayElement(type: .action, text: "The room falls quiet.")]
        try withDocument(source) { model, folder in
            model.titlePageBinding(.title).wrappedValue = "The Last Light"
            model.titlePageBinding(.subtitle).wrappedValue = "A screenplay for export review"
            model.titlePageBinding(.author).wrappedValue = "Sample Writer"
            let contact = (1...12).map { "Contact line \($0)" }.joined(separator: "\n")
            model.titlePageBinding(.contact).wrappedValue = contact
            model.titlePageBinding(.draftDate).wrappedValue = "October 3, 2026"
            let before = model.document
            let data = try model.makePrintPDF()
            let pdf = try #require(PDFDocument(data: data))
            let title = try #require(pdf.page(at: 0))
            let titleOnly = try #require(PDFDocument(data: model.makeTitlePagePDF()))
            #expect(titleOnly.pageCount == 1)
            let previewTitle = try #require(titleOnly.page(at: 0))
            #expect(previewTitle.string == title.string)
            let size = NSSize(width: 612, height: 792)
            #expect(previewTitle.thumbnail(of: size, for: .mediaBox).tiffRepresentation == title.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
            #expect(title.string?.contains("Contact line 12") == true)
            #expect(title.string?.contains("October 3, 2026") == true)
            let contactBounds = try #require(title.selection(for: (title.string! as NSString).range(of: "Contact line 1")))
                .bounds(for: title)
            #expect(abs(contactBounds.minX - 108) < 2)
            #expect(pdf.page(at: 1)?.string?.contains("INT. STUDIO - DAY") == true)
            #expect(model.document == before)
            if let directory = ProcessInfo.processInfo.environment["SCREENPLAYOS_EXPORT_AUDIT_DIRECTORY"] {
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("title-and-dialogue.pdf"))
            }
            let destination = folder.appendingPathComponent("existing.pdf")
            try data.write(to: destination)
            model.titlePageBinding(.contact).wrappedValue = String(repeating: "A contact line\n", count: 100)
            let overflowDocument = model.document
            #expect(throws: PrintPDFError.self) { try model.makeTitlePagePDF() }
            #expect(throws: PrintPDFError.self) { try model.makePrintPDF() }
            model.exportPDF(to: destination)
            #expect(model.errorMessage?.contains("does not fit") == true)
            #expect(try Data(contentsOf: destination) == data)
            #expect(model.document == overflowDocument)
            model.titlePageBinding(.contact).wrappedValue = ""
            model.titlePageBinding(.subtitle).wrappedValue = String(repeating: "An additional credit\n", count: 100)
            #expect(throws: PrintPDFError.self) { try model.makePrintPDF() }
        }
    }

    @Test func previewMatchesExportAndDoesNotChangeTheScreenplay() throws {
        let dialogue = (1...800).map { "line\($0)" }.joined(separator: " ")
        let elements = [ScreenplayElement(type: .sceneHeading, text: "INT. ROOM - DAY"),
                        ScreenplayElement(type: .character, text: "MARA"),
                        ScreenplayElement(type: .dialogue, text: dialogue),
                        ScreenplayElement(type: .pageBreak, text: ""),
                        ScreenplayElement(type: .action, text: "END OF SCENE.")]
        try withDocument(elements) { model, directory in
            model.titlePageBinding(.title).wrappedValue = "Preview Review"
            let before = model.document
            let data = try model.makePrintPDF()
            let snapshot = try PrintPreviewSnapshot(data: data)
            #expect(model.document == before)
            #expect(snapshot.document.pageCount == model.printedPages.count + 1)
            #expect(snapshot.document.page(at: 0)?.string?.contains("Preview Review") == true)
            #expect(snapshot.document.string?.contains("(MORE)") == true)
            #expect(snapshot.document.string?.contains("(CONT'D)") == true)
            let url = directory.appendingPathComponent("export.pdf")
            model.exportPDF(to: url)
            let exported = try #require(PDFDocument(url: url))
            #expect(exported.pageCount == snapshot.document.pageCount)
            for index in 0..<exported.pageCount {
                let previewPage = try #require(snapshot.document.page(at: index))
                let exportedPage = try #require(exported.page(at: index))
                #expect(previewPage.string == exportedPage.string)
                #expect(previewPage.bounds(for: .mediaBox) == exportedPage.bounds(for: .mediaBox))
                let size = NSSize(width: 306, height: 396)
                #expect(previewPage.thumbnail(of: size, for: .mediaBox).tiffRepresentation == exportedPage.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
            }
            // Exporting a reviewed snapshot writes those exact bytes, even after later edits.
            model.binding(for: elements.last!).wrappedValue = "A later change."
            model.writePrintPDF(snapshot.data, to: url)
            #expect(try Data(contentsOf: url) == snapshot.data)
            #expect(snapshot.document.string?.contains("END OF SCENE.") == true)
            #expect(snapshot.document.string?.contains("A later change.") == false)
        }
    }

    @Test func printExportFailureIsReportedWithoutChangingSource() throws {
        try withDocument([ScreenplayElement(type: .action, text: "Original.")]) { model, directory in
            let before = model.document
            model.exportPDF(to: directory.appendingPathComponent("missing/export.pdf"))
            #expect(model.errorMessage?.hasPrefix("Could not export PDF:") == true)
            #expect(model.document == before)
            #expect(throws: (any Error).self) { try PrintPreviewSnapshot(data: Data("invalid".utf8)) }
        }
    }

    @Test func lockingPreservesExistingPaginationAndRoundTrips() throws {
        let source = [ScreenplayElement(type: .character, text: "MARA"),
                      ScreenplayElement(type: .dialogue, text: (1...500).map { "word\($0)" }.joined(separator: " "))]
        try withDocument(source) { model, _ in
            let before = model.printedPages
            model.lockProductionPages()
            #expect(model.pagesAreLocked)
            #expect(model.printedPages.map(\.label) == before.map(\.label))
            #expect(model.printedPages.map { $0.elements.map(\.text) } == before.map { $0.elements.map(\.text) })
            let saved = try #require(model.saveURL)
            model.loadOpenScreenplay(at: saved)
            #expect(model.pagesAreLocked)
            #expect(model.printedPages.map(\.label) == before.map(\.label))
            model.unlockProductionPages()
            #expect(!model.pagesAreLocked)
            model.undo()
            #expect(model.pagesAreLocked)
            model.redo()
            #expect(!model.pagesAreLocked)
        }
    }

    @Test func identicalParagraphsKeepTheirLockedPageIdentityAfterDeletionAndReopen() throws {
        let first = ScreenplayElement(type: .action, text: "Same text.")
        let separator = ScreenplayElement(type: .pageBreak, text: "")
        let second = ScreenplayElement(type: .action, text: "Same text.")
        try withDocument([first, separator, second]) { model, _ in
            model.lockProductionPages()
            #expect(model.document?.screenplay.pageLock?.elements?.map(\.id) == [first.id, separator.id, second.id])
            model.selectElement(id: first.id)
            model.deleteSelectedElement()
            model.selectElement(id: separator.id)
            model.deleteSelectedElement()
            #expect(model.printedPages.map(\.label) == ["1", "2"])
            #expect(model.printedPages[0].elements.isEmpty)
            #expect(model.printedPages[1].elements.first?.element.id == second.id)
            model.undo()
            model.undo()
            #expect(model.printedPages[0].elements.first?.element.id == first.id)
            model.redo()
            model.redo()
            let saved = try #require(model.saveURL)
            model.loadOpenScreenplay(at: saved)
            #expect(model.printedPages[0].elements.isEmpty)
            #expect(model.printedPages[1].elements.first?.element.id == second.id)
            let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
            #expect(pdf.page(at: 1)?.string?.contains("OMITTED") == true)
            #expect(pdf.page(at: 2)?.string?.contains("Same text.") == true)
        }
    }

    @Test func deletingLastIdenticalParagraphLeavesFirstOnPageOne() throws {
        let first = ScreenplayElement(type: .action, text: "Same text.")
        let separator = ScreenplayElement(type: .pageBreak, text: "")
        let second = ScreenplayElement(type: .action, text: "Same text.")
        try withDocument([first, separator, second]) { model, _ in
            model.lockProductionPages()
            model.selectElement(id: second.id)
            model.deleteSelectedElement()
            model.selectElement(id: separator.id)
            model.deleteSelectedElement()
            #expect(model.printedPages.map(\.label) == ["1", "2"])
            #expect(model.printedPages[0].elements.first?.element.id == first.id)
            #expect(model.printedPages[1].elements.isEmpty)
        }
    }

    @Test func identicalReplacementStaysOnTheSurvivingParagraphsPage() throws {
        let first = ScreenplayElement(type: .action, text: "First text.")
        let next = ScreenplayElement(type: .action, text: "Second text.")
        try withDocument([first, ScreenplayElement(type: .pageBreak, text: ""), next]) { model, _ in
            model.lockProductionPages()
            model.binding(for: next).wrappedValue = "First text."
            #expect(model.printedPages[0].elements.first?.element.id == first.id)
            #expect(model.printedPages[1].elements.first?.element.id == next.id)
            #expect(model.printedPages[1].elements.first?.text == "First text.")
        }
    }

    @Test func identityAnchorsFollowSplitsMergesAndCompleteDeletion() {
        let first = ScreenplayElement(type: .action, text: "alpha beta gamma")
        let next = ScreenplayElement(type: .action, text: "tail")
        let baseline = [first, next]
        let lock = ProductionPageLock(text: baseline.map(\.text).joined(separator: "\n"),
                                      pageStarts: [0, 11, 17],
                                      elements: baseline.map { ProductionLockElement(id: $0.id, text: $0.text) })
        var head = first
        head.text = "alpha"
        let split = ScreenplayElement(type: .action, text: "beta gamma")
        #expect(ProductionPageLayout.mappedStarts(lock, source: [head, split, next]) == [0, 11, 17])
        var merged = first
        merged.text = "alpha beta gammatail"
        #expect(ProductionPageLayout.mappedStarts(lock, source: [merged]) == [0, 11, 16])
        #expect(ProductionPageLayout.mappedStarts(lock, source: []) == [0, 0, 0])
    }

    @Test func legacyPageLocksDecodeWithoutInventingParagraphIdentity() throws {
        let json = Data(#"{"text":"First\nNext","pageStarts":[0,6]}"#.utf8)
        let lock = try JSONDecoder().decode(ProductionPageLock.self, from: json)
        #expect(lock.elements == nil)
        let source = [ScreenplayElement(type: .action, text: "First NEW"), ScreenplayElement(type: .action, text: "Next")]
        #expect(ProductionPageLayout.mappedStarts(lock, source: source) == [0, 10])
    }

    @Test func lockedGrowthAddsLetteredPagesWithoutMovingTheNextPage() throws {
        let first = ScreenplayElement(type: .action, text: "First page.")
        let next = ScreenplayElement(type: .sceneHeading, text: "EXT. SECOND LOCATION - DAY")
        let source = [first, ScreenplayElement(type: .pageBreak, text: ""), next]
        try withDocument(source) { model, directory in
            model.lockProductionPages()
            model.binding(for: first).wrappedValue = "First page. " + (1...1100).map { "addition\($0)" }.joined(separator: " ")
            let pages = model.printedPages
            #expect(pages.first?.label == "1")
            #expect(pages.contains { $0.label == "1A" })
            #expect(pages.last?.label == "2")
            #expect(pages.last?.elements.first?.element.id == next.id)
            #expect(model.sceneBreakdowns.first?.pageNumber == "2")
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            let pdf = try PrintPreviewSnapshot(data: model.makePrintPDF(), pageLabels: pages.map(\.label))
            #expect(pdf.pageLabels.contains("1A"))
            #expect(pdf.document.string?.contains("1A.") == true)
            #expect(pdf.document.pageCount == pages.count + 1)
            model.undo()
            #expect(model.printedPages.map(\.label) == ["1", "2"])
            #expect(model.pagesAreLocked)
        }
    }

    @Test func replacingTheFirstTextOnALockedPageKeepsItOnThatPage() throws {
        let heading = ScreenplayElement(type: .sceneHeading, text: "EXT. SECOND LOCATION - DAY")
        let source = [ScreenplayElement(type: .action, text: "First page."),
                      ScreenplayElement(type: .pageBreak, text: ""), heading]
        try withDocument(source) { model, _ in
            model.lockProductionPages()
            model.binding(for: heading).wrappedValue = "INT. REVISED LOCATION - NIGHT"
            #expect(model.printedPages.map(\.label) == ["1", "2"])
            #expect(model.printedPages[0].elements.map(\.text) == ["First page."])
            #expect(model.printedPages[1].elements.map(\.text) == ["INT. REVISED LOCATION - NIGHT"])
        }
    }

    @Test func removingLockedPageRetainsOmittedNumber() throws {
        let first = ScreenplayElement(type: .action, text: "First page.")
        let source = [first, ScreenplayElement(type: .pageBreak, text: ""), ScreenplayElement(type: .action, text: "Second page.")]
        try withDocument(source) { model, _ in
            model.lockProductionPages()
            model.selectElement(id: first.id)
            model.deleteSelectedElement()
            #expect(model.printedPages.map(\.label) == ["1", "2"])
            #expect(model.printedPages[0].elements.isEmpty)
            #expect(model.printedPages[1].elements.first?.text == "Second page.")
            let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
            #expect(pdf.page(at: 1)?.string?.contains("OMITTED") == true)
            model.undo()
            #expect(model.printedPages[0].elements.first?.text == "First page.")
        }
    }

    @Test func lockAnchorsFollowParagraphSplitsAndUnicode() throws {
        let original = ScreenplayElement(type: .action, text: (1...650).map { "word\($0)" }.joined(separator: " "))
        try withDocument([original]) { model, _ in
            model.lockProductionPages()
            let labels = model.printedPages.map(\.label)
            model.splitElement(original.id, at: 30)
            #expect(model.pagesAreLocked)
            #expect(model.printedPages.filter { !$0.label.contains(where: \.isLetter) }.map(\.label) == labels)
            #expect(model.printedPages.flatMap(\.elements).filter { !$0.isContinuation }.map(\.text).joined().filter { !$0.isWhitespace } == original.text.filter { !$0.isWhitespace })
        }
        let lock = ProductionPageLock(text: "👩🏽‍🚀 first\nNext", pageStarts: [0, 8])
        #expect(ProductionPageLayout.mappedStarts(lock, text: "👩🏽‍🚀 NEW first\nNext") == [0, 12])
        #expect(ProductionPageLayout.suffix(26) == "Z")
        #expect(ProductionPageLayout.suffix(27) == "AA")
    }

    @Test func longParagraphIsSplitWithoutChangingSource() throws {
        let text = (1...700).map { "word\($0)" }.joined(separator: " ")
        let element = ScreenplayElement(type: .action, text: text)
        try withDocument([element]) { model, directory in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.flatMap(\.elements).map(\.text).joined() == text)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(model.document == before)
            #expect(model.elements.count == 1)
            let url = directory.appendingPathComponent("review.pdf")
            model.exportPDF(to: url)
            let pdf = try #require(PDFDocument(url: url))
            #expect(pdf.pageCount == pages.count + 1)
            let extracted = (1..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ")
            let tokens = extracted.components(separatedBy: .whitespacesAndNewlines).filter { $0.hasPrefix("word") }
            #expect(tokens == text.components(separatedBy: " "))
            // Optional artifacts for visual inspection; never writes into a user's screenplay folder.
            if let destination = ProcessInfo.processInfo.environment["SCREENPLAY_PAGINATION_QA_DIR"] {
                let output = URL(fileURLWithPath: destination)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try Data(contentsOf: url).write(to: output.appendingPathComponent("pagination.pdf"))
                for index in 1..<pdf.pageCount {
                    let page = try #require(pdf.page(at: index))
                    let thumbnail = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                    let tiff = try #require(thumbnail.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("page-\(index).png"))
                }
            }
        }
    }

    @Test func unicodeAndUnbrokenWordsSurviveSplitting() throws {
        let text = String(repeating: "👩🏽‍🚀café e\u{301} ", count: 300) + String(repeating: "X", count: 900)
        try withDocument([ScreenplayElement(type: .action, text: text)]) { model, _ in
            #expect(model.printedPages.count > 1)
            #expect(model.printedPages.flatMap(\.elements).map(\.text).joined() == text)
            #expect(model.printedPages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
        }
    }

    @Test func cueStaysWithStartOfLongDialogue() throws {
        let cue = ScreenplayElement(type: .character, text: "MARA")
        let dialogue = ScreenplayElement(type: .dialogue, text: String(repeating: "We have to keep going. ", count: 220).trimmingCharacters(in: .whitespaces))
        try withDocument([cue, dialogue]) { model, _ in
            #expect(model.printedPages.count > 1)
            #expect(model.printedPages.first?.elements.filter { !$0.isContinuation }.map(\.element.id) == [cue.id, dialogue.id])
            #expect(model.printedPages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(model.printedPages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(model.printedPages.last?.elements.last?.isContinuation == false)
            let fragments = model.printedPages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == dialogue.id }
            #expect(fragments.map(\.text).joined() == dialogue.text)
            #expect(model.elements == [cue, dialogue])
            #expect(model.printedPages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
        }
    }

    @Test func adjacentDialogueParagraphsContinueAcrossAutomaticBreaks() throws {
        let dialogue = (1...85).map { ScreenplayElement(type: .dialogue, text: "Sentence \($0).") }
        let source = [ScreenplayElement(type: .character, text: "MARA")] + dialogue
        try withDocument(source) { model, _ in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count >= 3)
            #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation }.map(\.element.id) == source.map(\.id))
            #expect(model.document == before)
        }
    }

    @Test func explicitBreakWithinSpeechAddsMarkersAndPreservesParenthetical() throws {
        let source = [ScreenplayElement(type: .character, text: "MARA (V.O.)"),
                      ScreenplayElement(type: .dialogue, text: "I thought we were done."),
                      ScreenplayElement(type: .pageBreak, text: ""),
                      ScreenplayElement(type: .pageBreak, text: ""),
                      ScreenplayElement(type: .parenthetical, text: "(quietly)"),
                      ScreenplayElement(type: .dialogue, text: "There is one more thing.")]
        try withDocument(source) { model, directory in
            let before = model.document
            let pages = model.printedPages
            #expect(pages.count == 2)
            #expect(pages[0].elements.last?.text == "(MORE)")
            #expect(pages[1].elements.map(\.text) == ["MARA (V.O.) (CONT'D)", "(quietly)", "There is one more thing."])
            #expect(model.document == before)
            let data = try model.makePrintPDF()
            let pdf = try #require(PDFDocument(data: data))
            #expect(pdf.pageCount == 3)
            #expect(pdf.page(at: 1)?.string?.contains("(MORE)") == true)
            #expect(pdf.page(at: 2)?.string?.contains("MARA (V.O.) (CONT'D)") == true)
            if let destination = ProcessInfo.processInfo.environment["SCREENPLAY_PAGINATION_QA_DIR"] {
                let output = URL(fileURLWithPath: destination)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try data.write(to: output.appendingPathComponent("continued-dialogue.pdf"))
                for index in 1..<pdf.pageCount {
                    let page = try #require(pdf.page(at: index))
                    let image = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
                    let tiff = try #require(image.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent("continued-dialogue-\(index).png"))
                }
            }
        }
    }

    @Test func newSpeakerAndSceneEndContinuation() throws {
        for next in [ScreenplayElement(type: .character, text: "ELI"),
                     ScreenplayElement(type: .sceneHeading, text: "EXT. STREET - NIGHT"),
                     ScreenplayElement(type: .action, text: "Mara leaves.")] {
            let source = [ScreenplayElement(type: .character, text: "MARA"),
                          ScreenplayElement(type: .dialogue, text: "Goodbye."),
                          ScreenplayElement(type: .pageBreak, text: ""), next,
                          ScreenplayElement(type: .dialogue, text: "A new thought.")]
            try withDocument(source) { model, _ in
                #expect(model.printedPages.flatMap(\.elements).allSatisfy { !$0.isContinuation })
            }
        }
    }

    @Test func parentheticalAtPageBoundaryKeepsDialogueAndFitsMarkers() throws {
        let dialogue = (1...36).map { ScreenplayElement(type: .dialogue, text: "Sentence \($0).") }
        let source = [ScreenplayElement(type: .character, text: "MARA (CONT'D)")] + dialogue +
            [ScreenplayElement(type: .parenthetical, text: "(after a long pause)"),
             ScreenplayElement(type: .dialogue, text: String(repeating: "Keep going. ", count: 150))]
        try withDocument(source) { model, _ in
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
            #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
            #expect(pages.flatMap(\.elements).allSatisfy { !$0.text.contains("(CONT'D) (CONT'D)") })
            let final = source.last!
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == final.id }.map(\.text).joined() == final.text)
        }
    }

    @Test func longParentheticalsAndForcedBreaksStayWithinPages() throws {
        for count in [1, 30, 100, 250] {
            let parenthetical = ScreenplayElement(type: .parenthetical, text: "(" + String(repeating: "quietly waiting ", count: count) + ")")
            let source = [ScreenplayElement(type: .character, text: "MARA"),
                          ScreenplayElement(type: .dialogue, text: "Before the pause."),
                          ScreenplayElement(type: .pageBreak, text: ""), parenthetical,
                          ScreenplayElement(type: .pageBreak, text: ""),
                          ScreenplayElement(type: .dialogue, text: "After the pause.")]
            try withDocument(source) { model, _ in
                let pages = model.printedPages
                #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
                #expect(pages.dropLast().allSatisfy { $0.elements.last?.text == "(MORE)" })
                #expect(pages.dropFirst().allSatisfy { $0.elements.first?.text == "MARA (CONT'D)" })
                #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == parenthetical.id }.map(\.text).joined() == parenthetical.text)
            }
        }
    }

    @Test func oversizedSpeakerDoesNotPreventPaginationProgress() throws {
        let cue = ScreenplayElement(type: .character, text: String(repeating: "MARA ", count: 400))
        let dialogue = ScreenplayElement(type: .dialogue, text: String(repeating: "Keep going. ", count: 200))
        try withDocument([cue, dialogue]) { model, _ in
            let pages = model.printedPages
            #expect(pages.count > 1)
            #expect(pages.allSatisfy { $0.elements.map(\.blockHeight).reduce(0, +) <= 648 })
            #expect(pages.flatMap(\.elements).filter { !$0.isContinuation && $0.element.id == dialogue.id }.map(\.text).joined() == dialogue.text)
        }
    }

    @Test func explicitPageBreakStartsNextPage() throws {
        let first = ScreenplayElement(type: .action, text: "Before the break.")
        let second = ScreenplayElement(type: .action, text: "After the break.")
        try withDocument([first, ScreenplayElement(type: .pageBreak, text: ""), second]) { model, _ in
            #expect(model.printedPages.count == 2)
            #expect(model.printedPages[0].elements.first?.element.id == first.id)
            #expect(model.printedPages[1].elements.first?.element.id == second.id)
        }
    }
}
