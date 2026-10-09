import AppKit
import PDFKit
import SwiftUI
import Testing
import ScreenplayDomain
import ScreenplayFDX
@testable import ScreenplayOSApp

@Suite("Line layout calibration") @MainActor
struct LineLayoutCalibrationTests {
    private func compare(_ name: String, mode: ScreenplayLineLayout = .twelvePointExperiment, locked: Bool = false, fontSize: Double? = nil, fontFamily: String? = nil, dialogueText: String? = nil, speakerText: String? = nil, editing: Bool = false, body: (ScreenplayViewModel, ScreenplayViewModel, URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = name == "Defenders" ? "Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx" : "Docs/AuditEvidence/pagination-2026-10-08/\(name).fdx"
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        var document = try FDXImporter().importData(data, title: name).document
        if let dialogueText {
            for index in document.screenplay.elements.indices where document.screenplay.elements[index].type == .dialogue {
                document.screenplay.elements[index].text = dialogueText
            }
        }
        if let speakerText {
            for index in document.screenplay.elements.indices where document.screenplay.elements[index].type == .character {
                document.screenplay.elements[index].text = speakerText
            }
        }
        if locked {
            document.screenplay.pageLock = ProductionPageLock(text: document.screenplay.elements.map(\.text).joined(separator: "\n"), pageStarts: [0])
        }
        if fontSize != nil || fontFamily != nil { document.typography = try DocumentTypography(fontFamily: fontFamily ?? "Courier", fontSize: fontSize ?? 12) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "LineLayoutCalibration.\(UUID().uuidString)"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let url = directory.appendingPathComponent("fixture.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: url)
        let legacy = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: directory, preferences: prefs)
        let candidate = ScreenplayViewModel(lineLayoutExperiment: mode, loadInitialDocument: false, autosaveDirectory: directory, preferences: prefs)
        legacy.loadOpenScreenplay(at: url); candidate.loadOpenScreenplay(at: url)
        let original = try Data(contentsOf: url)
        try body(legacy, candidate, directory)
        // Rendering alone must not rewrite the disposable file. Editing tests
        // intentionally exercise its autosave; the checked-in source stays intact.
        if !editing { #expect(try Data(contentsOf: url) == original) }
        #expect(try Data(contentsOf: root.appendingPathComponent(path)) == data)
    }

    @Test func fixturesRetainSourceAndProduceConsistentPrintPlans() throws {
        for (name, oldCount) in [("Action-heavy", 24), ("Dialogue-heavy", 30), ("Defenders", 18)] {
            try compare(name) { legacy, candidate, _ in
                #expect(legacy.printedPages.count == oldCount)
                #expect(candidate.printedPages.count < oldCount)
                #expect(candidate.elements == legacy.elements)
                #expect(candidate.printedLayout.unmappedElementIDs.isEmpty)
                let writing = ScreenplayWritingProjection(elements: candidate.elements, casing: candidate.screenplayCasing)
                let plan = try #require(PrintedWritingLayout(print: candidate.printedLayout, writing: writing,
                    typography: candidate.writingTypography, lineLayout: candidate.effectiveLineLayout))
                #expect(plan.labels == candidate.printedPages.map(\.label))
                #expect(!plan.lines.isEmpty)
                let pdf = try #require(PDFDocument(data: candidate.makePrintPDF()))
                #expect(pdf.pageCount == candidate.printedPages.count + 1)
                print("CALIBRATION \(name): legacy=\(oldCount) candidate=\(candidate.printedPages.count)")
                if let output = ProcessInfo.processInfo.environment["SCREENPLAYOS_CALIBRATION_OUTPUT"] {
                    try candidate.makePrintPDF().write(to: URL(fileURLWithPath: output).appendingPathComponent(name + "-candidate.pdf"))
                }
            }
        }
    }


    @Test func speechAndPageTopTrialsPreserveAllTextAndFitPages() throws {
        for mode: ScreenplayLineLayout in [.twelvePointFlowExperiment, .twelvePointPageTopExperiment, .sevenPointGridExperiment, .footerContinuationExperiment, .sentenceAlignedLineExperiment, .sentenceBoundaryExperiment, .headerContinuationExperiment] {
            for name in ["Action-heavy", "Dialogue-heavy", "Defenders"] {
                try compare(name, mode: mode) { legacy, candidate, _ in
                    @MainActor func fragments(_ model: ScreenplayViewModel) -> [UUID: String] {
                        var result: [UUID: String] = [:]
                        for item in model.printedPages.flatMap(\.elements) where !item.isContinuation {
                            result[item.element.id, default: ""] += item.text
                        }
                        return result
                    }
                    #expect(fragments(candidate) == fragments(legacy))
                    #expect(candidate.printedLayout.unmappedElementIDs.isEmpty)
                    let expected = name == "Action-heavy" ? 18 : name == "Defenders" ? 15 : mode.removesPageTopSpacing ? 20 : 21
                    if !mode.usesCharacterGrid { #expect(candidate.printedPages.count == expected) }
                    for (index, page) in candidate.printedPages.enumerated() {
                        if page.elements.last?.text == "(MORE)" {
                            #expect(index + 1 < candidate.printedPages.count)
                            if index + 1 < candidate.printedPages.count {
                                #expect(candidate.printedPages[index + 1].elements.first?.text.hasSuffix("(CONT'D)") == true)
                            }
                        }
                        let body = page.elements.filter { !(mode.continuationInFooter && $0.isContinuation && $0.text == "(MORE)") }
                        #expect(body.map(\.blockHeight).reduce(0, +) <= 648.01)
                        #expect(page.elements.map(\.blockHeight).reduce(0, +) <= (mode.continuationInFooter ? 660.01 : 648.01))
                        if let last = page.elements.last(where: { !$0.isContinuation }) {
                            #expect(last.element.type != .character && last.element.type != .parenthetical)
                        }
                        if mode.removesPageTopSpacing {
                            let first = try #require(page.elements.first)
                            #expect(first.layout.before == (mode.continuationInHeader && first.isContinuation && first.blockHeight == 0 ? -13 : 0))
                        }
                    }
                    let pdf = try #require(PDFDocument(data: candidate.makePrintPDF()))
                    #expect(pdf.pageCount == candidate.printedPages.count + 1)
                    func compact(_ text: String) -> String {
                        text.components(separatedBy: .whitespacesAndNewlines).joined().precomposedStringWithCanonicalMapping
                    }
                    for (i, page) in candidate.printedPages.enumerated() {
                        let extracted = try #require(pdf.page(at: i + 1)?.string)
                        let header = "\(page.label)."
                        var lines = extracted.components(separatedBy: .newlines)
                        let headerIndex = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == header })
                        lines.remove(at: headerIndex)
                        // PDFKit sorts text spatially, sometimes moving a right-aligned
                        // transition or page number. Check glyph coverage here; source
                        // order is checked above and in the external PDF comparison.
                        func counts(_ text: String) -> [Character: Int] {
                            compact(text).reduce(into: [:]) { $0[$1, default: 0] += 1 }
                        }
                        #expect(counts(lines.joined()) == counts(page.elements.map(\.text).joined()))
                    }
                    print("FLOW \(name) \(mode): \(candidate.printedPages.count)")
                    if let output = ProcessInfo.processInfo.environment["SCREENPLAYOS_CALIBRATION_OUTPUT"] {
                        try candidate.makePrintPDF().write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(mode).pdf"))
                    }
                }
            }
        }
    }

