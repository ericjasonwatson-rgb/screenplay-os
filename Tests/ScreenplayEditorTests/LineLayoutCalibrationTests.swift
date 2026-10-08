import AppKit
import PDFKit
import SwiftUI
import Testing
import ScreenplayDomain
import ScreenplayFDX
@testable import ScreenplayOSApp

@Suite("Line layout calibration") @MainActor
struct LineLayoutCalibrationTests {
    private func compare(_ name: String, mode: ScreenplayLineLayout = .twelvePointExperiment, locked: Bool = false, fontSize: Double? = nil, body: (ScreenplayViewModel, ScreenplayViewModel, URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = name == "Defenders" ? "Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx" : "Docs/AuditEvidence/pagination-2026-10-08/\(name).fdx"
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        var document = try FDXImporter().importData(data, title: name).document
        if locked {
            document.screenplay.pageLock = ProductionPageLock(text: document.screenplay.elements.map(\.text).joined(separator: "\n"), pageStarts: [0])
        }
        if let fontSize { document.typography = try DocumentTypography(fontSize: fontSize) }
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
        // Calibration and rendering must never autosave a different layout into the fixture.
        #expect(try Data(contentsOf: url) == original)
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
        for mode: ScreenplayLineLayout in [.twelvePointFlowExperiment, .twelvePointPageTopExperiment] {
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
                    #expect(candidate.printedPages.count == expected)
                    for (index, page) in candidate.printedPages.enumerated() {
                        if page.elements.last?.text == "(MORE)" {
                            #expect(index + 1 < candidate.printedPages.count)
                            if index + 1 < candidate.printedPages.count {
                                #expect(candidate.printedPages[index + 1].elements.first?.text.hasSuffix("(CONT'D)") == true)
                            }
                        }
                        #expect(page.elements.map(\.blockHeight).reduce(0, +) <= 648.01)
                        if let last = page.elements.last(where: { !$0.isContinuation }) {
                            #expect(last.element.type != .character && last.element.type != .parenthetical)
                        }
                        if mode.removesPageTopSpacing { #expect(page.elements.first?.layout.before == 0) }
                    }
                    let pdf = try #require(PDFDocument(data: candidate.makePrintPDF()))
                    #expect(pdf.pageCount == candidate.printedPages.count + 1)
                    print("FLOW \(name) \(mode): \(candidate.printedPages.count)")
                    if let output = ProcessInfo.processInfo.environment["SCREENPLAYOS_CALIBRATION_OUTPUT"] {
                        try candidate.makePrintPDF().write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(mode).pdf"))
                    }
                }
            }
        }
    }

    @Test func existingLocksAndOtherFontSizesRetainLegacyLayout() throws {
        for mode: ScreenplayLineLayout in [.twelvePointExperiment, .twelvePointFlowExperiment, .twelvePointPageTopExperiment] {
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

    @Test func nativeEditorMatchesCandidatePrintLinesAtEveryZoom() throws {
        try compare("Dialogue-heavy", mode: .twelvePointPageTopExperiment) { _, candidate, _ in
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
            }
        }
    }

    @Test func candidateCannotCreateProductionLocks() throws {
        try compare("Dialogue-heavy") { _, candidate, _ in
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
