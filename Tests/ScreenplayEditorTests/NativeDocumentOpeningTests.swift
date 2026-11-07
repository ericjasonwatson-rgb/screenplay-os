import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Native document opening", .serialized)
@MainActor
struct NativeDocumentOpeningTests {
    @Test func latestStartupRequestWaitsForWindowAndIsConsumedOnce() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let first = try nativeOpeningDocument(in: fixture.root, name: "First.screenplayos.json")
        let latest = try nativeOpeningDocument(in: fixture.root, name: "Latest.open-screenplay.json", legacy: true)
        let original = fixture.model.document
        let delegate = AppDelegate()
        delegate.application(NSApp, open: [first])
        delegate.application(NSApp, open: [latest])
        delegate.model = fixture.model
        #expect(fixture.model.document == original, "A model alone is not native-window readiness.")
        let probe = NativeDocumentWindow.Probe(model: fixture.model, opening: delegate.nativeDocumentOpening)
        fixture.host.addSubview(probe)
        let opened = try await waitForNativeUI(fixture.host) { fixture.model.sourceURL == latest }
        try #require(opened)
        #expect(fixture.model.recentDocuments.first?.url == latest)
        #expect(!fixture.model.recentDocuments.contains { $0.url == first })
        let element = try #require(fixture.model.elements.last)
        fixture.model.binding(for: element).wrappedValue = "Later local edit"
        let edited = fixture.model.document
        for _ in 0..<3 { delegate.nativeDocumentOpening.attach(window: fixture.window, model: fixture.model) }
        await drainNativeOpeningCallbacks()
        #expect(fixture.model.document == edited)
        #expect(fixture.model.canUndo)
        fixture.model.undo()
        #expect(fixture.model.elements.last?.text == "Synthetic action.")
    }

    @Test func laterNewCommandOrRejectedBatchCancelsStartupIntent() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let source = try nativeOpeningDocument(in: fixture.root, name: "Queued.json")
        for cancellation in 0..<3 {
            let opening = NativeDocumentOpening()
            opening.bind(fixture.model)
            #expect(opening.open([source]))
            if cancellation == 0 {
                // The same method used by File > New/Open/Recent/Recover also
                // handles cancellation of a subsequently cancelled open picker.
                opening.cancelPendingRequest()
            } else if cancellation == 1 {
                fixture.model.newDocument()
            } else {
                #expect(!opening.open([source, source]))
            }
            let current = fixture.model.document
            let probe = NativeDocumentWindow.Probe(model: fixture.model, opening: opening)
            fixture.host.addSubview(probe)
            await drainNativeOpeningCallbacks()
            #expect(fixture.model.document == current)
            #expect(fixture.model.sourceURL != source)
            probe.removeFromSuperview()
        }
    }

    @Test func nativeLegacyAndValidatedJSONKeepTheirExactSourceBytes() throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        for (name, legacy) in [("Native.screenplayos.json", false), ("Legacy.open-screenplay.json", true), ("Generic.JSON", false)] {
            let source = try nativeOpeningDocument(in: fixture.root, name: name, legacy: legacy)
            let bytes = try Data(contentsOf: source)
            #expect(opening.open([source]))
            #expect(fixture.model.sourceURL == source)
            #expect(fixture.model.saveURL == source)
            #expect(fixture.model.elements.last?.text == "Synthetic action.")
            #expect(try Data(contentsOf: source) == bytes)
        }
    }

    @Test func unknownFieldsUseExistingProtectedCopyReaderWithoutChangingSource() throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let source = try nativeOpeningDocument(in: fixture.root, name: "Future.screenplayos.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any])
        json["future_authored_field"] = ["keep": "Synthetic future content"]
        let bytes = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: source)
        let opening = attachedOpening(fixture)
        #expect(opening.open([source]))
        #expect(fixture.model.saveURL == nil)
        #expect(fixture.model.sourceURL == source)
        #expect(fixture.model.errorMessage?.contains("opened as a copy") == true)
        #expect(try Data(contentsOf: source) == bytes)
        let before = fixture.model.document
        #expect(opening.open([source]))
        #expect(fixture.model.document == before)
        #expect(try Data(contentsOf: source) == bytes)
        let element = try #require(fixture.model.elements.last)
        fixture.model.binding(for: element).wrappedValue = "Edit saved to the protected copy"
        #expect(fixture.model.saveURL != nil && fixture.model.saveURL != source)
        #expect(fixture.model.sourceURL == source)
        let copy = fixture.model.document
        try Data("{broken".utf8).write(to: source)
        #expect(!opening.open([source]), "A stale sourceURL is not evidence that the reader succeeded.")
        #expect(fixture.model.document == copy)
        #expect(opening.notice?.contains("Document not opened") == true)
    }

    @Test func unsupportedMissingMalformedAndBatchRequestsDoNotReplaceCurrentDocument() throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        let valid = try nativeOpeningDocument(in: fixture.root, name: "Valid.json")
        let malformed = fixture.root.appendingPathComponent("Malformed.screenplayos.json")
        let foreign = fixture.root.appendingPathComponent("Foreign.json")
        let folder = fixture.root.appendingPathComponent("Folder.json")
        try Data("{broken".utf8).write(to: malformed)
        try Data("{\"format\":\"foreign\",\"format_version\":\"1.0\"}".utf8).write(to: foreign)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let unsupported = ["pdf", "docx", "txt", "fdx", "screenplay"].map { fixture.root.appendingPathComponent("Foreign." + $0) }
        for url in unsupported { try Data(contentsOf: valid).write(to: url) }
        let original = fixture.model.document
        let selection = fixture.model.selectedElementID
        let caret = fixture.model.documentCaretToken
        let currentURL = try #require(fixture.model.saveURL)
        let currentBytes = try Data(contentsOf: currentURL)
        let urls = unsupported + [malformed, foreign, folder, fixture.root.appendingPathComponent("Missing.json"),
            try #require(URL(string: "https://example.invalid/Script.json")),
            try #require(URL(string: "screenplayos://open/Script.json")),
            try #require(URL(string: "file://remote.invalid/Script.json")),
            try #require(URL(string: valid.absoluteString + "?query=1")),
            try #require(URL(string: valid.absoluteString + "#fragment"))]
        for batch in urls.map({ [$0] }) + [[], [valid, malformed]] {
            #expect(!opening.open(batch))
            #expect(opening.notice != nil)
            #expect(fixture.model.document == original)
            #expect(fixture.model.selectedElementID == selection)
            #expect(fixture.model.documentCaretToken == caret)
            #expect(fixture.model.canUndo)
            #expect(try Data(contentsOf: currentURL) == currentBytes)
            #expect(fixture.model.sourceURL != valid)
        }
        #expect(try Data(contentsOf: malformed) == Data("{broken".utf8))
    }

    @Test func repeatedActiveFilePreservesUnsavedEditsSelectionUndoAndDiskConflict() throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        let active = try #require(fixture.model.saveURL)
        let originalBytes = try Data(contentsOf: active)
        let externalBytes = originalBytes + Data("\n ".utf8)
        try externalBytes.write(to: active)
        let element = try #require(fixture.model.elements.last)
        fixture.model.binding(for: element).wrappedValue = "Unsaved local draft must survive"
        let edited = fixture.model.document
        #expect(fixture.model.hasUnsavedChanges)
        #expect(fixture.model.saveProblem != nil)
        let selection = fixture.model.selectedElementID
        let caret = fixture.model.documentCaretToken
        let alias = fixture.root.appendingPathComponent("Alias.screenplayos.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: active)
        for url in [active, active, alias] {
            #expect(opening.open([url]))
            #expect(fixture.model.document == edited)
            #expect(fixture.model.selectedElementID == selection)
            #expect(fixture.model.documentCaretToken == caret)
            #expect(fixture.model.hasUnsavedChanges)
            #expect(fixture.model.canUndo)
            #expect(try Data(contentsOf: active) == externalBytes)
        }
        let replacement = try nativeOpeningDocument(in: fixture.root, name: "Replacement.json")
        let replacementBytes = try Data(contentsOf: replacement)
        #expect(!opening.open([replacement]))
        #expect(fixture.model.document == edited)
        #expect(fixture.model.selectedElementID == selection)
        #expect(fixture.model.canUndo)
        #expect(try Data(contentsOf: active) == externalBytes)
        #expect(try Data(contentsOf: replacement) == replacementBytes)
        try originalBytes.write(to: active)
        fixture.model.undo()
        #expect(fixture.model.elements.last?.text == element.text)
        #expect(opening.open([replacement]))
        #expect(try Data(contentsOf: replacement) == replacementBytes)
    }

    @Test func campaignSheetRejectsOpenWithoutChangingDraftFocusOrReplayingAfterClose() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let script = try await fixture.scriptEditor()
        let selection = NSRange(location: 5, length: 4)
        script.setSelectedRange(selection)
        #expect(fixture.window.makeFirstResponder(script))
        let opening = attachedOpening(fixture)
        let source = try nativeOpeningDocument(in: fixture.root, name: "Other.json")
        _ = try await fixture.open()
        try await fixture.replaceText("campaign.field.Brand", with: "Synthetic campaign remains current")
        try await fixture.expectLedger { $0.draft.brief.brand == "Synthetic campaign remains current" }
        let original = fixture.model.document
        let projectID = try #require(original?.project.id)
        let campaignURL = try fixture.campaignURL(projectID: projectID)
        let campaignBytes = try Data(contentsOf: campaignURL)
        let sheet = try #require(fixture.window.attachedSheet)
        let responder = sheet.firstResponder
        #expect(!opening.open([source]))
        #expect(opening.notice?.contains("try opening the file again") == true)
        #expect(fixture.model.document == original)
        #expect(sheet.firstResponder === responder)
        #expect(script.selectedRange() == selection)
        #expect(try Data(contentsOf: campaignURL) == campaignBytes)
        try await fixture.press("campaign.close")
        try await fixture.expectDismissed()
        opening.attach(window: fixture.window, model: fixture.model)
        _ = try await waitForNativeUI(fixture.host) { fixture.window.firstResponder === script }
        #expect(fixture.model.document == original, "Closing the panel must not replay the rejected command.")
        #expect(fixture.model.canUndo)
        #expect(opening.open([source]), "Only a fresh user retry may open the other document.")
        #expect(try Data(contentsOf: campaignURL) == campaignBytes)
        #expect(fixture.model.document?.project.id != projectID)
        let newSession = CampaignWorkspaceSession(projectID: try #require(fixture.model.document?.project.id), root: fixture.root)
        #expect(newSession.ledger.draft.brief.brand.isEmpty)
    }

    @Test func presentationFlagsAndNativeFilePickerRejectWithoutDeferredOpen() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        let source = try nativeOpeningDocument(in: fixture.root, name: "Other.json")
        let original = fixture.model.document
        let flags: [ReferenceWritableKeyPath<ScreenplayViewModel, Bool>] = [
            \.campaignPresented, \.titlePagePresented, \.dialogueAssistantPresented,
            \.continuityBiblePresented, \.convertedCopyInProgress, \.portableExportInProgress,
            \.commandPaletteVisible
        ]
        // No run-loop turn between setting and clearing: cover the guard before
        // a SwiftUI presentation has attached its native sheet.
        for flag in flags {
            fixture.model[keyPath: flag] = true
            #expect(!opening.open([source]))
            fixture.model[keyPath: flag] = false
            #expect(fixture.model.document == original)
        }
        let panel = NSOpenPanel()
        panel.directoryURL = fixture.root
        panel.beginSheetModal(for: fixture.window) { _ in }
        let presented = try await waitForNativeUI(fixture.host) { fixture.window.attachedSheet != nil }
        try #require(presented)
        #expect(!opening.open([source]))
        panel.cancel(nil)
        let dismissed = try await waitForNativeUI(fixture.host) { fixture.window.attachedSheet == nil }
        try #require(dismissed)
        opening.attach(window: fixture.window, model: fixture.model)
        await drainNativeOpeningCallbacks()
        #expect(fixture.model.document == original)
        #expect(fixture.model.sourceURL != source)
    }

    @Test func modelReplacementAndOldWindowCallbacksCannotRetargetPendingWork() async throws {
        let first = try CampaignPanelFixture(); defer { first.close() }
        let second = try CampaignPanelFixture(); defer { second.close() }
        let delegate = AppDelegate()
        delegate.model = first.model
        let source = try nativeOpeningDocument(in: first.root, name: "Queued.json")
        delegate.application(NSApp, open: [source])
        delegate.model = second.model
        let originalFirst = first.model.document
        let originalSecond = second.model.document
        let opening = delegate.nativeDocumentOpening
        opening.attach(window: second.window, model: second.model)
        opening.activate(window: first.window, model: first.model)
        opening.detach(window: first.window, model: first.model)
        await drainNativeOpeningCallbacks()
        #expect(first.model.document == originalFirst)
        #expect(second.model.document == originalSecond)
        #expect(opening.model === second.model)
        delegate.application(NSApp, open: [source])
        #expect(second.model.sourceURL == source)
        #expect(first.model.document == originalFirst)
    }

    @Test func deallocatedModelCannotLeaveAnOpeningForItsReplacement() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = NativeDocumentOpening()
        let suite = "NativeOpening-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var oldModel: ScreenplayViewModel? = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: fixture.root, preferences: preferences)
        opening.bind(oldModel)
        let source = try nativeOpeningDocument(in: fixture.root, name: "Stale.json")
        #expect(opening.open([source]))
        oldModel = nil
        #expect(opening.model == nil)
        let current = fixture.model.document
        opening.attach(window: fixture.window, model: fixture.model)
        await drainNativeOpeningCallbacks()
        #expect(fixture.model.document == current)
        #expect(fixture.model.sourceURL != source)
    }

    @Test func windowRecreationWaitsForNewAttachmentAndUsesLatestIntent() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        let source = try nativeOpeningDocument(in: fixture.root, name: "First.json")
        let latest = try nativeOpeningDocument(in: fixture.root, name: "Latest.json")
        let firstProbe = NativeDocumentWindow.Probe(model: fixture.model, opening: opening)
        fixture.host.addSubview(firstProbe)
        fixture.window.close()
        #expect(opening.window == nil, "A real native close must clear readiness.")
        var requests = 0
        opening.reopenWindow = { requests += 1 }
        let original = fixture.model.document
        #expect(opening.open([source]))
        #expect(opening.open([latest]))
        #expect(requests == 1, "Repeated events must not create a window per file.")
        #expect(fixture.model.document == original)
        // Host the actual window probe in a fresh native window. SwiftUI's
        // installed-app openWindow scene dispatch is a separate external gate.
        let host = NSHostingController(rootView: ContentView(model: fixture.model))
        let reopened = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        reopened.isReleasedWhenClosed = false
        defer { reopened.close() }
        reopened.contentViewController = host
        let probe = NativeDocumentWindow.Probe(model: fixture.model, opening: opening)
        host.view.addSubview(probe)
        reopened.makeKeyAndOrderFront(nil)
        let opened = try await waitForNativeUI(host.view) { fixture.model.sourceURL == latest }
        #expect(opened)
        #expect(opening.window === reopened)
        #expect(!fixture.model.recentDocuments.contains { $0.url == source })
    }

    @Test func newerNativeCommandWinsBeforeDeferredReadinessCallback() async throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let first = try nativeOpeningDocument(in: fixture.root, name: "Queued.json")
        let latest = try nativeOpeningDocument(in: fixture.root, name: "Newer.json")
        let opening = NativeDocumentOpening()
        #expect(opening.open([first]))
        opening.attach(window: fixture.window, model: fixture.model)
        #expect(opening.open([latest]))
        await drainNativeOpeningCallbacks()
        #expect(fixture.model.sourceURL == latest)
        #expect(!fixture.model.recentDocuments.contains { $0.url == first })
    }

    @Test func activeWindowChangesDoNotLetOldWindowCallbacksReplaceTheTarget() throws {
        let fixture = try CampaignPanelFixture(); defer { fixture.close() }
        let opening = attachedOpening(fixture)
        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        opening.attach(window: otherWindow, model: fixture.model)
        #expect(opening.window === otherWindow)
        opening.activate(window: fixture.window, model: fixture.model)
        opening.detach(window: otherWindow, model: fixture.model)
        opening.activate(window: otherWindow, model: fixture.model)
        #expect(opening.window === fixture.window)
        let source = try nativeOpeningDocument(in: fixture.root, name: "CurrentWindow.json")
        #expect(opening.open([source]))
        #expect(fixture.model.legacyWindow === fixture.window)
        #expect(fixture.model.sourceURL == source)
    }

    private func attachedOpening(_ fixture: CampaignPanelFixture) -> NativeDocumentOpening {
        let opening = NativeDocumentOpening()
        opening.attach(window: fixture.window, model: fixture.model)
        return opening
    }
}

@MainActor
private func nativeOpeningDocument(in root: URL, name: String, legacy: Bool = false) throws -> URL {
    let script = Screenplay(metadata: ScreenplayMetadata(title: name), elements: [
        ScreenplayElement(type: .sceneHeading, text: "INT. SYNTHETIC ROOM - DAY"),
        ScreenplayElement(type: .action, text: "Synthetic action.")
    ])
    let project = Project(metadata: ProjectMetadata(title: name, author: "Synthetic Fixture"), screenplayID: script.id)
    let document = ScreenplayOSDocument(format: legacy ? "open-screenplay" : "screenplayos", project: project, screenplay: script)
    let url = root.appendingPathComponent(name)
    try (JSONEncoder.screenplayOSEncoder().encode(document) + Data("\n ".utf8)).write(to: url)
    return url
}

@MainActor
private func drainNativeOpeningCallbacks() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
