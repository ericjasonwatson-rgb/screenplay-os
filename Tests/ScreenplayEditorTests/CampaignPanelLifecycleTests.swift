import AppKit
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

/// Hosted native acceptance, not an installed-app/Shortcuts launch or a VoiceOver
/// audit. Exercise the real sheet, SwiftUI controls and AppKit responder chain.
@Suite("Campaign panel lifecycle", .serialized)
@MainActor
struct CampaignPanelLifecycleTests {
    @Test func closeEscapeAndReopenPreserveDraftAndScriptContext() async throws {
        let fixture = try CampaignPanelFixture()
        defer { fixture.close() }
        let script = try await fixture.scriptEditor()
        let selection = NSRange(location: 5, length: 4)
        script.setSelectedRange(selection)
        #expect(fixture.window.makeFirstResponder(script))
        #expect(WritingTextView.acceptsScriptCommands(in: fixture.window))
        let document = fixture.model.document
        let projectID = try #require(document?.project.id)
        let screenplayURL = try #require(fixture.model.saveURL)
        let screenplayBytes = try Data(contentsOf: screenplayURL)

        for index in 0..<3 {
            let sheet = try await fixture.open()
            let content = try #require(sheet.contentView)
            #expect(content.bounds.width >= 720 && content.bounds.width <= 1000)
            #expect(content.bounds.height >= 540 && content.bounds.height <= 900)
            #expect(!WritingTextView.acceptsScriptCommands(in: fixture.window))
            #expect(!WritingTextView.acceptsScriptCommands(in: sheet))
            if index == 0 {
                try await fixture.replaceText("campaign.field.Brand", with: "Synthetic campaign")
                try await fixture.expectLedger { $0.draft.brief.brand == "Synthetic campaign" }
            } else {
                let brand = try await fixture.control("campaign.field.Brand")
                #expect(brand.accessibilityValue() as? String == "Synthetic campaign")
            }
            #expect(fixture.model.document == document)
            #expect(try Data(contentsOf: screenplayURL) == screenplayBytes)
            #expect(script.selectedRange() == selection)
            #expect(fixture.model.canUndo)

            if index == 1 {
                // Exercise the registered cancel key equivalent, rather than
                // directly changing the sheet binding or invoking dismiss().
                let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                    isARepeat: false, keyCode: 53))
                #expect(sheet.performKeyEquivalent(with: escape))
            } else {
                try await fixture.press("campaign.close")
            }
            try await fixture.expectDismissed()
            #expect(fixture.window.firstResponder === script)
            #expect(WritingTextView.acceptsScriptCommands(in: fixture.window))
        }
        let saved = try fixture.ledger(projectID: projectID)
        fixture.model.undo()
        #expect(fixture.model.writingText == fixture.scriptBeforeEdit)
        #expect(try fixture.ledger(projectID: projectID) == saved,
                "Screenplay Undo must not consume or mutate the campaign's separate draft history.")
    }

    @Test func repeatedNativeEditsAddRemoveAndUndoStayInCampaign() async throws {
        let fixture = try CampaignPanelFixture()
        defer { fixture.close() }
        _ = try await fixture.scriptEditor()
        let original = fixture.model.document
        _ = try await fixture.open()
        var previousBrand = ""

        for index in 1...3 {
            let brand = "Synthetic brand \(index)"
            try await fixture.replaceText("campaign.field.Brand", with: brand)
            try await fixture.expectLedger { $0.draft.brief.brand == brand }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0.draft.brief.brand == previousBrand }
            try await fixture.replaceText("campaign.field.Brand", with: brand)
            try await fixture.expectLedger { $0.draft.brief.brand == brand }
            previousBrand = brand

            try await fixture.press("campaign.deliverable.add")
            try await fixture.expectLedger { $0.draft.deliverables.count == 1 }
            let item = try #require(try fixture.ledger().draft.deliverables.first)
            let name = "Synthetic cutdown \(index)"
            try await fixture.replaceText("campaign.deliverable.name.\(item.id)", with: name)
            try await fixture.expectLedger { $0.draft.deliverables.first?.name == name }
            try await fixture.press("campaign.deliverable.remove.\(item.id)")
            try await fixture.expectLedger { $0.draft.deliverables.isEmpty }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger {
                $0.draft.deliverables.count == 1 && $0.draft.deliverables.first?.id == item.id
                    && $0.draft.deliverables.first?.name == name
            }
            let restored = try await fixture.control("campaign.deliverable.name.\(item.id)")
            #expect(restored.accessibilityValue() as? String == name)
            try await fixture.press("campaign.deliverable.remove.\(item.id)")
            try await fixture.expectLedger { $0.draft.deliverables.isEmpty }
            #expect(fixture.model.document == original)
            #expect(fixture.model.canUndo)
        }
        try await fixture.press("campaign.close")
        try await fixture.expectDismissed()
        _ = try await fixture.open()
        #expect(try fixture.ledger().draft.brief.brand == previousBrand)
        #expect(try fixture.ledger().draft.deliverables.isEmpty)
        let undo = try await fixture.control("campaign.undo")
        #expect(!undo.isAccessibilityEnabled(), "A reopened session must not retain the dismissed draft undo stack.")
        #expect(fixture.model.document == original)
    }

    @Test func projectReplacementDismissesOldSessionBeforeReopening() async throws {
        let fixture = try CampaignPanelFixture()
        defer { fixture.close() }
        _ = try await fixture.scriptEditor()
        let originalID = try #require(fixture.model.document?.project.id)
        let originalURL = try #require(fixture.model.saveURL)
        _ = try await fixture.open()
        try await fixture.replaceText("campaign.field.Brand", with: "First project")
        try await fixture.expectLedger { $0.draft.brief.brand == "First project" }
        let originalCampaign = try Data(contentsOf: fixture.campaignURL(projectID: originalID))

        // The host deliberately recomputes the same conditional sheet content as
        // ScreenplayOSApp. A changed init argument must not rebind its StateObject.
        fixture.model.newDocument()
        let replacementID = try #require(fixture.model.document?.project.id)
        #expect(replacementID != originalID)
        try await fixture.expectDismissed()
        #expect(try Data(contentsOf: fixture.campaignURL(projectID: originalID)) == originalCampaign)
        #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))

        _ = try await fixture.open()
        let brand = try await fixture.control("campaign.field.Brand")
        #expect(brand.accessibilityValue() as? String == "")
        try await fixture.replaceText("campaign.field.Brand", with: "Second project")
        try await fixture.expectLedger { $0.projectID == replacementID && $0.draft.brief.brand == "Second project" }
        try await fixture.press("campaign.close")
        try await fixture.expectDismissed()
        fixture.model.loadScreenplayOSDocument(at: originalURL)
        #expect(fixture.model.document?.project.id == originalID)
        _ = try await fixture.open()
        let restored = try await fixture.control("campaign.field.Brand")
        #expect(restored.accessibilityValue() as? String == "First project")
        #expect(try Data(contentsOf: fixture.campaignURL(projectID: originalID)) == originalCampaign)
    }

    @Test func leavingAgencyTabAndClosingPanelDiscardUnimportedPreview() async throws {
        let lifecycle = CampaignAgencyImportLifecycle { _ in
            let text = "Synthetic agency source. Never imported."
            return .init(filename: "Synthetic.txt", bytes: Data(text.utf8), text: text)
        }
        let fixture = try CampaignPanelFixture(importLifecycle: lifecycle)
        defer { fixture.close() }
        _ = try await fixture.scriptEditor()
        _ = try await fixture.open()
        let projectID = try #require(fixture.model.document?.project.id)

        for closePanel in [false, true] {
            try await fixture.selectTab("Agency Sources")
            let reading = try #require(lifecycle.chooseSource(revising: nil) {
                fixture.root.appendingPathComponent("Synthetic.txt")
            })
            await reading.value
            let content = try #require(fixture.window.attachedSheet?.contentView)
            let previewShown = try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityLabel() == "Cancel Import" } != nil
            }
            #expect(previewShown)
            #expect(lifecycle.preview != nil)
            if closePanel {
                try await fixture.press("campaign.close")
                try await fixture.expectDismissed()
            } else {
                try await fixture.selectTab("Brief & Deliverables")
            }
            let discarded = try await waitForNativeUI(fixture.host) {
                lifecycle.preview == nil && !lifecycle.isReading && lifecycle.previewDocumentID == nil
            }
            #expect(discarded)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: projectID).path))
        }
        _ = try await fixture.open()
        try await fixture.selectTab("Agency Sources")
        #expect(lifecycle.preview == nil)
        #expect(try fixture.ledger().draft.agency == nil)
    }

    @Test func leavingAgencyTabAndClosingPanelRejectLateReadResult() async throws {
        let reader = ControlledAgencyReader()
        let lifecycle = CampaignAgencyImportLifecycle { try await reader.read($0) }
        let fixture = try CampaignPanelFixture(importLifecycle: lifecycle)
        defer { fixture.close() }
        _ = try await fixture.scriptEditor()
        _ = try await fixture.open()
        let projectID = try #require(fixture.model.document?.project.id)

        for (index, closePanel) in [false, true].enumerated() {
            try await fixture.selectTab("Agency Sources")
            let url = fixture.root.appendingPathComponent("Synthetic-\(index).txt")
            let observation = try #require(lifecycle.chooseSource(revising: nil) { url })
            #expect(await reader.waitForRequest(index) == url)
            do {
                let content = try #require(fixture.window.attachedSheet?.contentView)
                let readingShown = try await waitForNativeUI(content) {
                    campaignAXElement(in: content) { $0.accessibilityLabel() == "Cancel Reading" } != nil
                }
                #expect(readingShown)
                #expect(lifecycle.isReading)
                if closePanel {
                    try await fixture.press("campaign.close")
                    try await fixture.expectDismissed()
                } else {
                    try await fixture.selectTab("Brief & Deliverables")
                }
                let cancelled = try await waitForNativeUI(fixture.host) { !lifecycle.isReading }
                #expect(cancelled, "Native disappearance must revoke the read before the parser returns.")
            } catch {
                // Never leave a suspended synthetic parser behind if a native
                // assertion throws before the normal late-result step.
                await reader.finish(index, with: .failure(CancellationError()))
                await observation.value
                throw error
            }
            let text = "Synthetic late result \(index)"
            await reader.finish(index, with: .success(.init(filename: url.lastPathComponent,
                                                          bytes: Data(text.utf8), text: text)))
            await observation.value
            #expect(await reader.wasCancelled(index))
            #expect(lifecycle.preview == nil)
            #expect(lifecycle.problem == nil)
            #expect(!lifecycle.isReading)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: projectID).path))
        }
        _ = try await fixture.open()
        try await fixture.selectTab("Agency Sources")
        #expect(lifecycle.preview == nil)
        #expect(try fixture.ledger().draft.agency == nil)
    }
}