    @Test func existingLocksAndOtherFontSizesRetainLegacyLayout() throws {
        for mode: ScreenplayLineLayout in [.twelvePointExperiment, .twelvePointFlowExperiment, .twelvePointPageTopExperiment, .sevenPointGridExperiment, .footerContinuationExperiment, .sentenceAlignedLineExperiment, .sentenceBoundaryExperiment, .headerContinuationExperiment] {
            for locked in [true, false] {
                try compare("Dialogue-heavy", mode: mode, locked: locked, fontSize: locked ? nil : 14) { legacy, candidate, _ in
                    #expect(candidate.effectiveLineLayout == .legacy)
                    #expect(candidate.printedPages.map(\.label) == legacy.printedPages.map(\.label))
                    #expect(candidate.printedPages.flatMap(\.elements).map(\.textHeight) == legacy.printedPages.flatMap(\.elements).map(\.textHeight))
                    #expect(candidate.document == legacy.document)
                }
            }
        }
    }

    @Test(arguments: [0, 1, 2, 3]) func nativeEditorMatchesCandidatePrintLinesAtEveryZoom(sample: Int) throws {
        let synthetic = sample == 2
        try compare("Dialogue-heavy", mode: sample == 0 ? .footerContinuationExperiment : sample == 3 ? .headerContinuationExperiment : .sentenceBoundaryExperiment,
                    dialogueText: synthetic ? String(repeating: "We must wait beside the door. ", count: 12) : nil) { _, candidate, directory in
            if synthetic {
                let suite = "SentenceFooterComparison.\(UUID())"
                let prefs = try #require(UserDefaults(suiteName: suite))
                defer { prefs.removePersistentDomain(forName: suite) }
                let footer = ScreenplayViewModel(lineLayoutExperiment: .footerContinuationExperiment, loadInitialDocument: false,
                                                 autosaveDirectory: directory, preferences: prefs)
                footer.loadOpenScreenplay(at: directory.appendingPathComponent("fixture.json"))
                #expect(candidate.printedPages.map { $0.elements.map(\.text) } != footer.printedPages.map { $0.elements.map(\.text) })
            }
            let original = candidate.document
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: candidate))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let value = view as? WritingTextView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            for zoom in [1.0, 1.25, 0.8] {
                candidate.pageZoom = zoom; host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                let editor = try #require(find(host)), plan = try #require(editor.pagePlan)
                let layout = try #require(editor.layoutManager), container = try #require(editor.textContainer)
                layout.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[layout.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                for (start, line) in plan.lines {
                    let y = try #require(actual[start])
                    #expect(abs(y - line.y) < 0.01)
                }
                #expect(plan.labels == candidate.printedPages.map(\.label))
                for start in plan.lines.keys {
                    editor.setSelectedRange(NSRange(location: start, length: 0))
                    #expect(editor.selectedRange().location == start)
                }
                #expect(candidate.document == original)
            }
        }
    }

    @Test(arguments: [ScreenplayLineLayout.sentenceBoundaryExperiment, .headerContinuationExperiment]) func interiorBreakTypingSelectionAndUndoPreserveSource(mode: ScreenplayLineLayout) throws {
        try compare("Dialogue-heavy", mode: mode, editing: true) { _, candidate, _ in
            let original = candidate.elements
            let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: candidate))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            func find(_ view: NSView) -> WritingTextView? {
                if let value = view as? WritingTextView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            @MainActor func refresh() {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
            refresh()
            let editor = try #require(find(host))
            @MainActor func verify() throws {
                refresh()
                let plan = try #require(editor.pagePlan)
                let fresh = try #require(PrintedWritingLayout(print: candidate.printedLayout,
                    writing: ScreenplayWritingProjection(elements: candidate.elements, casing: candidate.screenplayCasing),
                    typography: candidate.writingTypography, lineLayout: candidate.effectiveLineLayout))
                #expect(plan.lines == fresh.lines)
                #expect(plan.lineBreaks == fresh.lineBreaks)
                let manager = try #require(editor.layoutManager), container = try #require(editor.textContainer)
                manager.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[manager.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                for (start, line) in plan.lines {
                    #expect(abs(try #require(actual[start]) - line.y) < 0.01)
                    if start < editor.string.utf16.count {
                        let glyph = manager.glyphIndexForCharacter(at: start)
                        let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                        let position = manager.location(forGlyphAt: glyph)
                        let point = NSPoint(x: rect.minX + position.x + 0.1, y: rect.midY)
                        #expect(manager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil) == start)
                    }
                }
                #expect(editor.string == ScreenplayWritingProjection(elements: candidate.elements, casing: candidate.screenplayCasing).text)
            }
            try verify()
            let span = try #require(candidate.printedPages.flatMap(\.elements)
                .first { $0.element.type == .dialogue && ($0.sourceSpan?.elementRange.location ?? 0) > 0 }?.sourceSpan)
            let writing = ScreenplayWritingProjection(elements: candidate.elements, casing: candidate.screenplayCasing)
            let boundary = writing.displayRange(span.documentRange).location
            let across = NSRange(location: boundary - 8, length: 16)
            editor.setSelectedRange(across)
            #expect(editor.selectedRange() == across)
            // Requires the macOS pasteboard service, unavailable in a filesystem
            // sandbox. Opt in explicitly for the local native verification run.
            if ProcessInfo.processInfo.environment["SCREENPLAYOS_TEST_PASTEBOARD"] == "1" {
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                #expect(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
                #expect(pasteboard.string(forType: .string) == (writing.text as NSString).substring(with: across))
            }
            editor.insertText(" A café 🛰️ waits. ", replacementRange: across)
            let edited = candidate.elements
            #expect(edited != original)
            try verify()
            candidate.undo(); try verify(); #expect(candidate.elements == original)
            candidate.redo(); try verify(); #expect(candidate.elements == edited)
            candidate.undo(); try verify(); #expect(candidate.elements == original)
            // Removing the space that allowed the original sentence break must
            // recalculate both layouts, without leaving a stale forced boundary.
            editor.setSelectedRange(NSRange(location: boundary - 1, length: 1))
            editor.insertText("", replacementRange: editor.selectedRange())
            try verify()
            candidate.undo(); try verify(); #expect(candidate.elements == original)
        }
    }

    @Test func interiorSentencePreferenceKeepsTwoLinesAndWordBoundaries() {
        let text = "The train arrives. We wait by the door. Another sentence follows."
        let source = text as NSString
        let first = source.range(of: "We wait").location
        let second = source.range(of: "Another").location
        #expect(SentenceAlignedSplit.preferredInteriorEnd(in: text, fittingLineEnds: [12, second + 4]) == second)
        #expect(SentenceAlignedSplit.preferredInteriorEnd(in: text, fittingLineEnds: [first, second - 1]) == second - 1)
        #expect(SentenceAlignedSplit.preferredInteriorEnd(in: text, fittingLineEnds: [12]) == 12)
        #expect(SentenceAlignedSplit.preferredInteriorEnd(in: text, fittingLineEnds: []) == 0)
        let policy = NativeLineBreaks(starts: [10, 20], paragraphs: [NSRange(location: 10, length: 20)])
        #expect(policy.allows(10) && policy.allows(20) && policy.allows(9) && policy.allows(30))
        #expect(!policy.allows(15))
    }

    @Test(arguments: [false, true]) func headerCueGeometryAndLongNameFallback(longName: Bool) throws {
        try compare("Dialogue-heavy", mode: .headerContinuationExperiment,
                    dialogueText: longName ? String(repeating: "We must wait beside the door. ", count: 60) : nil,
                    speakerText: longName ? String(repeating: "VERY LONG CHARACTER NAME ", count: 4) : nil) { _, candidate, _ in
            let writing = ScreenplayWritingProjection(elements: candidate.elements, casing: candidate.screenplayCasing)
            let plan = try #require(PrintedWritingLayout(print: candidate.printedLayout, writing: writing,
                typography: candidate.writingTypography, lineLayout: candidate.effectiveLineLayout))
            var checked = 0
            for (index, page) in candidate.printedPages.enumerated() {
                guard let cue = page.elements.first, cue.isContinuation, cue.text.hasSuffix("(CONT'D)") else { continue }
                checked += 1
                let base = CGFloat(index) * PrintedWritingLayout.stride
                let marker = try #require(plan.marks.first { $0.text == cue.text && abs($0.rect.minY - (base + 72 + cue.layout.before)) < 0.01 })
                if longName {
                    #expect(cue.textHeight > 12)
                    #expect(cue.layout.before == 0)
                    #expect(cue.blockHeight == cue.textHeight)
                    #expect(marker.rect.minY == base + 72)
                } else {
                    #expect(cue.textHeight == 12)
                    #expect(cue.layout.before == -13 && cue.layout.after == 1)
                    #expect(cue.blockHeight == 0)
                    #expect(marker.rect.minY == base + 59)
                }
                let body = try #require(page.elements.first { !$0.isContinuation }?.sourceSpan)
                let firstLine = try #require(plan.lines[writing.displayRange(body.documentRange).location])
                #expect(firstLine.y == base + cue.blockHeight)
            }
            #expect(checked > 0)
        }
    }

    @Test func sentencePreferenceUsesOnlyEligibleNativeBoundaries() {
        let text = "She waits by the door. He stays beside the window. They leave together."
        let source = text as NSString
        let first = source.range(of: "He stays").location
        let second = source.range(of: "They leave").location
        #expect(SentenceAlignedSplit.preferredEnd(in: text, fittingLineEnds: [5, first, second, second + 5]) == second)
        // A sentence ending inside a line cannot become a fabricated line start.
        #expect(SentenceAlignedSplit.preferredEnd(in: text, fittingLineEnds: [5, first + 3]) == first + 3)
        // Do not backtrack to a one-line speech fragment.
        #expect(SentenceAlignedSplit.preferredEnd(in: text, fittingLineEnds: [first, first + 5]) == first + 5)
        #expect(SentenceAlignedSplit.preferredEnd(in: text, fittingLineEnds: []) == 0)
    }

    @Test func sentencePreferencePreservesUnicodeAndWhitespace() {
        let text = "She sees 👩🏽‍🚀 by the door.  He waits for café patrons. They leave."
        let source = text as NSString
        let boundary = source.range(of: "He waits").location
        let end = SentenceAlignedSplit.preferredEnd(in: text, fittingLineEnds: [4, boundary, boundary + 5])
        #expect(end == boundary)
        #expect(source.substring(to: end) + source.substring(from: end) == text)
        #expect(source.substring(from: end).hasPrefix("He waits"))
    }

    @Test func characterGridMeasuresSevenPointsAndRejectsOtherFonts() throws {
        let elements = [ScreenplayElement(type: .dialogue, text: "ABCDEFGHIJ")]
        let storage = NSTextStorage(); let cache = WritingTextRenderCache()
        _ = cache.update(storage, elements: elements, projection: ScreenplayWritingProjection(elements: elements),
            typography: try DocumentTypography(), dark: false, selectedID: nil, nativeEdit: nil, lineLayout: .sevenPointGridExperiment)
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 432, height: 1000))
        container.lineFragmentPadding = 0; layout.addTextContainer(container); layout.ensureLayout(for: container)
        for i in 1..<10 {
            #expect(abs(layout.location(forGlyphAt: i).x - layout.location(forGlyphAt: i - 1).x - 7) < 0.001)
        }
        for mode: ScreenplayLineLayout in [.sevenPointGridExperiment, .footerContinuationExperiment, .sentenceAlignedLineExperiment, .sentenceBoundaryExperiment, .headerContinuationExperiment] {
            try compare("Dialogue-heavy", mode: mode, fontFamily: "Helvetica") { legacy, candidate, _ in
                #expect(candidate.effectiveLineLayout == .legacy)
                #expect(candidate.printedPages.count == legacy.printedPages.count)
            }
        }
    }

    @Test(arguments: [ScreenplayLineLayout.twelvePointExperiment, .sentenceBoundaryExperiment, .headerContinuationExperiment]) func candidateCannotCreateProductionLocks(mode: ScreenplayLineLayout) throws {
        try compare("Dialogue-heavy", mode: mode) { _, candidate, _ in
            let original = candidate.document
            candidate.lockProductionPages()
            #expect(!candidate.pagesAreLocked)
            #expect(candidate.document == original)
        }
    }

    @Test func renderCacheSwitchesPitchWithoutChangingText() throws {
        let elements = [ScreenplayElement(type: .dialogue, text: "One line.\nAnother line.")]
        let projection = ScreenplayWritingProjection(elements: elements)
        let storage = NSTextStorage(); let cache = WritingTextRenderCache()
        for mode: ScreenplayLineLayout in [.legacy, .twelvePointExperiment, .legacy] {
            _ = cache.update(storage, elements: elements, projection: projection, typography: try DocumentTypography(),
                dark: false, selectedID: nil, nativeEdit: nil, lineLayout: mode)
            #expect(storage.string == projection.text)
            let style = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.maximumLineHeight == (mode == .legacy ? 0 : 12))
            #expect(style.lineSpacing == (mode == .legacy ? 2 : 0))
        }
        for scale in [0.8, 1.0, 1.25] {
            let style = ScreenplayBodyLayout.editorStyle(for: .dialogue, scale: scale, lineLayout: .twelvePointExperiment)
            #expect(abs(style.maximumLineHeight - 12 * scale) < 0.001)
        }
    }
}
