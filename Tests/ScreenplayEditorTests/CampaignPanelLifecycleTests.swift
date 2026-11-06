import AppKit
import ApplicationServices
import Darwin
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

/// Hosted native acceptance, not an installed-app/Shortcuts launch or a VoiceOver
/// audit. Exercise the real sheet, SwiftUI controls and AppKit responder chain.
/// SwiftPM has no external AX client, so each presentation requests its own
/// process's lazy accessibility tree before resolving controls by exact identity.
/// The hosted test process completes AppKit launch once before making that request.
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
                #expect(try campaignAXValue(brand) as? String == "Synthetic campaign")
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
            #expect(try campaignAXValue(restored) as? String == name)
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
        #expect(undo.isAccessibilityEnabled?() == false, "A reopened session must not retain the dismissed draft undo stack.")
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
        #expect(try campaignAXValue(brand) as? String == "")
        try await fixture.replaceText("campaign.field.Brand", with: "Second project")
        try await fixture.expectLedger { $0.projectID == replacementID && $0.draft.brief.brand == "Second project" }
        try await fixture.press("campaign.close")
        try await fixture.expectDismissed()
        fixture.model.loadScreenplayOSDocument(at: originalURL)
        #expect(fixture.model.document?.project.id == originalID)
        _ = try await fixture.open()
        let restored = try await fixture.control("campaign.field.Brand")
        #expect(try campaignAXValue(restored) as? String == "First project")
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
                campaignAXElement(in: content) { $0.accessibilityLabel?() == "Cancel Import" } != nil
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
                    campaignAXElement(in: content) { $0.accessibilityLabel?() == "Cancel Reading" } != nil
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
final class CampaignPanelFixture {
    private static let applicationSetup: (application: NSApplication, activationPolicySet: Bool) = {
        // SwiftPM does not run NSApplicationMain. Complete the public AppKit
        // launch setup once so its accessibility server can answer self-process
        // requests. The existing native-UI wait helper services the run loop;
        // starting a second application run loop here would block the tests.
        // https://developer.apple.com/documentation/appkit/nsapplication/finishlaunching()
        let application = NSApplication.shared
        let activationPolicySet = application.setActivationPolicy(.accessory)
        application.finishLaunching()
        return (application, activationPolicySet)
    }()

    let root: URL
    let model: ScreenplayViewModel
    private let hostingController: NSHostingController<CampaignPanelHost>
    let host: NSView
    let window: NSWindow
    let scriptBeforeEdit: String
    private let preferences: UserDefaults
    private let preferencesSuite: String