@MainActor
private struct CampaignPanelHost: View {
    @ObservedObject var model: ScreenplayViewModel
    let root: URL
    let importLifecycle: CampaignAgencyImportLifecycle?

    var body: some View {
        ContentView(model: model)
            .sheet(isPresented: $model.campaignPresented) {
                if let projectID = model.document?.project.id {
                    CampaignWorkspaceView(model: model, projectID: projectID, root: root,
                                          importLifecycle: importLifecycle)
                }
            }
    }
}

@MainActor
private final class CampaignPanelFixture {
    let root: URL
    let model: ScreenplayViewModel
    let host: NSHostingView<CampaignPanelHost>
    let window: NSWindow
    let scriptBeforeEdit: String
    private let preferences: UserDefaults
    private let preferencesSuite: String

    init(importLifecycle: CampaignAgencyImportLifecycle? = nil) throws {
        _ = NSApplication.shared
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent("CampaignPanel-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let preferencesSuite = "CampaignPanel-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesSuite))
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root,
            preferences: preferences, recoveryDirectory: root.appendingPathComponent("Recovery"),
            continuityBibleRoot: root, editAudioRoot: root)
        model.newDocument()
        let scriptBeforeEdit = model.writingText
        model.replaceWritingText(in: NSRange(location: 0, length: (model.writingText as NSString).length),
                                 with: "INT. SYNTHETIC ROOM - DAY\nA producer reviews the campaign.")
        let host = NSHostingView(rootView: CampaignPanelHost(model: model, root: root, importLifecycle: importLifecycle))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        self.root = root
        self.preferencesSuite = preferencesSuite
        self.preferences = preferences
        self.model = model
        self.scriptBeforeEdit = scriptBeforeEdit
        self.host = host
        self.window = window
    }

    func close() {
        model.campaignPresented = false
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        window.close()
        preferences.removePersistentDomain(forName: preferencesSuite)
        try? FileManager.default.removeItem(at: root)
    }

    func scriptEditor() async throws -> WritingTextView {
        let appeared = try await waitForNativeUI(host) { campaignNativeView(WritingTextView.self, in: self.host) != nil }
        try #require(appeared)
        return try #require(campaignNativeView(WritingTextView.self, in: host))
    }

    func open() async throws -> NSWindow {
        model.campaignPresented = true
        let appeared = try await waitForNativeUI(host) {
            guard let content = self.window.attachedSheet?.contentView else { return false }
            content.layoutSubtreeIfNeeded()
            return campaignAXElement(in: content) { $0.accessibilityIdentifier() == "campaign.close" } != nil
        }
        try #require(appeared, "The actual native Campaign sheet did not appear.")
        return try #require(window.attachedSheet)
    }

    func expectDismissed() async throws {
        let dismissed = try await waitForNativeUI(host) { !self.model.campaignPresented && self.window.attachedSheet == nil }
        try #require(dismissed, "Campaign's binding and native sheet must both be dismissed.")
    }

    func control(_ identifier: String) async throws -> any NSAccessibilityProtocol {
        let content = try #require(window.attachedSheet?.contentView)
        let appeared = try await waitForNativeUI(content) {
            campaignAXElement(in: content) { $0.accessibilityIdentifier() == identifier } != nil
        }
        try #require(appeared, "Missing native Campaign control: \(identifier)")
        return try #require(campaignAXElement(in: content) { $0.accessibilityIdentifier() == identifier })
    }

    func press(_ identifier: String) async throws {
        let button = try await control(identifier)
        try #require(button.isAccessibilityEnabled(), "Disabled Campaign control: \(identifier)")
        try #require(button.accessibilityPerformPress(), "Campaign control rejected its native action: \(identifier)")
    }

    func replaceText(_ identifier: String, with value: String) async throws {
        let field = try await control(identifier)
        let sheet = try #require(window.attachedSheet)
        let content = try #require(sheet.contentView)
        field.setAccessibilityFocused(true)
        let focused = try await waitForNativeUI(content) {
            guard let text = sheet.firstResponder as? NSTextView else { return false }
            return text.isEditable && !(text is WritingTextView)
        }
        try #require(focused, "Campaign field did not obtain native text focus: \(identifier)")
        #expect(!WritingTextView.acceptsScriptCommands(in: sheet))
        #expect(!WritingTextView.acceptsScriptCommands(in: window))
        let editor = try #require(sheet.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        editor.insertText(value, replacementRange: editor.selectedRange())
        sheet.makeFirstResponder(content)
    }

    func selectTab(_ label: String) async throws {
        let content = try #require(window.attachedSheet?.contentView)
        let tabs = try #require(campaignNativeView(NSTabView.self, in: content))
        let item = try #require(tabs.tabViewItems.first { $0.label == label })
        tabs.selectTabViewItem(item)
        let selected = try await waitForNativeUI(content) { tabs.selectedTabViewItem === item }
        try #require(selected)
    }

    func campaignURL(projectID: UUID) throws -> URL {
        try CampaignWorkspaceStore.url(projectID: projectID, root: root)
    }

    func ledger(projectID: UUID? = nil) throws -> CampaignLedger {
        let id = try #require(projectID ?? model.document?.project.id)
        return try CampaignWorkspaceStore.load(projectID: id, from: campaignURL(projectID: id)).ledger
    }

    func expectLedger(_ condition: @MainActor (CampaignLedger) -> Bool) async throws {
        let content = try #require(window.attachedSheet?.contentView)
        let committed = try await waitForNativeUI(content) {
            guard let value = try? self.ledger() else { return false }
            return condition(value)
        }
        try #require(committed, "The native action did not persist the expected campaign state.")
    }
}

@MainActor
private func campaignNativeView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let found = view as? T { return found }
    return view.subviews.lazy.compactMap { campaignNativeView(type, in: $0) }.first
}

@MainActor
private func campaignAXElement(in root: NSView,
                               matching predicate: (any NSAccessibilityProtocol) -> Bool) -> (any NSAccessibilityProtocol)? {
    var seen = Set<ObjectIdentifier>()
    var remaining = 400
    func search(_ value: Any, depth: Int = 0) -> (any NSAccessibilityProtocol)? {
        // Virtual accessibility children can manufacture new wrapper identities.
        // Bound both depth and work even when object-identity cycle detection misses them.
        guard depth < 30, remaining > 0, let element = value as? any NSAccessibilityProtocol,
              seen.insert(ObjectIdentifier(element as AnyObject)).inserted else { return nil }
        remaining -= 1
        if predicate(element) { return element }
        for child in element.accessibilityChildren() ?? [] {
            if let found = search(child, depth: depth + 1) { return found }
        }
        if let view = value as? NSView {
            for child in view.subviews {
                if let found = search(child, depth: depth + 1) { return found }
            }
        }
        return nil
    }
    return search(root)
}
