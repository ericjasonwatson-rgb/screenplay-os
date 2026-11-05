import AppKit
import SwiftUI

@main
struct ScreenplayOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ScreenplayViewModel(takeRoot: TakeWorkflow.applicationSupportRoot)

    private var packageFieldEditor: NSTextView? {
        guard model.packageEditor != nil, let text = NSApp.keyWindow?.firstResponder as? NSTextView,
              text.isFieldEditor else { return nil }
        return text
    }

    private func performScriptCommand(_ command: () -> Void) {
        guard WritingTextView.acceptsScriptCommands(in: NSApp.keyWindow) else { return }
        command()
    }

    private var scriptCommandsDisabled: Bool {
        !model.scriptEditorFocused || model.campaignPresented || model.titlePagePresented ||
        model.dialogueAssistantPresented || model.boardGenerationSnapshot != nil || model.generationConsentPreview != nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .sheet(isPresented: $model.campaignPresented) {
                    if let projectID = model.document?.project.id {
                        CampaignWorkspaceView(model: model, projectID: projectID)
                    }
                }
                .onAppear { appDelegate.model = model; model.enablePackageWindows() }
                .background(DocumentCloseGuard(model: model))
                .frame(minWidth: 900, idealWidth: 1200, minHeight: 560, idealHeight: 760)
        }
        .defaultSize(width: 1200, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit ScreenplayOS") { appDelegate.requestQuit() }
                    .keyboardShortcut("q", modifiers: [.command])
            }
            CommandGroup(replacing: .appInfo) {
                Group {
                    Button("About ScreenplayOS", action: AppBranding.showAbout)
                }.disabled(model.packageSheetOpen || model.campaignPresented)
            }
            CommandGroup(replacing: .newItem) {
                Group {
                    Button("New Screenplay") {
                        model.newDocument()
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    .help("Start a screenplay with Outline, Script, Shot, Boards, and Edit.")

                    Menu("Experimental Features") {
                        Button("New Writing-Only Screenplay", action: model.newPackage)
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                            .help("Creates a separate writing-only document. Outline, Shot, Boards, Edit, and title-page editing are not available in this editor.")
                    }

                    Button("Open...") {
                        model.showOpenPanel()
                    }
                    .keyboardShortcut("o", modifiers: [.command])

                    Menu("Recover Unsaved Draft") {
                        ForEach(model.recoveryCopies) { copy in
                            Button("\(copy.title) — \(copy.savedAt.formatted())") {
                                model.openRecoveryCopy(copy)
                            }
                        }
                    }
                    .disabled(model.recoveryCopies.isEmpty)

                    Menu("Recover Package Edits") {
                        Button("Refresh Recovery List", action: model.refreshPackageRecoveries)
                        ForEach(model.packageRecoveries) { record in
                            Button("\(record.title) — \(record.savedAt.formatted())") { model.openPackageRecovery(record) }
                        }
                    }
                    Menu("Open Recent") {
                        if model.recentDocuments.isEmpty {
                            Text("No Recent Scripts")
                        } else {
                            ForEach(model.recentDocuments) { recent in
                                Button(recent.name) {
                                    model.openDocument(at: recent.url)
                                }
                            }
                        }
                    }
                }.disabled(model.packagePreview != nil || model.campaignPresented)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command])
                Divider()
                Group {
                    Button("Save") {
                        model.save()
                    }
                    .keyboardShortcut("s", modifiers: [.command])

                    Button("Save As...") {
                        model.showSavePanel()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button("Save Converted Copy…", action: model.showConvertedCopyPanel)
                        .disabled(model.document == nil || model.convertedCopyInProgress)

                    Button("Export PDF...") {
                        model.showExportPDFPanel()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button("Export Final Draft FDX…", action: model.showExportFDXPanel)
                        .disabled(model.document == nil && model.packageEditor == nil)

                    Button("Export Portable Project Copy…") { model.exportPortableProject() }
                        .disabled(model.document == nil || model.packageEditor != nil || model.portableExportInProgress)

                    Button("Export Report...") {
                        model.showExportReportPanel()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .option])

                    Button("Export Premiere EDL…") {
                        model.selectedProductionExportKind = .premiereEDL
                        model.showProductionExportPanel()
                    }
                    Button("Export Final Cut Pro XML…") {
                        model.selectedProductionExportKind = .finalCutXML
                        model.showProductionExportPanel()
                    }

                    Button("Export Edit File...") {
                        model.showProductionExportPanel()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                }.disabled(model.packageSheetOpen || model.campaignPresented)
                if let editor = model.packageEditor {
                    Button("Save Package") { editor.saveCurrent() }
                        .keyboardShortcut("s", modifiers: [.command])
                    Button("Save Package As…") { editor.savePanel() }.keyboardShortcut("s", modifiers: [.command, .shift])
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Group {
                    Button("Undo") {
                        if let field = packageFieldEditor { field.undoManager?.undo() }
                        else if let editor = model.packageEditor { editor.undo() } else { model.undo() }
                    }
                    .keyboardShortcut("z", modifiers: [.command])
                    .disabled(packageFieldEditor == nil && !(model.packageEditor?.canUndo ?? model.canUndo))
                    Button("Redo") {
                        if let field = packageFieldEditor { field.undoManager?.redo() }
                        else if let editor = model.packageEditor { editor.redo() } else { model.redo() }
                    }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(packageFieldEditor == nil && !(model.packageEditor?.canRedo ?? model.canRedo))
                }.disabled(model.packagePreview != nil || model.campaignPresented)
            }
            CommandGroup(after: .textEditing) {
                if let editor = model.packageEditor {
                    Button("Find…", action: editor.showFind).keyboardShortcut("f", modifiers: [.command])
                    Button("Find Next") { editor.navigateFind() }.keyboardShortcut("g", modifiers: [.command])
                    Button("Find Previous") { editor.navigateFind(backward: true) }.keyboardShortcut("g", modifiers: [.command, .shift])
                }
            }
            CommandMenu("Campaign") {
                Button("Campaign Brief & Scope…") { model.campaignPresented = true }
                    .disabled(model.document == nil || model.packageSheetOpen || model.campaignPresented
                              || model.titlePagePresented || model.dialogueAssistantPresented
                              || model.continuityBiblePresented || model.boardGenerationSnapshot != nil
                              || model.generationConsentPreview != nil || model.generationCostLedger != nil
                              || model.convertedCopyReceipt != nil)
            }
            CommandMenu("Workspace") {
                Group {
                    Picker("Mode", selection: Binding(
                        get: { model.workflowMode },
                        set: { model.setWorkflowMode($0) }
                    )) {
                        ForEach(WorkflowMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Workspace", selection: $model.sidebarMode) {
                        ForEach(model.sidebarModesForCurrentWorkflow) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Divider()

                    Toggle("Show Navigation", isOn: $model.navigationVisible)
                        .keyboardShortcut("0", modifiers: [.command, .option])

                    Toggle("Show Context Inspector", isOn: $model.contextAssistantVisible)
                        .keyboardShortcut("a", modifiers: [.command, .option])

                    Toggle("Focus Mode", isOn: $model.focusMode)
                        .keyboardShortcut("f", modifiers: [.command, .shift])

                    Toggle("Dark Page", isOn: $model.darkPageMode)
                        .keyboardShortcut("d", modifiers: [.command, .shift])

                    Divider()

                    Button("Zoom In") {
                        model.adjustPageZoom(by: 0.05)
                    }
                    .keyboardShortcut("+", modifiers: [.command])

                    Button("Zoom Out") {
                        model.adjustPageZoom(by: -0.05)
                    }
                    .keyboardShortcut("-", modifiers: [.command])

                    Button("Actual Size") {
                        model.pageZoom = 1.0
                    }
                    .keyboardShortcut("0", modifiers: [.command])

                    Divider()

                    Button("Reset Layout") {
                        model.resetWorkspaceLayout()
                        AppDelegate.resetMainWindowLayout()
                    }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                }.disabled(model.packageSheetOpen || model.campaignPresented)
            }
            CommandMenu("AI") {
                Button("Connect AI provider…") { model.dialogueAssistantPresented = true }
                    .disabled(model.packageSheetOpen || model.campaignPresented)
                Button("Suggest dialogue line…") { model.dialogueAssistantPresented = true }
                    .disabled(model.packageSheetOpen || model.campaignPresented || model.selectedElement?.type != .dialogue)
                Divider()
                Button("Preview Offline AI Request…") { model.prepareOfflineDialogueRequest() }
                    .disabled(model.packageSheetOpen || model.campaignPresented || model.selectedElement?.type != .dialogue)
                Button("Export AI Activity…") { model.showGenerationActivityExportPanel() }
                    .disabled(model.packageSheetOpen || model.campaignPresented || model.document == nil)
                Button("AI Cost Ledger…") { model.showGenerationCostLedger() }
                    .disabled(model.packageSheetOpen || model.campaignPresented || model.document == nil)
                Divider()
                Button("Enter License…") { model.showLicenseImportPanel() }
                    .disabled(model.packageSheetOpen || model.campaignPresented)
            }
            CommandMenu("Screenplay") {
                Group {
                    Button("Command Palette") {
                        model.showCommandPalette()
                    }
                    .keyboardShortcut("k", modifiers: [.command])

                    Divider()

                    Button("Show Navigator") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .navigator
                        model.revealSidebar()
                    }
                    .keyboardShortcut("1", modifiers: [.command, .option])

                    Button("Show Outline") {
                        model.setWorkflowMode(.outline)
                        model.sidebarMode = .outline
                        model.revealSidebar()
                    }
                    .keyboardShortcut("u", modifiers: [.command, .option])

                    Button("Show Search") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .search
                        model.revealSidebar()
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    Button("Show Production Context") {
                        model.sidebarMode = .productionContext
                        model.revealSidebar()
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option])

                    Button("Show Breakdown") {
                        model.setWorkflowMode(.directing)
                        model.sidebarMode = .breakdown
                        model.revealSidebar()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                    Button("Show Boards") {
                        model.setWorkflowMode(.boards)
                        model.sidebarMode = .boards
                        model.revealSidebar()
                    }
                    .keyboardShortcut("g", modifiers: [.command, .option])

                    Button("Show Reports") {
                        model.sidebarMode = .reports
                        model.revealSidebar()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .option])

                    Button("Show Exports") {
                        model.setWorkflowMode(.edit)
                        model.sidebarMode = .exports
                        model.revealSidebar()
                    }
                    .keyboardShortcut("x", modifiers: [.command, .option])

                    Button("Show Edit Spine") {
                        model.setWorkflowMode(.edit)
                        model.sidebarMode = .editorial
                        model.revealSidebar()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])

                    Button("Show Activity") {
                        model.sidebarMode = .activity
                        model.revealSidebar()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .option])

                    Button("Show Snapshots") {
                        model.sidebarMode = .snapshots
                        model.revealSidebar()
                    }
                    .keyboardShortcut("v", modifiers: [.command, .option])

                    Button("Show Notes") {
                        model.sidebarMode = .notes
                        model.revealSidebar()
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                    Button("Show Format") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .assistant
                        model.revealSidebar()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .option])

                    Button("Show Title Page") {
                        model.titlePagePresented = true
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])

                    Divider()

                    Toggle("Revision Mode", isOn: Binding(
                        get: { model.revisionModeEnabled },
                        set: { model.setRevisionMode($0) }
                    ))
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    Button("Clear Revision Marks") {
                        model.clearRevisionMarks()
                    }
                    .disabled(model.revisionMarkCount == 0)

                    Button("Create Snapshot") {
                        model.createSnapshot()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .option])

                    Button("Add Script Note") {
                        model.addNoteToSelectedElement()
                    }
                    .keyboardShortcut("m", modifiers: [.command, .option])

                    Divider()

                    Toggle("Use Production Context", isOn: Binding(
                        get: { model.productionContextEnabled },
                        set: { model.setProductionContextEnabled($0) }
                    ))

                    Button("Refresh Production Context") {
                        model.refreshProductionContextFromScript()
                    }

                    Divider()

                    Group {
                        Button("Delete Selected Element") {
                            performScriptCommand { model.deleteSelectedElement() }
                        }
                        .keyboardShortcut(.delete, modifiers: [])

                        Button("Clean Blank Elements") {
                            performScriptCommand { model.deleteEmptyElements() }
                        }
                        .keyboardShortcut(.delete, modifiers: [.command])

                    }
                    .disabled(scriptCommandsDisabled)

                    Button("Clean Script") {
                        model.cleanScript()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Group {
                        Divider()

                        Button("Cycle Element Type") {
                            performScriptCommand { model.cycleSelectedElementType() }
                        }
                        .keyboardShortcut(.tab, modifiers: [])

                        Button("Cycle Element Type Backward") {
                            performScriptCommand { model.cycleSelectedElementType(forward: false) }
                        }
                        .keyboardShortcut(.tab, modifiers: [.shift])

                        Divider()

                        Button("Make Scene Heading") {
                            performScriptCommand { model.promoteSelectedElementToSceneHeading() }
                        }
                        .keyboardShortcut("1", modifiers: [.command])

                        Button("Make Action") {
                            performScriptCommand { model.setSelectedElementType(.action) }
                        }
                        .keyboardShortcut("2", modifiers: [.command])

                        Button("Make Character") {
                            performScriptCommand { model.promoteSelectedElementToCharacter() }
                        }
                        .keyboardShortcut("3", modifiers: [.command])

                        Button("Make Dialogue") {
                            performScriptCommand { model.setSelectedElementType(.dialogue) }
                        }
                        .keyboardShortcut("4", modifiers: [.command])

                        Button("Make Parenthetical") {
                            performScriptCommand { model.setSelectedElementType(.parenthetical) }
                        }
                        .keyboardShortcut("5", modifiers: [.command])

                        Button("Make Transition") {
                            performScriptCommand { model.setSelectedElementType(.transition) }
                        }
                        .keyboardShortcut("6", modifiers: [.command])

                        Button("Make Shot") {
                            performScriptCommand { model.setSelectedElementType(.shot) }
                        }
                        .keyboardShortcut("7", modifiers: [.command])
                    }
                    .disabled(scriptCommandsDisabled)
                }.disabled(model.packageSheetOpen || model.campaignPresented)
            }
        }
        MenuBarExtra {
            Button("Bring Windows to Front") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.arrangeInFront(nil)
            }
            Button("About ScreenplayOS", action: AppBranding.showAbout)
            Divider()
            Button("Quit ScreenplayOS") { appDelegate.requestQuit() }
        } label: {
            Image(nsImage: AppBranding.menuBarIcon)
                .accessibilityLabel("ScreenplayOS")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ScreenplayViewModel?
    private var terminationApproved = false
    func requestQuit() {
        guard model?.confirmSafeClose() != false else { return }
        terminationApproved = true
        // Dismiss any read-only preview only after every editor and the legacy draft approve termination.
        model?.packageEditor = nil
        model?.packagePreview = nil
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationApproved || model?.confirmSafeClose() != false ? .terminateNow : .terminateCancel
    }

    static func resetMainWindowLayout() {
        normalizeMainWindowFrame(force: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = AppBranding.appIcon
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Self.normalizeMainWindowFrame()
        }
    }

    private static func normalizeMainWindowFrame(force: Bool = false) {
        guard
            let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
            let screen = window.screen ?? NSScreen.main
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let isTooSmall = frame.width < min(900, visibleFrame.width) || frame.height < min(560, visibleFrame.height)
        let isOffscreen = frame.minX < visibleFrame.minX || frame.maxX > visibleFrame.maxX || frame.minY < visibleFrame.minY || frame.maxY > visibleFrame.maxY

        guard force || isTooSmall || isOffscreen else {
            return
        }

        let width = min(1200, visibleFrame.width - 32)
        let height = min(760, visibleFrame.height - 32)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true, animate: false)
    }
}