    init(importLifecycle: CampaignAgencyImportLifecycle? = nil) throws {
        let applicationSetup = Self.applicationSetup
        try #require(applicationSetup.activationPolicySet,
                     "The hosted AppKit process could not set its accessory activation policy.")
        try #require(applicationSetup.application.activationPolicy() == .accessory)
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
        // Install an AppKit view-controller presentation owner, as an application
        // window does, before testing SwiftUI's real sheet presentation chain.
        let hostingController = NSHostingController(rootView: CampaignPanelHost(
            model: model, root: root, importLifecycle: importLifecycle))
        let host = hostingController.view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)
        self.root = root
        self.preferencesSuite = preferencesSuite
        self.preferences = preferences
        self.model = model
        self.scriptBeforeEdit = scriptBeforeEdit
        self.hostingController = hostingController
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
        let attached = try await waitForNativeUI(host) { self.window.attachedSheet != nil }
        if !attached { diagnoseFailure("sheet attachment") }
        try #require(attached, "Campaign binding=\(model.campaignPresented); native sheet attached=\(window.attachedSheet != nil); host belongs to window=\(host.window === window).")
        let sheet = try #require(window.attachedSheet)
        try await requestAccessibilityTree()
        _ = try await control("campaign.close")
        return sheet
    }

    private func requestAccessibilityTree() async throws {
        // SwiftUI creates virtual AX nodes lazily when an accessibility client
        // asks for this process. Make a public, read-only request off MainActor
        // so AppKit can service it. No system-wide permissions or AX preferences
        // are changed. Request only the stable application role, not a window
        // list that other native suites can change while the request is pending.
        // https://developer.apple.com/documentation/applicationservices/axuielement_h
        let result = await Task.detached { () -> (onMainThread: Bool, timeout: AXError, read: AXError?, role: String?) in
            let onMainThread = pthread_main_np() != 0
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            let timeout = AXUIElementSetMessagingTimeout(application, 2)
            guard timeout == .success else { return (onMainThread, timeout, nil, nil) }
            var role: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return (onMainThread, timeout, read, role as? String)
        }.value
        try #require(!result.onMainThread, "The AX request must not block AppKit's main-thread reply.")
        if result.timeout != .success || result.read != .success || result.role != kAXApplicationRole as String {
            let readStatus = result.read.map { String($0.rawValue) } ?? "not attempted"
            diagnoseFailure("accessibility activation timeout=\(result.timeout.rawValue) roleRead=\(readStatus) role=\(String(describing: result.role))")
        }
        try #require(result.timeout == .success, "Self-process AX timeout setup failed: \(result.timeout.rawValue).")
        let read = try #require(result.read, "Self-process AX role read was not attempted.")
        try #require(read == .success, "Self-process AX role read failed: \(read.rawValue).")
        try #require(result.role == kAXApplicationRole as String, "Self-process AX role must identify an application.")
    }

    func expectDismissed() async throws {
        let dismissed = try await waitForNativeUI(host) { !self.model.campaignPresented && self.window.attachedSheet == nil }
        try #require(dismissed, "Campaign's binding and native sheet must both be dismissed.")
    }

    func control(_ identifier: String) async throws -> AnyObject {
        let content = try #require(window.attachedSheet?.contentView)
        let appeared = try await waitForNativeUI(content) {
            campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } != nil
        }
        if !appeared { diagnoseFailure("control \(identifier)") }
        try #require(appeared, "Missing native Campaign control: \(identifier)")
        return try #require(campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier })
    }

    func press(_ identifier: String) async throws {
        let button = try await control(identifier)
        try #require(button.isAccessibilityEnabled?() == true, "Disabled or unavailable Campaign control: \(identifier)")
        try #require(button.accessibilityPerformPress?() == true, "Campaign control rejected its native action: \(identifier)")
    }

    func replaceText(_ identifier: String, with value: String) async throws {
        let field = try await control(identifier)
        let sheet = try #require(window.attachedSheet)
        let content = try #require(sheet.contentView)
        let previouslyFocused = field.isAccessibilityFocused?()
        let previousFrame = field.accessibilityFrame?()
        let nativeScrolls = revealTextField(identifier, in: content, sheet: sheet)
        // Scrolling can replace the AX node. Resolve its exact identity again.
        let current = try await control(identifier)
        let nativeControl: NSTextField?
        if let control = current as? NSTextField {
            // A native representable may expose the text field itself as its
            // AX node. Use that exact object, never a guessed backing view.
            try #require(control.window === sheet && control.isEditable && control.isEnabled,
                "Campaign AX text field must be enabled and editable in this sheet: \(identifier)")
            nativeControl = control
            sheet.makeKey()
            control.selectText(nil)
        } else if let cell = current as? NSCell {
            // NSCell.controlView is a public, exact association, unlike guessing
            // a SwiftUI backing view by class name, position or matching text.
            // https://developer.apple.com/documentation/appkit/nscell/controlview
            let control = try #require(cell.controlView as? NSTextField,
                "Campaign AX text cell has no associated native text field: \(identifier)")
            try #require(control.cell === cell && control.window === sheet && control.isEditable && control.isEnabled,
                "Campaign text cell must belong to its enabled, editable control in this sheet: \(identifier)")
            nativeControl = control
            sheet.makeKey()
            control.selectText(nil)
        } else {
            nativeControl = nil
            let focus = try #require(current.setAccessibilityFocused,
                "Campaign field has no native focus setter: \(identifier)")
            focus(true)
        }
        func expectedEditorIsActive() -> Bool {
            guard let target = campaignAXElement(in: content, matching: { $0.accessibilityIdentifier?() == identifier }),
                  target.isAccessibilityFocused?() == true,
                  let text = sheet.firstResponder as? NSTextView,
                  text.isEditable, !(text is WritingTextView) else { return false }
            if let control = target as? NSTextField {
                return control === nativeControl && control.window === sheet && control.isEditable && control.isEnabled
                    && control.currentEditor() === text
            }
            if let cell = target as? NSCell {
                guard let control = cell.controlView as? NSTextField else { return false }
                return control.cell === cell && control.window === sheet && control.isEditable && control.isEnabled
                    && control.currentEditor() === text
            }
            return nativeControl == nil
        }
        var focused = try await waitForNativeUI(content, until: expectedEditorIsActive)
        var keySteps = 0
        if !focused && nativeControl == nil {
            // A virtual element may expose an AX focus setter without activating
            // AppKit's editor. Use the window's real key-view loop, not guessed
            // click coordinates. A stale AX flag alone cannot satisfy this path:
            // observe it unfocused before accepting a focused editable responder.
            sheet.makeKey()
            sheet.recalculateKeyViewLoop()
            var sawUnfocused = current.isAccessibilityFocused?() == false
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while !focused && keySteps < 64 && ProcessInfo.processInfo.systemUptime < deadline {
                sheet.selectNextKeyView(nil)
                keySteps += 1
                focused = try await waitForNativeUI(content, timeout: 0.05) {
                    let target = campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier }
                    if target?.isAccessibilityFocused?() == false { sawUnfocused = true }
                    return sawUnfocused && expectedEditorIsActive()
                }
            }
        }
        if !focused {
            print("CAMPAIGN_FOCUS identifier=\(identifier) previousAXFocus=\(String(describing: previouslyFocused)) previousFrame=\(String(describing: previousFrame)) currentFrame=\(String(describing: current.accessibilityFrame?())) nativeScrolls=\(nativeScrolls) nativeControl=\(nativeControl != nil) keySteps=\(keySteps) sheetKey=\(sheet.isKeyWindow) responder=\(String(describing: sheet.firstResponder))")
            diagnoseFailure("text focus \(identifier)")
        }
        try #require(focused, "Campaign field did not obtain native text focus: \(identifier)")
        #expect(!WritingTextView.acceptsScriptCommands(in: sheet))
        #expect(!WritingTextView.acceptsScriptCommands(in: window))
        let editor = try #require(sheet.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        editor.insertText(value, replacementRange: editor.selectedRange())
        sheet.makeFirstResponder(content)
    }

    /// Reveal the exact AX-identified field before requesting keyboard focus.
    /// Use only document views whose bounded AX tree contains this same
    /// identifier and the field's reported screen rectangle. NSView's public
    /// scrolling API is available on the application's macOS 13 minimum.
    /// No guessed point, private view class, direct value setter or model edit.
    private func revealTextField(_ identifier: String, in content: NSView, sheet: NSWindow) -> Int {
        var remaining = 400
        var scrolls = 0
        func reveal(in view: NSView, depth: Int = 0) {
            guard depth < 30, remaining > 0 else { return }
            remaining -= 1
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               let field = campaignAXElement(in: document, matching: { $0.accessibilityIdentifier?() == identifier }),
               let frame = field.accessibilityFrame?(), !frame.isEmpty,
               [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) {
                // accessibilityFrame is in screen coordinates; scrollToVisible
                // accepts the document view's local coordinates and performs
                // the minimum scroll. A false result also means already visible.
                // https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:)
                let rectangle = document.convert(sheet.convertFromScreen(frame), from: nil)
                if document.scrollToVisible(rectangle) { scrolls += 1 }
                document.layoutSubtreeIfNeeded()
            }
            for child in view.subviews { reveal(in: child, depth: depth + 1) }
        }
        reveal(in: content)
        return scrolls
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

    private static var diagnosedFailure = false

    /// One bounded dump of this synthetic fixture, only after a native probe fails.
    /// Passing tests never enter this diagnostic path.
    private func diagnoseFailure(_ stage: String) {
        guard !Self.diagnosedFailure else { return }
        Self.diagnosedFailure = true
        print("CAMPAIGN_UI_DIAGNOSTIC BEGIN \(stage)")
        print("binding=\(model.campaignPresented) visible=\(window.isVisible) key=\(window.isKeyWindow) active=\(NSApp.isActive) running=\(NSApp.isRunning) hostMatches=\(host.window === window) controller=\(String(describing: window.contentViewController)) attachedSheet=\(String(describing: window.attachedSheet))")
        var remaining = 200
        var seen = Set<ObjectIdentifier>()
        func describe(_ element: AnyObject, path: String, depth: Int = 0) {
            guard depth < 24, remaining > 0,
                  seen.insert(ObjectIdentifier(element)).inserted else { return }
            remaining -= 1
            let children = element.accessibilityChildren?() ?? []
            print("CAMPAIGN_AX \(path) type=\(type(of: element)) identifier=\(String(describing: element.accessibilityIdentifier?()).prefix(120)) role=\(String(describing: element.accessibilityRole?())) label=\(String(describing: element.accessibilityLabel?()).prefix(120)) frame=\(String(describing: element.accessibilityFrame?())) focused=\(String(describing: element.isAccessibilityFocused?())) children=\(children.count) fullProtocol=\(element is any NSAccessibilityProtocol)")
            for (index, child) in children.enumerated() {
                describe(child as AnyObject, path: "\(path).ax\(index)", depth: depth + 1)
            }
            if let view = element as? NSView {
                for (index, child) in view.subviews.enumerated() {
                    describe(child, path: "\(path).view\(index)", depth: depth + 1)
                }
            }
        }
        if let sheet = window.attachedSheet {
            print("CAMPAIGN_SHEET visible=\(sheet.isVisible) parentMatches=\(sheet.sheetParent === window) responder=\(String(describing: sheet.firstResponder))")
            if let content = sheet.contentView { describe(content, path: "sheet") }
        } else {
            describe(host, path: "host")
        }
        print("CAMPAIGN_UI_DIAGNOSTIC END \(stage)")
    }
}

