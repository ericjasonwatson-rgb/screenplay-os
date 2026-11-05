import AppKit
import SwiftUI
import PDFKit
import Testing
@testable import ScreenplayOSApp

@Suite("Native editor rendering", .serialized)
@MainActor
struct NativeEditorTests {
    @Test func fitWidthTracksPanelsWithoutChangingScriptOrSelection() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "FitWidth.\(UUID())", prefs = try #require(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: folder); prefs.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                 with: "INT. ROOM - DAY\n" + String(repeating: "A writer waits beside the window. ", count: 25))
        let original = model.document
        let labels = model.printedPages.map(\.label)
        let host = NSHostingView(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        @MainActor func find(_ view: NSView) -> WritingTextView? {
            if let text = view as? WritingTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        struct Geometry: Equatable {
            let hostBounds: NSRect
            let scrollFrame: NSRect
            let viewportSize: NSSize
            let documentSize: NSSize
            let zoom: CGFloat
            let sidePaneWidths: [CGFloat]
        }
        @MainActor func geometry() -> Geometry? {
            guard let text = find(host), let scroll = text.enclosingScrollView else { return nil }
            var sidePaneWidths: [CGFloat] = []
            var child: NSView = text
            while let parent = child.superview {
                if let split = parent as? NSSplitView, split.isVertical {
                    for sibling in split.arrangedSubviews where sibling !== child
                        && !split.isSubviewCollapsed(sibling) && !sibling.isHiddenOrHasHiddenAncestor
                        && sibling.frame.width > 1 {
                        sidePaneWidths.append(sibling.frame.width)
                    }
                }
                child = parent
            }
            return Geometry(hostBounds: host.bounds, scrollFrame: scroll.convert(scroll.bounds, to: host),
                viewportSize: scroll.contentSize, documentSize: text.frame.size, zoom: scroll.magnification,
                sidePaneWidths: sidePaneWidths)
        }
        @MainActor func settle(until condition: @MainActor () -> Bool = { true }) async throws {
            var previous: Geometry?
            var stableSince = ProcessInfo.processInfo.systemUptime
            // Fit can be correct for a transient pane width. Service native commits
            // until both the requested state and geometry have stopped changing.
            let settled = try await waitForNativeUI(host) {
                let current = geometry()
                let now = ProcessInfo.processInfo.systemUptime
                guard current != nil, current == previous, condition() else {
                    previous = current
                    stableSince = now
                    return false
                }
                return now - stableSince >= 0.1
            }
            #expect(settled, "Native fit geometry did not settle: \(String(describing: previous))")
        }
        try await settle()
        let text = try #require(find(host)), scroll = try #require(text.enclosingScrollView)
        let selection = NSRange(location: 20, length: 6)
        text.setSelectedRange(selection)
        model.fitWritingPageWidth = true
        // ScreenplayPageView gives ScriptPageWell a 760 * pageZoom fixed-width
        // cap outside Fit Width. In this wide window, fitting must lift that cap,
        // not only update native magnification inside the old fixed-width well.
        let fixedPageWellWidth = CGFloat(760 * model.pageZoom)
        var zooms: [CGFloat] = []
        var geometries: [Geometry] = []
        for narrow in [false, true, false] {
            model.navigationVisible = narrow; model.contextAssistantVisible = narrow
            let requestedSize = narrow ? NSSize(width: 1000, height: 700) : NSSize(width: 1440, height: 900)
            window.setContentSize(requestedSize)
            try await settle {
                guard let current = geometry(), find(host) === text, text.pagePlan != nil,
                      abs(current.hostBounds.width - requestedSize.width) < 1,
                      current.sidePaneWidths.count == (narrow ? 2 : 0),
                      narrow || current.scrollFrame.width > fixedPageWellWidth,
                      abs(text.frame.width * scroll.magnification - scroll.contentSize.width) < 1,
                      abs(scroll.documentVisibleRect.minX) < 1 else { return false }
                guard let wide = geometries.first else { return true }
                return narrow ? scroll.contentSize.width < wide.viewportSize.width
                    : abs(scroll.contentSize.width - wide.viewportSize.width) < 1
            }
            zooms.append(scroll.magnification)
            geometries.append(try #require(geometry()))
            #expect(abs(text.frame.width * scroll.magnification - scroll.contentSize.width) < 1)
            #expect(abs(scroll.documentVisibleRect.minX) < 1)
            #expect(text.selectedRange() == selection)
            #expect(model.document == original)
            #expect(model.printedPages.map(\.label) == labels)
            #expect(text.pagePlan != nil)
            if let directory = ProcessInfo.processInfo.environment["SCREENPLAYOS_FIT_CAPTURE_DIR"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent(narrow ? "fit-narrow.png" : "fit-wide.png"))
            }
        }
        #expect(zooms[1] < zooms[0])
        #expect(abs(geometries[2].viewportSize.width - geometries[0].viewportSize.width) < 1,
            "Wide viewport geometry: \(geometries)")
        #expect(abs(zooms[2] - zooms[0]) < 0.01, "Fit zoom geometry: \(geometries)")
        let fitted = scroll.magnification
        model.adjustPageZoom(by: -0.05)
        try await settle { abs(scroll.magnification - (fitted - 0.05)) < 0.001 }
        #expect(!model.fitWritingPageWidth)
        #expect(abs(scroll.magnification - (fitted - 0.05)) < 0.001)
        model.fitWritingPageWidth = true
        try await settle { abs(text.frame.width * scroll.magnification - scroll.contentSize.width) < 1 }
        model.pageZoom = 1.25
        try await settle { abs(scroll.magnification - 1.25) < 0.001 }
        #expect(!model.fitWritingPageWidth)
        #expect(abs(scroll.magnification - 1.25) < 0.001)
        #expect(text.selectedRange() == selection)
        #expect(model.document == original)
        // A fixed scale reached from Fit Width also works in the scene preview.
        model.pageZoom = 0.25
        let preview = NSHostingView(rootView: SceneScreenplayPreview(model: model))
        window.contentView = preview
        @MainActor func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        let previewSettled = try await waitForNativeUI(preview) {
            guard let scroll = findScroll(preview) else { return false }
            return abs(scroll.magnification - 0.25) < 0.001
        }
        #expect(previewSettled)
        #expect(abs(try #require(findScroll(preview)).magnification - 0.25) < 0.001)
        #expect(model.document == original)
    }

