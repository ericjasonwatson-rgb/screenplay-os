import AppKit
import SwiftUI

@main
struct ScreenplayOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ScreenplayViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
                .background(DocumentCloseGuard(model: model))
                .frame(minWidth: 900, idealWidth: 1200, minHeight: 560, idealHeight: 760)
        }
        .defaultSize(width: 1200, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Group {
                    Button("About ScreenplayOS", action: AppBranding.showAbout)
                }.disabled(model.packagePreview != nil)
            }
            CommandGroup(replacing: .newItem) {
                Group {
                    Button("New Screenplay") {
                        model.newDocument()
                    }
                    .keyboardShortcut("n", modifiers: [.command])

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
                }.disabled(model.packagePreview != nil)
            }
            CommandGroup(replacing: .saveItem) {
                Group {
                    Button("Save") {
                        model.save()
                    }
                    .keyboardShortcut("s", modifiers: [.command])

                    Button("Save As...") {
                        model.showSavePanel()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button("Export PDF...") {
                        model.showExportPDFPanel()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button("Export Report...") {
                        model.showExportReportPanel()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .option])

                    Button("Export Edit File...") {
                        model.showProductionExportPanel()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                }.disabled(model.packagePreview != nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Group {
                    Button("Undo") {
                        model.undo()
                    }
                    .keyboardShortcut("z", modifiers: [.command])
                    .disabled(!model.canUndo)
                    Button("Redo") { model.redo() }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!model.canRedo)
                }.disabled(model.packagePreview != nil)
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
                        model.pageZoom = min(1.35, model.pageZoom + 0.05)
                    }
                    .keyboardShortcut("+", modifiers: [.command])

                    Button("Zoom Out") {
                        model.pageZoom = max(0.8, model.pageZoom - 0.05)
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
                }.disabled(model.packagePreview != nil)
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
                    }
                    .keyboardShortcut("1", modifiers: [.command, .option])

                    Button("Show Outline") {
                        model.setWorkflowMode(.outline)
                        model.sidebarMode = .outline
                    }
                    .keyboardShortcut("u", modifiers: [.command, .option])

                    Button("Show Search") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .search
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    Button("Show Production Context") {
                        model.sidebarMode = .productionContext
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option])

                    Button("Show Breakdown") {
                        model.setWorkflowMode(.directing)
                        model.sidebarMode = .breakdown
                    }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                    Button("Show Boards") {
                        model.setWorkflowMode(.boards)
                        model.sidebarMode = .boards
                    }
                    .keyboardShortcut("g", modifiers: [.command, .option])

                    Button("Show Reports") {
                        model.sidebarMode = .reports
                    }
                    .keyboardShortcut("r", modifiers: [.command, .option])

                    Button("Show Exports") {
                        model.setWorkflowMode(.edit)
                        model.sidebarMode = .exports
                    }
                    .keyboardShortcut("x", modifiers: [.command, .option])

                    Button("Show Edit Spine") {
                        model.setWorkflowMode(.edit)
                        model.sidebarMode = .editorial
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])

                    Button("Show Activity") {
                        model.sidebarMode = .activity
                    }
                    .keyboardShortcut("l", modifiers: [.command, .option])

                    Button("Show Snapshots") {
                        model.sidebarMode = .snapshots
                    }
                    .keyboardShortcut("v", modifiers: [.command, .option])

                    Button("Show Notes") {
                        model.sidebarMode = .notes
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                    Button("Show Format") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .assistant
                    }
                    .keyboardShortcut("k", modifiers: [.command, .option])

                    Button("Show Title Page") {
                        model.setWorkflowMode(.writing)
                        model.sidebarMode = .titlePage
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

                    Button("Delete Selected Element") {
                        model.deleteSelectedElement()
                    }
                    .keyboardShortcut(.delete, modifiers: [])

                    Button("Clean Blank Elements") {
                        model.deleteEmptyElements()
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])

                    Button("Clean Script") {
                        model.cleanScript()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Divider()

                    Button("Cycle Element Type") {
                        model.cycleSelectedElementType()
                    }
                    .keyboardShortcut(.tab, modifiers: [])

                    Button("Cycle Element Type Backward") {
                        model.cycleSelectedElementType(forward: false)
                    }
                    .keyboardShortcut(.tab, modifiers: [.shift])

                    Divider()

                    Button("Make Scene Heading") {
                        model.promoteSelectedElementToSceneHeading()
                    }
                    .keyboardShortcut("1", modifiers: [.command])

                    Button("Make Action") {
                        model.setSelectedElementType(.action)
                    }
                    .keyboardShortcut("2", modifiers: [.command])

                    Button("Make Character") {
                        model.promoteSelectedElementToCharacter()
                    }
                    .keyboardShortcut("3", modifiers: [.command])

                    Button("Make Dialogue") {
                        model.setSelectedElementType(.dialogue)
                    }
                    .keyboardShortcut("4", modifiers: [.command])

                    Button("Make Parenthetical") {
                        model.setSelectedElementType(.parenthetical)
                    }
                    .keyboardShortcut("5", modifiers: [.command])

                    Button("Make Transition") {
                        model.setSelectedElementType(.transition)
                    }
                    .keyboardShortcut("6", modifiers: [.command])

                    Button("Make Shot") {
                        model.setSelectedElementType(.shot)
                    }
                    .keyboardShortcut("7", modifiers: [.command])
                }.disabled(model.packagePreview != nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ScreenplayViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.confirmSafeClose() == false ? .terminateCancel : .terminateNow
    }

    static func resetMainWindowLayout() {
        normalizeMainWindowFrame(force: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