@MainActor
func campaignAXValue(_ element: AnyObject) throws -> Any? {
    // AppKit declares this ObjC selector with several covariant return types.
    // Supply the general AX signature before invoking it on a virtual node.
    let getter: (() -> Any?)? = element.accessibilityValue
    let read = try #require(getter, "Campaign control has no native accessibility value getter.")
    return read()
}

@MainActor
private func campaignNativeView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let found = view as? T { return found }
    return view.subviews.lazy.compactMap { campaignNativeView(type, in: $0) }.first
}

@MainActor
func campaignAXElement(in root: NSView,
                               matching predicate: (AnyObject) -> Bool) -> AnyObject? {
    var seen = Set<ObjectIdentifier>()
    var remaining = 400
    func search(_ element: AnyObject, depth: Int = 0) -> AnyObject? {
        // Virtual accessibility children can manufacture new wrapper identities.
        // Bound both depth and work even when object-identity cycle detection misses them.
        guard depth < 30, remaining > 0,
              seen.insert(ObjectIdentifier(element)).inserted else { return nil }
        remaining -= 1
        if predicate(element) { return element }
        // SwiftUI's virtual nodes implement public ObjC AX selectors without
        // necessarily declaring conformance to the entire NSAccessibilityProtocol.
        // A protocol cast silently drops those nodes and their stable identifiers.
        for child in element.accessibilityChildren?() ?? [] {
            if let found = search(child as AnyObject, depth: depth + 1) { return found }
        }
        if let view = element as? NSView {
            for child in view.subviews {
                if let found = search(child, depth: depth + 1) { return found }
            }
        }
        return nil
    }
    return search(root)
}