    @Test func nativeTypingSelectionFormattingAndUndoRemainConsistent() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "NativeEditorTests.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.newDocument()
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                 with: "INT. ROOM - DAY\nFirst action.\nLast action.")
        let host = NSHostingView(rootView: ContinuousScreenplayEditor(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func refresh() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        refresh()
        let view = try #require(find(host))
        let original = model.writingText
        let selectionSignal = model.chromeState.signal(for: .elementType, model: model)
        let documentBeforeSelection = model.document
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let firstElement = try #require(model.elements.first)
        #expect(selectionSignal.value == .fields([firstElement.id.uuidString, firstElement.type.rawValue]))
        #expect(model.document == documentBeforeSelection)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText(" 👩🏽‍🚀", replacementRange: view.selectedRange())
        refresh()
        #expect(view.string == model.writingText)
        #expect(view.string == original + " 👩🏽‍🚀")
        #expect(view.selectedRange().location == (view.string as NSString).length)
        model.undo()
        refresh()
        #expect(view.string == original)
        model.redo()
        refresh()
        #expect(view.string == original + " 👩🏽‍🚀")
        let last = try #require(model.elements.last)
        model.setType(.dialogue, for: last.id)
        refresh()
        let range = try #require(model.writingRanges.last)
        let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(Double(style.headIndent) - 72 * model.pageZoom) < 0.001)
        // Native one-paragraph edits retain dialogue formatting, including Unicode.
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText(" More dialogue.", replacementRange: view.selectedRange())
        refresh()
        let typedStyle = try #require(view.textStorage?.attribute(.paragraphStyle, at: (view.string as NSString).length - 1, effectiveRange: nil) as? NSParagraphStyle)
        #expect(typedStyle.headIndent == 72)
        // Replacing identical text across Action/Dialogue can preserve IDs and text
        // while AppKit applies the first paragraph's typing style to the replacement.
        let actionRange = model.writingRanges[1]
        let dialogueRange = model.writingRanges[2]
        let crossParagraph = NSRange(location: actionRange.location + 1,
            length: dialogueRange.location + 3 - actionRange.location - 1)
        let sameText = (view.string as NSString).substring(with: crossParagraph)
        let beforePaste = model.writingText
        view.setSelectedRange(crossParagraph)
        view.insertText(sameText, replacementRange: crossParagraph)
        refresh()
        #expect(view.string == beforePaste)
        let pastedStyle = try #require(view.textStorage?.attribute(.paragraphStyle, at: model.writingRanges[2].location + 1, effectiveRange: nil) as? NSParagraphStyle)
        #expect(pastedStyle.headIndent == 72)
        model.undo()
        refresh()
        #expect(view.string == beforePaste)
        let selection = NSRange(location: 0, length: 10)
        view.setSelectedRange(selection)
        model.contextAssistantVisible.toggle()
        refresh()
        #expect(view.selectedRange() == selection)
        model.pageZoom = 1.2
        refresh()
        let zoomStyle = try #require(view.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(zoomStyle.headIndent - 72) < 0.001)
    }
    @Test func completeWindowPreservesWritingThroughPaneChangesAndReopening() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "WritingJourney.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx")
        let copy = folder.appendingPathComponent("fixture.fdx")
        try FileManager.default.copyItem(at: fixture, to: copy)
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.loadFDX(at: copy)
        let host = NSHostingView(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func refresh() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        refresh()
        let text = try #require(find(host))
        let original = model.writingText
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        text.insertText(" Writing check.", replacementRange: text.selectedRange())
        refresh()
        #expect(model.writingText == original + " Writing check.")
        model.undo()
        refresh()
        #expect(find(host)?.string == ScreenplayWritingProjection(elements: model.elements).text)
        model.redo()
        refresh()
        let selection = NSRange(location: 100, length: 12)
        try #require(find(host)).setSelectedRange(selection)
        for focused in [true, false] {
            model.focusMode = focused
            refresh()
            #expect(find(host)?.selectedRange() == selection)
        }
        for visible in [false, true] {
            model.navigationVisible = visible
            model.contextAssistantVisible = visible
            refresh()
            #expect(find(host)?.selectedRange() == selection)
        }
        window.setContentSize(NSSize(width: 900, height: 560))
        refresh()
        #expect(find(host)?.selectedRange() == selection)
        let scene = try #require(model.scenes.last)
        model.selectElement(id: scene.elementID)
        refresh()
        model.setWorkflowMode(.outline)
        refresh()
        #expect(model.selectedSceneBreakdown?.elementID == scene.elementID)
        model.setWorkflowMode(.writing)
        refresh()
        #expect(model.selectedSceneBreakdown?.elementID == scene.elementID)
        #expect(find(host)?.string == ScreenplayWritingProjection(elements: model.elements).text)
        model.save()
        #expect(model.prepareToClose())
        let saved = model.writingText
        let reopened = ScreenplayViewModel(autosaveDirectory: folder, preferences: prefs)
        #expect(reopened.writingText == saved)
        #expect(reopened.printedPages.map(\.label) == model.printedPages.map(\.label))
        #expect(try Data(contentsOf: copy) == Data(contentsOf: fixture))
    }

    @Test func titleEditorPreviewUpdatesAndRecoversFromOverflow() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "TitleEditorPreview.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.newDocument()
        let host = NSHostingView(rootView: ScreenplayTitlePageEditor(model: model).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 810, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        window.orderFront(nil)
        @MainActor func findPDF(_ view: NSView) -> TitlePagePDFCanvas? {
            if let pdf = view as? TitlePagePDFCanvas { return pdf }
            return view.subviews.lazy.compactMap { findPDF($0) }.first
        }
        let initialPreview = try await waitForNativeUI(host) { findPDF(host)?.document?.pageCount == 1 }
        nativeUIHierarchyDiagnostic("title initial", host: host, window: window, model: model)
        #expect(initialPreview)
        #expect(findPDF(host)?.document?.pageCount == 1)
        model.titlePageBinding(.title).wrappedValue = "An obsolete title"
        model.titlePageBinding(.title).wrappedValue = "The Revised Title"
        let revisedPreview = try await waitForNativeUI(host) {
            findPDF(host)?.document?.string?.contains("The Revised Title") == true
        }
        nativeUIHierarchyDiagnostic("title revised", host: host, window: window, model: model)
        #expect(revisedPreview)
        #expect(findPDF(host)?.document?.string?.contains("The Revised Title") == true)
        #expect(findPDF(host)?.document?.string?.contains("obsolete") == false)
        model.titlePageBinding(.contact).wrappedValue = String(repeating: "Too much contact information\n", count: 100)
        let invalidPreviewRemoved = try await waitForNativeUI(host) { findPDF(host) == nil }
        nativeUIHierarchyDiagnostic("title overflow", host: host, window: window, model: model)
        #expect(invalidPreviewRemoved)
        #expect(findPDF(host) == nil)
        model.titlePageBinding(.contact).wrappedValue = "writer@example.com"
        let recoveredPreview = try await waitForNativeUI(host) {
            findPDF(host)?.document?.string?.contains("writer@example.com") == true
        }
        nativeUIHierarchyDiagnostic("title recovered", host: host, window: window, model: model)
        #expect(recoveredPreview)
        #expect(findPDF(host)?.document?.string?.contains("writer@example.com") == true)
        if let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_TITLE_PREVIEW_CAPTURE"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Opt-in profiling through the same test target in Debug and Release.
    /// Test-process-only selection; never a saved application preference.
    private func stressLineLayout() throws -> ScreenplayLineLayout {
        let value = ProcessInfo.processInfo.environment["SCREENPLAYOS_STRESS_LAYOUT"] ?? "legacy"
        switch value {
        case "legacy": return .legacy
        case "header": return .headerContinuationExperiment
        default:
            throw NSError(domain: "ScreenplayOSStress", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown stress layout: \(value)"])
        }
    }

    /// Timing is recorded, never used as a flaky pass/fail threshold.
    @Test func longScriptTypingBenchmarkWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_FIXTURE"] else { return }
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "TypingBenchmark.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let url = folder.appendingPathComponent("script.json")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
        let model = ScreenplayViewModel(lineLayoutExperiment: try stressLineLayout(), loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.loadScreenplayOSDocument(at: url)
        #expect(model.effectiveLineLayout == (try stressLineLayout()))
        _ = try #require(model.document, "Benchmark fixture failed to load: \(model.errorMessage ?? "unknown error")")
        #expect(!model.elements.isEmpty)
        model.navigationVisible = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_NAVIGATOR"] == "1"
        model.contextAssistantVisible = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_CONTEXT"] == "1"
        model.focusMode = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_FOCUS"] == "1"
        let host = NSHostingView(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func find(_ view: NSView) -> WritingTextView? {
            if let text = view as? WritingTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        let text = try #require(find(host))
        #expect(text.string == ScreenplayWritingProjection(elements: model.elements).text)
        window.makeFirstResponder(text)
        print("SCREENPLAYOS_BENCHMARK_PAGES=\(model.printedPages.count) ELEMENTS=\(model.elements.count)")
        let position = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_POSITION"] ?? "end"
        print("SCREENPLAYOS_BENCHMARK_POSITION=\(position) NAVIGATOR=\(model.navigationVisible) CONTEXT=\(model.contextAssistantVisible) FOCUS=\(model.focusMode)")
        // Preserve the original workload by default; opt in to isolate typing after navigation.
        let settleNavigation = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_SETTLE_NAVIGATION"] == "1"
        print("SCREENPLAYOS_BENCHMARK_SETTLE_NAVIGATION=\(settleNavigation)")
        var navigationMilliseconds: [Double] = []
        var navigationPhases: [[Double]] = []
        var milliseconds: [Double] = []
        var phases: [[Double]] = []
        let iterations = Int(ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_ITERATIONS"] ?? "15") ?? 15
        try #require((1...1000).contains(iterations))
        print("SCREENPLAYOS_BENCHMARK_ITERATIONS=\(iterations)")
        for _ in 0..<iterations {
            let source = text.string as NSString
            let searchStart = position == "middle" ? source.length / 2 : 0
            let newline = source.range(of: "\n", range: NSRange(location: searchStart, length: source.length - searchStart))
            let offset = position == "end" || newline.location == NSNotFound ? source.length : NSMaxRange(newline)
            let navigationStart = ProcessInfo.processInfo.systemUptime
            text.setSelectedRange(NSRange(location: offset, length: 0))
            let selectedAt = ProcessInfo.processInfo.systemUptime
            if settleNavigation {
                text.scrollRangeToVisible(text.selectedRange())
                let scrolledAt = ProcessInfo.processInfo.systemUptime
                host.layoutSubtreeIfNeeded()
                let layoutAt = ProcessInfo.processInfo.systemUptime
                // Give selection/page observers a separate turn before timing input.
                try await Task.sleep(nanoseconds: 1_000_000)
                host.layoutSubtreeIfNeeded()
                let deferredAt = ProcessInfo.processInfo.systemUptime
                host.displayIfNeeded()
                let displayedAt = ProcessInfo.processInfo.systemUptime
                navigationPhases.append([selectedAt - navigationStart, scrolledAt - selectedAt, layoutAt - scrolledAt, deferredAt - layoutAt, displayedAt - deferredAt].map { $0 * 1000 })
            }
            navigationMilliseconds.append((ProcessInfo.processInfo.systemUptime - navigationStart) * 1000)
            let start = ProcessInfo.processInfo.systemUptime
            text.insertText("x", replacementRange: text.selectedRange())
            let insertedAt = ProcessInfo.processInfo.systemUptime
            host.layoutSubtreeIfNeeded()
            let laidOutAt = ProcessInfo.processInfo.systemUptime
            // Allow main-queue observation to settle, then include any resulting layout.
            try await Task.sleep(nanoseconds: 1_000_000)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let finishedAt = ProcessInfo.processInfo.systemUptime
            milliseconds.append((finishedAt - start) * 1000)
            phases.append([(insertedAt - start) * 1000, (laidOutAt - insertedAt) * 1000, (finishedAt - laidOutAt) * 1000])
            #expect(text.string == ScreenplayWritingProjection(elements: model.elements).text)
        }
        print("SCREENPLAYOS_NAVIGATION_PHASES_MS=\(navigationPhases)")
        print("SCREENPLAYOS_NAVIGATION_MS=\(navigationMilliseconds)")
        print("SCREENPLAYOS_TYPING_MS=\(milliseconds)")
        print("SCREENPLAYOS_TYPING_PHASES_MS=\(phases)")
        if let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_BENCHMARK_SCREENSHOT"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        #expect(model.prepareToClose())
        let savedURL = try #require(model.saveURL)
        let reopened = ScreenplayViewModel(lineLayoutExperiment: try stressLineLayout(), loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        reopened.loadScreenplayOSDocument(at: savedURL)
        _ = try #require(reopened.document)
        #expect(reopened.elements == model.elements)
        #expect(reopened.writingTypography == model.writingTypography)
        #expect(reopened.printedPages.map(\.label) == model.printedPages.map(\.label))
        #expect(ScreenplayWritingProjection(elements: reopened.elements).text == text.string)
    }

    @Test func longScriptUIStressWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENPLAYOS_STRESS_FIXTURE"] else { return }
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "UIStress.\(UUID())"
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            prefs.removePersistentDomain(forName: suite)
        }
        let originalBytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let url = folder.appendingPathComponent("stress.json")
        try originalBytes.write(to: url)
        let model = ScreenplayViewModel(lineLayoutExperiment: try stressLineLayout(), loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
        model.loadScreenplayOSDocument(at: url)
        #expect(model.effectiveLineLayout == (try stressLineLayout()))
        _ = try #require(model.document)
        let host = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func find(_ view: NSView) -> WritingTextView? {
            if let text = view as? WritingTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let automaticLayout = ProcessInfo.processInfo.environment["SCREENPLAYOS_STRESS_AUTOMATIC_LAYOUT"] == "1"
        func settle() async throws {
            if !automaticLayout { host.layoutSubtreeIfNeeded() }
            try await Task.sleep(nanoseconds: 50_000_000)
            if !automaticLayout {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }
        }
        try await settle()
        for cycle in 0..<30 {
            let authored = model.elements
            model.navigationVisible = cycle % 2 == 0
            model.contextAssistantVisible = cycle % 3 != 0
            model.pageZoom = [0.75, 1.0, 1.5][cycle % 3]
            window.setContentSize(cycle % 2 == 0 ? NSSize(width: 1440, height: 900) : NSSize(width: 1000, height: 700))
            try await settle()
            #expect(model.elements == authored)
            let text = try #require(find(host))
            let projection = ScreenplayWritingProjection(elements: model.elements)
            let index = [1, model.elements.count / 2, model.elements.count - 1][cycle % 3]
            text.setSelectedRange(NSRange(location: NSMaxRange(projection.ranges[index]), length: 0))
            text.scrollRangeToVisible(text.selectedRange())
            let before = model.writingText
            let addition = cycle % 5 == 0 ? "\nStress café 👩🏽‍🚀." : " test"
            text.insertText(addition, replacementRange: text.selectedRange())
            try await settle()
            let after = model.writingText
            #expect(after != before)
            #expect(text.string == ScreenplayWritingProjection(elements: model.elements).text)
            #expect(NSMaxRange(text.selectedRange()) <= (text.string as NSString).length)
            if cycle % 3 == 0 {
                model.undo(); try await settle()
                #expect(model.writingText == before)
                model.redo(); try await settle()
                #expect(model.writingText == after)
            }
            if cycle % 4 == 0 {
                let last = ScreenplayWritingProjection(elements: model.elements).ranges[index]
                text.setSelectedRange(last)
                model.toggleWritingEmphasis(\.bold)
                try await settle()
                #expect(model.writingText == after)
            }
            let page = [0, model.printedPages.count / 2, model.printedPages.count - 1][cycle % 3]
            model.navigateToPrintedPage(page)
            try await settle()
            #expect(text.string == ScreenplayWritingProjection(elements: model.elements).text)
            #expect(text.pagePlan != nil)
            if ProcessInfo.processInfo.environment["SCREENPLAYOS_STRESS_VERIFY_GEOMETRY"] == "1" {
                let plan = try #require(text.pagePlan)
                let layout = try #require(text.layoutManager), container = try #require(text.textContainer)
                layout.ensureLayout(for: container)
                var actual: [Int: CGFloat] = [:]
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                    actual[layout.characterIndexForGlyph(at: glyphs.location)] = rect.minY
                }
                // A trailing empty paragraph has no glyphs; AppKit exposes its
                // caret row separately from enumerateLineFragments.
                if text.string.isEmpty || text.string.hasSuffix("\n") {
                    #expect(layout.extraLineFragmentTextContainer === container)
                    actual[(text.string as NSString).length] = layout.extraLineFragmentRect.minY
                }
                for (start, line) in plan.lines {
                    let y = try #require(actual[start], "Missing native line at UTF-16 offset \(start)")
                    #expect(abs(y - line.y) < 0.01)
                }
                #expect(plan.labels == model.printedPages.map(\.label))
            }
            if cycle < 3, let capturePath = ProcessInfo.processInfo.environment["SCREENPLAYOS_STRESS_CAPTURE_DIR"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: capturePath).appendingPathComponent("layout-\(cycle).png"))
            }
            #expect(model.prepareToClose())
            let reopened = ScreenplayViewModel(lineLayoutExperiment: try stressLineLayout(), loadInitialDocument: false, autosaveDirectory: folder, preferences: prefs)
            reopened.loadScreenplayOSDocument(at: try #require(model.saveURL))
            #expect(reopened.elements == model.elements)
            #expect(reopened.writingTypography == model.writingTypography)
            print("SCREENPLAYOS_UI_STRESS_CYCLE=\(cycle + 1)")
        }
        let pdf = try #require(PDFDocument(data: model.makePrintPDF()))
        #expect(pdf.pageCount >= model.printedPages.count)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == originalBytes)
        print("SCREENPLAYOS_UI_STRESS_PASSED=30")
    }

}
