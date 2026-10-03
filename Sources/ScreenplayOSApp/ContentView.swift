import AppKit
import SwiftUI
import ScreenplayDomain

private enum WorkspacePaneLayout {
    static let scriptContextMinWidth: CGFloat = 480
    static let scriptContextIdealWidth: CGFloat = 520
    static let scriptContextMaxWidth: CGFloat = 620
    static let compactWorkbenchMinWidth: CGFloat = 320
    static let compactWorkbenchIdealWidth: CGFloat = 380
    static let compactWorkbenchMaxWidth: CGFloat = 520
    static let visualWorkbenchMinWidth: CGFloat = 420
    static let visualWorkbenchIdealWidth: CGFloat = 540
    static let visualWorkbenchMaxWidth: CGFloat = 720
    static let editWorkbenchMinWidth: CGFloat = 360
}

struct ContentView: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .shell) }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceNavigationBar(model: model)
            ZStack(alignment: .top) {
                NavigationSplitView(columnVisibility: Binding(
                    get: { model.visibleWorkspaceRegions.contains(.navigation) ? .all : .detailOnly },
                    set: { visibility in
                        if !model.focusMode { model.navigationVisible = visibility != .detailOnly }
                    }
                )) {
                    Group {
                        if model.visibleWorkspaceRegions.contains(.navigation) {
                            SidebarView(model: model)
                        }
                    }
                        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
                } detail: {
                    EditorWorkspaceView(model: model)
                }

                if model.commandPaletteVisible {
                    CommandPaletteView(model: model)
                        .padding(.top, 44)
                        .transition(.opacity)
                        .zIndex(5)
                }
            }
        }
        .background { StudioSurface() }
        .preferredColorScheme(.dark)
        .tint(StudioAppearance.accent)
        .font(.system(size: 12))
        .controlSize(.small)
        .background(
            KeyCommandMonitor(
                onDelete: {
                    guard !model.packageSheetOpen else { return false }
                    return model.deleteSelectedElementIfEmpty()
                },
                onCommandDelete: {
                    guard !model.packageSheetOpen else { return false }
                    model.deleteEmptyElements()
                    return true
                },
                onElementShortcut: { type in
                    guard !model.packageSheetOpen else { return false }
                    model.setSelectedElementType(type)
                    return true
                },
                onCommandPalette: {
                    guard !model.packageSheetOpen else { return false }
                    model.showCommandPalette()
                    return true
                }
            )
        )
        .sheet(isPresented: $model.titlePagePresented) { ScreenplayTitlePageEditor(model: model) }
        .sheet(item: $model.packagePreview) { preview in
            PackagePreviewView(preview: preview) { model.packagePreview = nil }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = model.saveProblem {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Save a Copy…") { model.showSavePanel() }
                }
                .padding(12)
                .background(.regularMaterial)
            } else if !model.recoveryCopies.isEmpty {
                Text("Unsaved drafts are available in File > Recover Unsaved Draft.")
                    .font(.callout).padding(8)
                    .frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .alert("Source unavailable", isPresented: Binding(
            get: { model.sourceNavigationProblem != nil },
            set: { if !$0 { model.sourceNavigationProblem = nil } }
        )) {
            Button("OK") { model.sourceNavigationProblem = nil }
        } message: {
            Text(model.sourceNavigationProblem ?? "")
        }
        .onDeleteCommand {
            guard !model.packageSheetOpen else { return }
            model.deleteSelectedElement()
        }
        .toolbar { WorkspaceToolbar(model: model) }
    }
}

private struct WorkspaceToolbar: ToolbarContent {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .commands) }
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: AppBranding.showAbout) {
                Image(nsImage: AppBranding.logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("About ScreenplayOS")
            .help("About ScreenplayOS")
        }
        ToolbarItemGroup(placement: .principal) {
            ElementTypePicker(model: model)
        }

        ToolbarItemGroup {
            Button {
                model.showCommandPalette()
            } label: {
                Label("Command", systemImage: "command")
            }

            Button {
                model.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)

            Toggle(isOn: Binding(
                get: { model.revisionModeEnabled },
                set: { model.setRevisionMode($0) }
            )) {
                Label("Revision", systemImage: "pencil.and.outline")
            }
            .toggleStyle(StudioToggleStyle())

            Button {
                model.focusMode.toggle()
            } label: {
                Label("Focus", systemImage: "scope")
            }
            .buttonStyle(.borderless)

            Toggle(isOn: $model.contextAssistantVisible) {
                Label("Context", systemImage: "sidebar.right")
            }
            .toggleStyle(StudioToggleStyle())

            Button {
                model.save()
            } label: {
                Label(model.saveURL == nil ? "Save to Downloads" : "Save", systemImage: "square.and.arrow.down")
            }

            Button {
                model.showOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
    }
}


private struct CommandPaletteView: View {
    @ObservedObject var model: ScreenplayViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("Command", text: $model.commandPaletteQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let command = model.commandPaletteCommands.first {
                            model.performCommand(command)
                        }
                    }
                Button {
                    model.hideCommandPalette()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.commandPaletteCommands.prefix(16)) { command in
                        Button {
                            model.performCommand(command)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: command.systemImage)
                                    .frame(width: 18)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(command.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(command.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 390)
        }
        .frame(width: 520)
        .background(ScreenplayOSTokens.Palette.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: ScreenplayOSTokens.Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: ScreenplayOSTokens.Radius.panel)
                .stroke(ScreenplayOSTokens.Palette.separator, lineWidth: ScreenplayOSTokens.Spacing.hairline)
        )
        .onAppear {
            searchFocused = true
        }
        .onExitCommand {
            model.hideCommandPalette()
        }
    }
}

private struct ElementTypePicker: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .elementType) }

    var body: some View {
        if let selectedElement = model.selectedElement {
            Picker("Element Type", selection: Binding(
                get: { selectedElement.type },
                set: { model.setType($0, for: selectedElement.id) }
            )) {
                ForEach(ElementType.editorTypes, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 190)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        List {
            DisclosureGroup("Document details") {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.documentDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(model.documentLocation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                MetricRow(label: "Elements", value: "\(model.elements.count)")
                MetricRow(label: "Pages", value: "\(model.printedPages.count)")
                MetricRow(label: "Scenes", value: "\(model.sceneCount)")
                MetricRow(label: "Characters", value: "\(model.characterNames.count)")
                MetricRow(label: "Revisions", value: "\(model.revisionMarkCount)")
                MetricRow(label: "Issues", value: "\(model.formatIssues.count)")
                MetricRow(label: "Notes", value: "\(model.openScriptNotes.count)")
                MetricRow(label: "Proposals", value: "\(model.proposalsForCurrentWorkflow.count)")
                MetricRow(label: "Snapshot", value: model.lastSnapshotSummary)
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            switch model.sidebarMode {
            case .navigator:
                NavigatorSections(model: model)
            case .productionContext:
                ProductionContextSections(model: model)
            case .breakdown:
                SceneBreakdownSections(model: model)
            case .boards:
                BoardsSections(model: model)
            case .reports:
                ReportsSections(model: model)
            case .exports:
                ProductionExportSections(model: model)
            case .editorial:
                EditorialSpineSections(model: model)
            case .snapshots:
                SnapshotSections(model: model)
            case .notes:
                ScriptNoteSections(model: model)
            case .search:
                SearchSections(model: model)
            case .assistant:
                AssistantSections(model: model)
            case .titlePage:
                TitlePageSection(model: model)
            case .proposals:
                ProposalsSections(model: model)
            case .activity:
                ActivitySections(model: model)
            case .outline:
                OutlineSections(model: model)
            }
        }
        .navigationTitle(model.title)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(StudioAppearance.panel)
    }
}

private struct OutlineSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Beat Sheet") {
            BeatSheetTemplateControls(model: model)
        }

        if model.outlineBeats.isEmpty {
            Section("Beats") {
                Text("No outline yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(model.outlineBeats) { beat in
                Section {
                    OutlineBeatCard(model: model, beat: beat)
                }
            }
        }
    }
}

private struct BeatSheetTemplateControls: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var replacing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.outlineBeats.first.map { "Current structure: \($0.template)" } ?? "Choose a story structure")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Structure", selection: $model.selectedOutlineTemplate) {
                    ForEach(OutlineTemplateKind.allCases) { template in
                        Text(template.displayName).tag(template)
                    }
                }.pickerStyle(.menu)
                Button(model.outlineBeats.isEmpty ? "Create Beat Sheet" : "Replace Beat Sheet…") {
                    if model.outlineBeats.isEmpty { model.seedSelectedOutlineTemplate() }
                    else { replacing = true }
                }
            }
            Text(model.outlineCoverageSummary).font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Replace the current beat sheet?", isPresented: $replacing) {
            Button("Replace with \(model.selectedOutlineTemplate.displayName)", role: .destructive) {
                model.seedSelectedOutlineTemplate()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This replaces beat names, notes, and scene links. Screenplay scenes stay intact. You can undo the replacement.")
        }
    }
}

private struct OutlineBeatCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let beat: OutlineBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(beat.order)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(beat.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            Text(beat.purpose)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            TextField("Notes", text: model.bindingForOutlineNotes(beat), axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            HStack {
                Button {
                    model.linkSelectedScene(to: beat)
                } label: {
                    Label("Link Scene", systemImage: "link")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(model.selectedSceneBreakdown == nil)

                Spacer()
            }

            if !beat.linkedSceneSpineIDs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Linked Scenes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(beat.linkedSceneSpineIDs, id: \.self) { sceneSpineID in
                        HStack {
                            Button {
                                model.navigateToSceneSpineID(sceneSpineID)
                            } label: {
                                Text("\(sceneSpineID) \(model.sceneTitle(for: sceneSpineID))")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                model.unlinkScene(sceneSpineID, from: beat)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .onTapGesture {
            model.selectOutlineBeat(beat)
        }
    }
}

private struct ActivitySections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Activity") {
            Text("\(model.activityEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if model.activityEvents.isEmpty {
            Section("Events") {
                Text("No activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(model.activityEvents.prefix(50)) { event in
                Section {
                    ActivityEventRow(event: event)
                }
            }
        }
    }
}

private struct ActivityEventRow: View {
    let event: ActivityEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.action)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(event.actor.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(event.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct SnapshotSections: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var snapshotToRestore: ProjectSnapshot?

    var body: some View {
        Section("Snapshots") {
            TextField("Snapshot name", text: $model.snapshotName)
            Button {
                model.createSnapshot()
            } label: {
                Label("Create Snapshot", systemImage: "camera.badge.clock")
            }
            .buttonStyle(.bordered)
            .disabled(model.document == nil)

            Text("Saved beside the screenplay in ScreenplayOS Snapshots.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Section("Local Versions") {
            if model.snapshots.isEmpty {
                Text("No snapshots yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text("\(snapshot.displayDate) | \(snapshot.displaySize)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button {
                                snapshotToRestore = snapshot
                            } label: {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                model.revealSnapshotInFinder(snapshot)
                            } label: {
                                Label("Reveal", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .confirmationDialog(
            "Restore Snapshot?",
            isPresented: Binding(
                get: { snapshotToRestore != nil },
                set: { if !$0 { snapshotToRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: snapshotToRestore
        ) { snapshot in
            Button("Restore \(snapshot.name)", role: .destructive) {
                model.restoreSnapshot(snapshot)
                snapshotToRestore = nil
            }
            Button("Cancel", role: .cancel) {
                snapshotToRestore = nil
            }
        } message: { snapshot in
            Text("The current document will be saved as a Before Restore snapshot first, then replaced with \(snapshot.name).")
        }
    }
}

private struct ScriptNoteSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Add Note") {
            TextField("Note for selected script line", text: $model.draftScriptNote, axis: .vertical)
                .lineLimit(3...6)

            Button {
                model.addNoteToSelectedElement()
            } label: {
                Label("Add Note", systemImage: "note.text.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedElementID == nil || model.draftScriptNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if model.selectedElementID != nil {
                Text("\(model.selectedElementNoteCount) open on selected line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a script line first.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Current Scene") {
            if model.scriptNotesForSelectedScene.isEmpty {
                Text("No notes for this scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.scriptNotesForSelectedScene) { note in
                    ScriptNoteRow(model: model, note: note)
                }
            }
        }
    }
}

private struct ScriptNoteRow: View {
    @ObservedObject var model: ScreenplayViewModel
    let note: ScriptNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(note.status == .open ? .blue : .secondary)
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(note.body)
                .font(.caption)
                .lineLimit(4)

            HStack(spacing: 8) {
                Button {
                    model.navigateToScriptNote(note)
                } label: {
                    Label("Go", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    model.setScriptNoteStatus(note.status == .open ? .resolved : .open, for: note.id)
                } label: {
                    Label(note.status == .open ? "Resolve" : "Reopen", systemImage: note.status == .open ? "checkmark.circle" : "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ProposalsSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("\(model.workflowMode.rawValue) AI") {
            Toggle(isOn: Binding(
                get: { model.currentWorkflowAIEnabled },
                set: { model.setAIEnabled($0, for: model.workflowMode) }
            )) {
                Text(model.aiProposalSummary)
            }

            Button {
                model.generateProposalsForCurrentWorkflow()
            } label: {
                Label("Generate Proposals", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(!model.currentWorkflowAIEnabled)
        }

        if model.proposalsForCurrentWorkflow.isEmpty {
            Section("Queue") {
                Text("No proposals for this mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(model.proposalsForCurrentWorkflow) { proposal in
                Section {
                    ProposalCard(model: model, proposal: proposal)
                }
            }
        }
    }
}

private struct ProposalCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let proposal: AIProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(proposal.status.color)
                    .frame(width: 8, height: 8)
                Text(proposal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            Text(proposal.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Picker("Status", selection: Binding(
                get: { proposal.status },
                set: { model.setProposalStatus(proposal.id, status: $0) }
            )) {
                ForEach(AIProposalStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(proposal.target.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    model.applyProposal(proposal)
                } label: {
                    Label("Apply", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(proposal.status == .applied || proposal.status == .rejected)

                Button {
                    model.navigateToProposalTarget(proposal)
                } label: {
                    Label("Source", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct NavigatorSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        if !model.recentDocuments.isEmpty {
            DisclosureGroup("Recent documents") {
                ForEach(model.recentDocuments) { recent in
                    Button {
                        model.openDocument(at: recent.url)
                    } label: {
                        Text(recent.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Section("Scenes") {
            ForEach(model.scenes) { scene in
                Button {
                    model.navigateToScene(scene)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StudioAppearance.sceneColor(scene.elementID.uuidString).frame(width: 3, height: 24)
                        Text("\(scene.number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(scene.title.uppercased())
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(2)
                    }
                    if let sceneData = model.sceneBreakdowns.first(where: { $0.elementID == scene.elementID }) {
                        HStack(spacing: 6) {
                            GeometryReader { geometry in
                                Rectangle().fill(StudioAppearance.recess)
                                Rectangle().fill(StudioAppearance.sceneColor(scene.elementID.uuidString).opacity(0.65))
                                    .frame(width: geometry.size.width * CGFloat(sceneData.elementCount) / CGFloat(max(1, model.sceneBreakdowns.map(\.elementCount).max() ?? 1)))
                            }.frame(height: 3)
                            Text("\(sceneData.elementCount)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.leading, 35)
                        .help("Scene length: \(sceneData.elementCount) screenplay elements; bars are relative to the longest scene.")
                    }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .listRowBackground(model.selectedSceneBreakdown?.number == scene.number ? StudioAppearance.selection : Color.clear)
                .foregroundStyle(Color.primary)
            }
        }

        Section("Characters") {
            ForEach(model.characterNames, id: \.self) { character in
                Text(character)
                    .font(.system(size: 13, weight: .medium, design: .default))
            }
        }
    }
}

private struct ProductionContextSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Production Context") {
            Toggle(isOn: Binding(
                get: { model.productionContextEnabled },
                set: { model.setProductionContextEnabled($0) }
            )) {
                Text(model.productionContextSummary)
            }

            Button("Refresh From Script") {
                model.refreshProductionContextFromScript()
            }
            .buttonStyle(.bordered)

            if let generatedAt = model.productionContext.generatedAt {
                Text("Updated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        ForEach(ProductionEntityKind.allCases, id: \.self) { kind in
            let entities = model.productionEntities.filter { $0.kind == kind }
            if !entities.isEmpty {
                Section("\(kind.displayName) \(entities.count)") {
                    ForEach(entities.prefix(24)) { entity in
                        ProductionEntityRow(model: model, entity: entity)
                    }
                }
            }
        }

        if !model.productionNotes.isEmpty {
            Section("Notes \(model.productionNotes.count)") {
                ForEach(model.productionNotes.prefix(12)) { note in
                    Button {
                        model.selectProductionNote(note)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(note.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.selectedObject.kind == .productionNote && model.selectedObject.id == note.id ? Color.accentColor : Color.primary)
                }
            }
        }
    }
}

private struct EditorialSpineSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Edit Spine") {
            Text("\(model.editorialBeats.count) scene beats")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tracks script scenes toward edit handoff.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if model.editorialBeats.isEmpty {
            Section("Beats") {
                Text("No editorial beats yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(model.editorialBeats) { beat in
                Section {
                    Button {
                        model.selectEditorialBeat(beat)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(beat.sceneSpineID)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .leading)
                                Text(beat.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                            }

                            HStack(spacing: 8) {
                                Text(beat.status.displayName)
                                Text(beat.markerCategory.displayName)
                                Text("\(beat.shotIDs.count) shots")
                                Text("\(beat.boardFrameIDs.count) boards")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.selectedObject.kind == .editorialBeat && model.selectedObject.id == beat.id ? Color.accentColor : Color.primary)

                    Picker("Status", selection: Binding(
                        get: { beat.status },
                        set: { model.setEditorialBeatStatus($0, for: beat.id) }
                    )) {
                        ForEach(EditorialBeatStatus.editStatuses, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)

                    TextField("Edit notes", text: model.bindingForEditorialNotes(beat), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
        }
    }
}

private struct ReportsSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Reports") {
            Picker("Report", selection: $model.selectedReportKind) {
                ForEach(ReportKind.allCases) { report in
                    Text(report.displayName).tag(report)
                }
            }

            Button {
                model.showExportReportPanel()
            } label: {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }

        Section("Preview") {
            Text(model.reportPreview)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.vertical, 4)
        }
    }
}

private struct ProductionExportSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Edit Exports") {
            Picker("Export", selection: $model.selectedProductionExportKind) {
                ForEach(ProductionExportKind.allCases) { export in
                    Text(export.displayName).tag(export)
                }
            }

            Button {
                model.showProductionExportPanel()
            } label: {
                Label("Export File", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            if let selected = model.selectedSceneBreakdown {
                Text("Selected scene: \(selected.editSpineID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Preview") {
            Text(model.productionExportPreview)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.vertical, 4)
        }
    }
}

private struct BoardsSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        if let selected = model.selectedSceneBreakdown {
            Section("Boards \(selected.editSpineID)") {
                Button {
                    model.generateBoardsForSelectedScene()
                } label: {
                    Label("Generate Boards", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)

                if model.shotsForSelectedScene.isEmpty {
                    Text("Generate a shot list for this scene first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(model.boardFramesForSelectedScene.count) frames from \(model.shotsForSelectedScene.count) shots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.boardFramesForSelectedScene.isEmpty {
                Section("Frames") {
                    Text("No board frames yet for the selected scene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.boardFramesForSelectedScene) { frame in
                    Section {
                        BoardFrameCard(model: model, frame: frame)
                    }
                }
            }
        } else {
            Section("Boards") {
                Text("Select a scene first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BoardFrameCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let frame: BoardFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(frame.frameNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(frame.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            TextField("Visual prompt", text: model.bindingForBoardPrompt(frame), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .lineLimit(3...6)

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: model.bindingForBoardDuration(frame), in: 0.5...30.0, step: 0.5)
                Text(String(format: "%.1fs", frame.durationSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("Status", selection: Binding(
                get: { frame.status },
                set: { model.setBoardFrameStatus($0, for: frame.id) }
            )) {
                ForEach(ShotStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)

            TextField("Notes", text: model.bindingForBoardNotes(frame), axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Button {
                model.navigateToBoardSource(frame)
            } label: {
                Label("Source", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
        .onTapGesture {
            model.selectBoardFrame(frame)
        }
    }
}

private struct SceneBreakdownSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Scene Breakdown") {
            Button {
                model.refreshProductionContextFromScript()
            } label: {
                Label("Refresh Context", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Text("\(model.sceneBreakdowns.count) scenes ready for production review")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let selected = model.selectedSceneBreakdown {
            Section("Shot List \(selected.editSpineID)") {
                Button {
                    model.generateShotListForSelectedScene()
                } label: {
                    Label("Generate Shot List", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)

                if model.shotsForSelectedScene.isEmpty {
                    Text("No shots yet for the selected scene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.shotsForSelectedScene) { shot in
                        ShotCard(model: model, shot: shot)
                    }
                }
            }
        }

        ForEach(model.sceneBreakdowns) { breakdown in
            Section {
                Button {
                    model.navigateToSceneBreakdown(breakdown)
                } label: {
                    SceneBreakdownCard(breakdown: breakdown)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedElementID == breakdown.elementID ? Color.accentColor : Color.primary)
            }
        }
    }
}

private struct ShotCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let shot: Shot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(shot.shotNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                TextField("Shot label", text: model.bindingForShotLabel(shot), axis: .vertical)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            Picker("Setup", selection: Binding(
                get: { shot.setup },
                set: { model.setShotSetup($0, for: shot.id) }
            )) {
                ForEach(ShotSetup.allCases, id: \.self) { setup in
                    Text(setup.displayName).tag(setup)
                }
            }
            .pickerStyle(.menu)

            Picker("Status", selection: Binding(
                get: { shot.status },
                set: { model.setShotStatus($0, for: shot.id) }
            )) {
                ForEach(ShotStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)

            TextField("Notes", text: model.bindingForShotNotes(shot), axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Button {
                model.navigateToShotSource(shot)
            } label: {
                Label("Source", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
        .onTapGesture {
            model.selectShot(shot)
        }
    }
}

private struct SceneBreakdownCard: View {
    let breakdown: SceneBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(breakdown.editSpineID)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                Text(breakdown.heading.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                BreakdownMetric(label: "Page", value: breakdown.pageNumber ?? "-")
                BreakdownMetric(label: "Beats", value: "\(breakdown.actionBeatCount)")
                BreakdownMetric(label: "Rev", value: "\(breakdown.revisionCount)")
            }

            BreakdownList(label: "Cast", values: breakdown.characters)
            BreakdownList(label: "Location", values: breakdown.locations)
            BreakdownList(label: "Props", values: breakdown.props)
            BreakdownList(label: "VFX", values: breakdown.visualEffects)
            BreakdownList(label: "Notes", values: breakdown.notes)

            if !breakdown.firstAction.isEmpty {
                Text(breakdown.firstAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BreakdownMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

private struct BreakdownList: View {
    let label: String
    let values: [String]

    var body: some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(values.prefix(8).joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}

private struct ProductionEntityRow: View {
    @ObservedObject var model: ScreenplayViewModel
    let entity: ProductionEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle()
                    .fill(entity.status.color)
                    .frame(width: 8, height: 8)
                Text(entity.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(entity.sourceElementIDs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("Status", selection: Binding(
                get: { entity.status },
                set: { model.setProductionEntityStatus(entity.id, status: $0) }
            )) {
                ForEach(ProductionEntityStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
        }
        .onTapGesture {
            model.selectProductionEntity(entity)
        }
    }
}

private struct SearchSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Find / Replace") {
            TextField("Find", text: $model.findQuery)
                .textFieldStyle(.roundedBorder)

            TextField("Replace", text: $model.replaceText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Replace Selected") {
                    model.replaceSelectedMatch()
                }
                .disabled(model.findQuery.isEmpty || model.selectedElementID == nil)

                Button("Replace All") {
                    model.replaceAllMatches()
                }
                .disabled(model.findMatches.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !model.findQuery.isEmpty {
                Text("\(model.findMatches.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.findMatches.prefix(12)) { match in
                Button {
                    model.navigateToFindMatch(match)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(match.number) - \(match.elementType)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(match.preview)
                            .font(.system(size: 13))
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedElementID == match.elementID ? Color.accentColor : Color.primary)
            }
        }

        Section("Rename Character") {
            Picker("Character", selection: $model.characterToRename) {
                Text("Choose").tag("")
                ForEach(model.characterNames, id: \.self) { character in
                    Text(character).tag(character)
                }
            }

            TextField("New name", text: $model.newCharacterName)
                .textFieldStyle(.roundedBorder)

            Button("Rename") {
                model.renameCharacter()
            }
            .buttonStyle(.bordered)
            .disabled(model.characterToRename.isEmpty || model.newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct AssistantSections: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Revision Mode") {
            Toggle(isOn: Binding(
                get: { model.revisionModeEnabled },
                set: { model.setRevisionMode($0) }
            )) {
                Text(model.revisionStatusText)
            }

            TextField("Revision label", text: Binding(
                get: { model.revisionLabel },
                set: { model.setRevisionLabel($0) }
            ))
            .textFieldStyle(.roundedBorder)

            Picker("Color", selection: Binding(
                get: { model.revisionColor },
                set: { model.setRevisionColor($0) }
            )) {
                ForEach(RevisionColor.allCases, id: \.self) { color in
                    Text(color.displayName).tag(color)
                }
            }

            HStack {
                Circle()
                    .fill(model.revisionColor.swiftUIColor)
                    .frame(width: 10, height: 10)
                Text("\(model.revisionMarkCount) marked lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Clear Revision Marks") {
                model.clearRevisionMarks()
            }
            .buttonStyle(.bordered)
            .disabled(model.revisionMarkCount == 0)
        }

        Section("Format") {
            Button("Clean Script") {
                model.cleanScript()
            }
            .buttonStyle(.bordered)

            Button("Delete Blank Elements") {
                model.deleteEmptyElements()
            }
            .buttonStyle(.bordered)

            if model.formatIssues.isEmpty {
                Text("No issues found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.formatIssues.prefix(20)) { issue in
                    Button {
                        model.navigateToIssue(issue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: issue.severity == .warning ? "exclamationmark.triangle" : "wand.and.stars")
                                    .foregroundStyle(issue.severity == .warning ? .orange : .secondary)
                                Text(issue.title)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            Text(issue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TitlePageSection: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        Section("Title Page") {
            TextField("Title", text: model.titlePageBinding(.title))
                .textFieldStyle(.roundedBorder)

            TextField("Subtitle", text: model.titlePageBinding(.subtitle))
                .textFieldStyle(.roundedBorder)

            TextField("Author", text: model.titlePageBinding(.author))
                .textFieldStyle(.roundedBorder)

            TextField("Draft date", text: model.titlePageBinding(.draftDate))
                .textFieldStyle(.roundedBorder)

            TextField("Contact", text: model.titlePageBinding(.contact), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Button("Use Project Info") {
                model.syncTitlePageFromProject()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            TitlePagePreview(titlePage: model.titlePage)
        }
    }
}

private struct EditorWorkspaceView: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .workspace) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                DocumentIdentityBar(model: model)
                if model.workflowMode == .writing || model.workflowMode == .production {
                    ScreenplayPageView(model: model)
                } else {
                    GeometryReader { geometry in
                        ScrollView(.horizontal) {
                            wideWorkspace
                                .frame(width: max(geometry.size.width, minimumWorkspaceWidth), height: geometry.size.height)
                        }
                    }
                }
                BottomStatusBar(model: model)
            }
            .frame(minWidth: 340, maxWidth: .infinity)

            if model.contextAssistantVisible && model.visibleWorkspaceRegions.contains(.context) {
                ContextAssistantPanel(model: model)
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 380)
            }
        }
    }

    private var minimumWorkspaceWidth: CGFloat {
        switch model.workflowMode {
        case .edit: return 660
        case .boards: return 940
        default: return 880
        }
    }

    @ViewBuilder private var wideWorkspace: some View {
        switch model.workflowMode {
        case .outline: OutlineWorkspaceView(model: model)
        case .directing: ShotWorkspaceView(model: model)
        case .boards: BoardsWorkspaceView(model: model)
        case .edit: EditWorkspaceView(model: model)
        default: EmptyView()
        }
    }

}

private struct OutlineWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    WorkspaceHeader(
                        title: "Beat Sheet",
                        subtitle: "Story beats linked to your screenplay scenes.",
                        focus: "STORY",
                        trailing: "\(model.sceneBreakdowns.count) scenes"
                    )

                    BeatSheetTemplateControls(model: model)
                    ForEach(model.outlineBeats) { beat in
                        OutlineBeatCard(model: model, beat: beat)
                            .padding(10)
                            .background(ScreenplayOSTokens.Palette.panelBackground)
                    }
                    Divider()
                    Text("Scenes").font(.headline)
                    HStack(spacing: 8) {
                        Button {
                            model.addSceneAfterSelectedScene()
                        } label: {
                            Label("Add Scene", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            model.duplicateSelectedScene()
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.selectedSceneBreakdown == nil)

                        Button {
                            model.deleteSelectedScene()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.sceneBreakdowns.count <= 1 || model.selectedSceneBreakdown == nil)

                        Spacer()
                    }

                    if model.sceneBreakdowns.isEmpty {
                        EmptyWorkspacePrompt(
                            systemImage: "map",
                            title: "No scenes yet",
                            message: "Add a scene to begin shaping the film structure."
                        )
                    } else {
                        ForEach(model.sceneBreakdowns) { breakdown in
                            OutlineSceneCard(model: model, breakdown: breakdown)
                        }
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 560)

            ScriptPreviewPane(model: model, title: "Script Preview")
                .frame(
                    minWidth: WorkspacePaneLayout.compactWorkbenchMinWidth,
                    idealWidth: WorkspacePaneLayout.compactWorkbenchIdealWidth,
                    maxWidth: WorkspacePaneLayout.compactWorkbenchMaxWidth
                )
        }
        .background(ScreenplayOSTokens.Palette.workspaceBackground)
    }
}

private struct OutlineSceneCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let breakdown: SceneBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(breakdown.editSpineID)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(breakdown.heading.uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text("p. \(breakdown.pageNumber ?? "-")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !breakdown.firstAction.isEmpty {
                Text(breakdown.firstAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Text("\(breakdown.elementCount) lines")
                Text("\(breakdown.characters.count) chars")
                Text("\(breakdown.locations.first ?? "No location")")
                if !model.outlineBeats.filter({ $0.linkedSceneSpineIDs.contains(breakdown.editSpineID) }).isEmpty {
                    Text("Mapped")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    model.navigateToSceneBreakdown(breakdown)
                    model.moveSelectedSceneEarlier()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(breakdown.number <= 1)

                Button {
                    model.navigateToSceneBreakdown(breakdown)
                    model.moveSelectedSceneLater()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(breakdown.number >= model.sceneBreakdowns.count)

                Button {
                    model.navigateToSceneBreakdown(breakdown)
                    model.duplicateSelectedScene()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button {
                    model.navigateToSceneBreakdown(breakdown)
                    model.setWorkflowMode(.writing)
                } label: {
                    Label("Open in Script", systemImage: "arrow.right")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(10)
        .background(model.selectedSceneBreakdown?.editSpineID == breakdown.editSpineID ? StudioAppearance.selection : ScreenplayOSTokens.Palette.panelBackground)
        .overlay(alignment: .leading) { StudioAppearance.sceneColor(breakdown.elementID.uuidString).frame(width: 3).allowsHitTesting(false) }
        .overlay(
            Rectangle()
                .stroke(ScreenplayOSTokens.Palette.separator, lineWidth: ScreenplayOSTokens.Spacing.hairline)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.navigateToSceneBreakdown(breakdown)
        }
    }
}

private struct OutlineStageRow: View {
    @ObservedObject var model: ScreenplayViewModel
    let beat: OutlineBeat

    var body: some View {
        Button {
            model.selectOutlineBeat(beat)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(beat.order)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    Text(beat.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(beat.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !beat.linkedSceneSpineIDs.isEmpty {
                        Text(beat.linkedSceneSpineIDs.map { "\($0) \(model.sceneTitle(for: $0))" }.joined(separator: "  |  "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(model.selectedObject.kind == .outlineBeat && model.selectedObject.id == beat.id ? StudioAppearance.selection : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScreenplayOSTokens.Palette.separator)
                    .frame(height: ScreenplayOSTokens.Spacing.hairline)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ScriptPreviewPane: View {
    @ObservedObject var model: ScreenplayViewModel
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.setWorkflowMode(.writing)
                } label: {
                    Label("Open in Script", systemImage: "arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.selectedSceneScriptElements) { element in
                        Text(element.text.isEmpty ? element.type.displayName : model.displayedText(for: element))
                            .font(Font(PackageTypography.font(model.writingTypography)))
                            .foregroundStyle(Color(nsColor: StudioAppearance.ink(model.darkPageMode)).opacity(element.text.isEmpty ? 0.5 : 1))
                            .frame(maxWidth: .infinity, alignment: element.type == .character || element.type == .dialogue ? .center : .leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: StudioAppearance.paper(model.darkPageMode)))
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(width: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct ShotWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        HSplitView {
            ScriptPreviewPane(model: model, title: "Scene Script")
                .frame(
                    minWidth: WorkspacePaneLayout.scriptContextMinWidth,
                    idealWidth: WorkspacePaneLayout.scriptContextIdealWidth,
                    maxWidth: WorkspacePaneLayout.scriptContextMaxWidth
                )

            ShotListPane(model: model)
                .frame(
                    minWidth: WorkspacePaneLayout.compactWorkbenchMinWidth,
                    idealWidth: WorkspacePaneLayout.compactWorkbenchIdealWidth,
                    maxWidth: WorkspacePaneLayout.compactWorkbenchMaxWidth
                )
        }
        .background(ScreenplayOSTokens.Palette.workspaceBackground)
    }
}

private struct ShotListPane: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    WorkspaceHeader(
                        title: "Shot",
                        subtitle: "Coverage and camera intent for the visible scene.",
                        focus: "COVERAGE",
                        trailing: model.selectedSceneBreakdown?.editSpineID ?? "No scene"
                    )

                    if let selected = model.selectedSceneBreakdown {
                        Button {
                            model.generateShotListForSelectedScene()
                        } label: {
                            Label(model.shotsForSelectedScene.isEmpty ? "Generate Shot List" : "Regenerate Shot List", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.bordered)

                        ForEach(model.shotsForSelectedScene) { shot in
                            ShotStageRow(model: model, shot: shot)
                        }

                        if model.shotsForSelectedScene.isEmpty {
                            EmptyWorkspacePrompt(
                                systemImage: "camera.viewfinder",
                                title: "No shots for \(selected.editSpineID)",
                                message: "Create starter coverage from this scene, then refine the shot intent."
                            )
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            ShotComposerPane(model: model)
                .frame(minHeight: 260, idealHeight: 300, maxHeight: 380)
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(width: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct ShotStageRow: View {
    @ObservedObject var model: ScreenplayViewModel
    let shot: Shot

    var body: some View {
        Button {
            model.selectShot(shot)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(shot.shotNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                VStack(alignment: .leading, spacing: 5) {
                    Text(shot.label)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(shot.setup.displayName) | \(shot.status.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(shot.sceneSpineID)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(model.selectedObject.kind == .shot && model.selectedObject.id == shot.id ? StudioAppearance.selection : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScreenplayOSTokens.Palette.separator)
                    .frame(height: ScreenplayOSTokens.Spacing.hairline)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ShotComposerPane: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Shot Composer", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.setWorkflowMode(.boards)
                } label: {
                    Label("Boards", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            if let shot = model.selectedShot {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Shot label", text: model.bindingForShotLabel(shot), axis: .vertical)
                        .font(.system(size: 14, weight: .semibold))
                    Picker("Setup", selection: Binding(
                        get: { model.selectedShot?.setup ?? shot.setup },
                        set: { model.setShotSetup($0, for: shot.id) }
                    )) {
                        ForEach(ShotSetup.allCases, id: \.self) { setup in
                            Text(setup.displayName).tag(setup)
                        }
                    }
                    Picker("Status", selection: Binding(
                        get: { model.selectedShot?.status ?? shot.status },
                        set: { model.setShotStatus($0, for: shot.id) }
                    )) {
                        ForEach(ShotStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("Notes", text: model.bindingForShotNotes(shot), axis: .vertical)
                        .lineLimit(4...8)
                    Button {
                        model.navigateToShotSource(shot)
                    } label: {
                        Label("Source in Script", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(14)
            } else {
                EmptyWorkspacePrompt(systemImage: "camera", title: "No shot selected", message: "Select or generate a shot to compose it.")
                    .padding(14)
            }
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(width: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct BoardsWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        HSplitView {
            ScriptPreviewPane(model: model, title: "Scene Script")
                .frame(
                    minWidth: WorkspacePaneLayout.scriptContextMinWidth,
                    idealWidth: WorkspacePaneLayout.scriptContextIdealWidth,
                    maxWidth: WorkspacePaneLayout.scriptContextMaxWidth
                )

            BoardWorkbenchPane(model: model)
                .frame(
                    minWidth: WorkspacePaneLayout.visualWorkbenchMinWidth,
                    idealWidth: WorkspacePaneLayout.visualWorkbenchIdealWidth,
                    maxWidth: WorkspacePaneLayout.visualWorkbenchMaxWidth
                )
        }
        .background(ScreenplayOSTokens.Palette.workspaceBackground)
    }
}

private struct BoardWorkbenchPane: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                WorkspaceHeader(
                    title: "Boards",
                    subtitle: "Visual sequence for the visible scene.",
                    focus: "IMAGES",
                    trailing: "\(model.boardFramesForSelectedScene.count) boards | \(model.boardomaticDurationText)"
                )
                .padding(16)

                BoardomaticBar(model: model)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        if model.boardFramesForSelectedScene.isEmpty {
                            EmptyWorkspacePrompt(
                                systemImage: "rectangle.on.rectangle",
                                title: "No boards for this scene",
                                message: model.shotsForSelectedScene.isEmpty ? "Generate shots first, then create boards." : "Generate boards from the selected scene's shots."
                            )
                            .frame(width: 360, height: 260)
                        } else {
                            ForEach(model.boardFramesForSelectedScene) { frame in
                                BoardStageCard(model: model, frame: frame)
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            BoardDetailsPane(model: model)
                .frame(minHeight: 300, idealHeight: 340, maxHeight: 420)
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(width: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct BoardomaticBar: View {
    @ObservedObject var model: ScreenplayViewModel
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleBoardomaticPlayback()
            } label: {
                Label(model.boardomaticIsPlaying ? "Pause" : "Play", systemImage: model.boardomaticIsPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.boardFramesForSelectedScene.isEmpty)

            Button {
                model.selectPreviousBoardFrame()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(model.boardFramesForSelectedScene.isEmpty)

            Button {
                model.selectNextBoardFrame()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(model.boardFramesForSelectedScene.isEmpty)

            Slider(value: Binding(
                get: { model.boardomaticProgress },
                set: { model.scrubBoardomaticProgress(to: $0) }
            ), in: 0...1)
            .disabled(model.boardFramesForSelectedScene.isEmpty)

            Text(model.boardomaticPlayheadText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(StudioAppearance.panel)
        .onReceive(timer) { _ in
            model.advanceBoardomaticTick()
        }
    }
}

private struct BoardStageCard: View {
    @ObservedObject var model: ScreenplayViewModel
    let frame: BoardFrame

    var body: some View {
        Button {
            model.selectBoardFrame(frame)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(frame.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                HStack {
                    Text("\(frame.frameNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fs", frame.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(frame.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(frame.prompt.isEmpty ? "No visual prompt yet." : frame.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(width: 280)
            .padding(10)
            .background(model.activeBoardFrame?.id == frame.id ? StudioAppearance.selection : ScreenplayOSTokens.Palette.panelBackground)
            .overlay(
                Rectangle()
                    .stroke(model.activeBoardFrame?.id == frame.id ? Color.accentColor : ScreenplayOSTokens.Palette.separator, lineWidth: ScreenplayOSTokens.Spacing.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BoardDetailsPane: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Board Details", systemImage: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.setWorkflowMode(.edit)
                } label: {
                    Label("Edit", systemImage: "timeline.selection")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            if let frame = model.selectedBoardFrame {
                VStack(alignment: .leading, spacing: 12) {
                    Text(frame.label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    TextField("Visual prompt", text: model.bindingForBoardPrompt(frame), axis: .vertical)
                        .lineLimit(4...8)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: model.bindingForBoardDuration(frame), in: 0.5...30.0, step: 0.5)
                        Text(String(format: "%.1f seconds", model.selectedBoardFrame?.durationSeconds ?? frame.durationSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Picker("Status", selection: Binding(
                        get: { model.selectedBoardFrame?.status ?? frame.status },
                        set: { model.setBoardFrameStatus($0, for: frame.id) }
                    )) {
                        ForEach(ShotStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("Notes", text: model.bindingForBoardNotes(frame), axis: .vertical)
                        .lineLimit(3...7)
                    Button {
                        model.navigateToBoardSource(frame)
                    } label: {
                        Label("Source in Script", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(14)
            } else {
                EmptyWorkspacePrompt(systemImage: "photo", title: "No board selected", message: "Select a board to adjust its prompt, timing, and notes.")
                    .padding(14)
            }
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
    }
}

private struct EditWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VSplitView {
            HSplitView {
                ScriptPreviewPane(model: model, title: "Scene Script")
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 440)
                EditWorkbenchPane(model: model)
                    .frame(minWidth: WorkspacePaneLayout.editWorkbenchMinWidth)
            }
            .frame(minHeight: 240)

            LinearEditSpineView(model: model)
                .frame(minHeight: 260, idealHeight: 300, maxHeight: 420)
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
    }
}

private struct EditWorkbenchPane: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Edit", subtitle: "Selected scene", focus: "TIME",
                            trailing: model.editTimelineDurationText)
                .padding(12)
            EditPlaybackBar(model: model)
            ZStack {
                Rectangle().fill(Color.black.opacity(0.82))
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(model.activeBoardFrame?.label ?? model.selectedSceneBreakdown?.heading ?? "Select a scene below")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    if let frame = model.activeBoardFrame {
                        Text(String(format: "%.1fs", frame.durationSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
    }
}

private struct WorkspaceHeader: View {
    let title: String
    let subtitle: String
    var focus: String? = nil
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    if let focus {
                        Text(focus)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyWorkspacePrompt: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(16)
    }
}

private struct ContextAssistantPanel: View {
    @ObservedObject var model: ScreenplayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Context Inspector", systemImage: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.contextAssistantVisible = false
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InspectorHeader(model: model, context: model.inspectorContext)

                    Toggle(isOn: Binding(
                        get: { model.productionContextEnabled },
                        set: { model.setProductionContextEnabled($0) }
                    )) {
                        Text(model.productionContextSummary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(model.contextAssistantStarterPrompts, id: \.self) { prompt in
                            Button {
                                model.runContextAssistantPrompt(prompt)
                            } label: {
                                Text(prompt)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Context request", text: $model.contextAssistantPrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)

                        Button {
                            model.runContextAssistantPrompt()
                        } label: {
                            Label("Run", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.contextAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !model.contextAssistantJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Jobs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear") {
                                    model.clearContextAssistantJobs()
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }

                            ForEach(model.contextAssistantJobs.prefix(8)) { job in
                                ContextAssistantJobRow(job: job)
                            }
                        }
                    }

                    if !model.productionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(model.productionNotes.prefix(6)) { note in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(note.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(ScreenplayOSTokens.Palette.appBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(width: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct InspectorHeader: View {
    @ObservedObject var model: ScreenplayViewModel
    let context: InspectorContext

    var body: some View {
        VStack(alignment: .leading, spacing: ScreenplayOSTokens.Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.selection.kind.rawValue)
                    .font(.caption2)
                    .foregroundStyle(ScreenplayOSTokens.Palette.secondaryText)
                Spacer()
                if let sceneSpineID = context.selection.sceneSpineID {
                    Text(sceneSpineID)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ScreenplayOSTokens.Palette.secondaryText)
                }
            }

            Text(context.title)
                .font(ScreenplayOSTokens.Typography.panelTitle)
                .lineLimit(2)

            Text(context.subtitle)
                .font(ScreenplayOSTokens.Typography.inspector)
                .foregroundStyle(ScreenplayOSTokens.Palette.secondaryText)
                .lineLimit(2)

            if !context.details.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(context.details) { detail in
                        InspectorDetailRow(detail: detail)
                    }
                }
            }

            if !context.actions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(context.actions) { action in
                        Button {
                            model.performInspectorAction(action)
                        } label: {
                            Label(action.compactTitle, systemImage: action.systemImage)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(ScreenplayOSTokens.Spacing.panelInset)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScreenplayOSTokens.Palette.separator)
                .frame(height: ScreenplayOSTokens.Spacing.hairline)
        }
    }
}

private struct InspectorDetailRow: View {
    let detail: InspectorDetail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.label)
                .font(.caption2)
                .foregroundStyle(ScreenplayOSTokens.Palette.secondaryText)
                .frame(width: 74, alignment: .leading)
            Text(detail.value)
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

private struct ContextAssistantJobRow: View {
    let job: ContextAssistantJob

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(job.prompt)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(job.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(job.status == .complete ? .green : .secondary)
            }
            Text(job.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
    }
}

private struct DocumentIdentityBar: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .identity) }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(StudioAppearance.accent)
            Text(model.documentDisplayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .help(model.documentLocation)
            Spacer(minLength: 8)
            Label(model.saveProblem != nil ? "Save failed" : (model.saveURL == nil ? "Not saved" : (model.hasUnsavedChanges ? "Unsaved changes" : "Saved locally")),
                  systemImage: model.saveProblem != nil ? "exclamationmark.triangle" : (model.hasUnsavedChanges ? "circle.fill" : "checkmark"))
                .font(.system(size: 11)).foregroundStyle(model.saveProblem != nil ? Color.orange : Color(white: 0.76))
        }
        .padding(.horizontal, 12).padding(.vertical, 6).studioStrip()
    }
}

private struct BottomStatusBar: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .status) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                StatusCapsule(systemImage: "list.number", text: model.selectedElementPosition)
                PrintedPageMenu(model: model)
                    .fixedSize()
                .help("Go to the source text on a printed page. Page numbers exclude the title page.")
                StatusCapsule(systemImage: "pencil.and.outline", text: model.revisionStatusText)
                if model.workflowMode != .writing {
                    StatusCapsule(systemImage: "rectangle.stack", text: model.productionContextSummary)
                }
                StatusCapsule(systemImage: "doc.text.magnifyingglass", text: model.currentSceneTitle)
                    .frame(maxWidth: 280, alignment: .leading)

                Spacer(minLength: 12)

                Toggle(isOn: $model.focusMode) {
                    Label("Focus", systemImage: "scope")
                }
                .toggleStyle(StudioToggleStyle())
                .controlSize(.small)

                Toggle(isOn: $model.darkPageMode) {
                    Label("Dark Page", systemImage: model.darkPageMode ? "moon.fill" : "moon")
                }
                .toggleStyle(StudioToggleStyle())
                .controlSize(.small)


            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
        .studioStrip()
    }
}

private struct StatusCapsule: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)

            .clipShape(RoundedRectangle(cornerRadius: ScreenplayOSTokens.Radius.control))
    }
}

private struct TitlePagePreview: View {
    let titlePage: TitlePage

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 8)
            Text(titlePage.title.isEmpty ? "Untitled" : titlePage.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if !titlePage.subtitle.isEmpty {
                Text(titlePage.subtitle)
                    .font(.system(size: 12, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !titlePage.author.isEmpty {
                Text("by \(titlePage.author)")
                    .font(.system(size: 12, design: .serif))
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 12)

            if !titlePage.draftDate.isEmpty || !titlePage.contact.isEmpty {
                VStack(spacing: 3) {
                    if !titlePage.draftDate.isEmpty {
                        Text(titlePage.draftDate)
                    }
                    if !titlePage.contact.isEmpty {
                        Text(titlePage.contact)
                    }
                }
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: ScreenplayOSTokens.Radius.panel))
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScreenplayPageView: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .page) }
    @State private var preview: PrintPreviewSnapshot?
    @State private var showsPages = true
    @State private var showsPageBox = false

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { formattingControls.fixedSize(); Spacer(minLength: 0); documentControls.fixedSize() }
                VStack(alignment: .leading, spacing: 6) { formattingControls; documentControls }
            }
            .buttonStyle(StudioButtonStyle())
            .padding(.horizontal, 12).padding(.vertical, 6).studioStrip()
            if let notice = PackageTypography.substitution(model.writingTypography) {
                Text(notice).font(.caption).padding(.horizontal, 8)
            }
            if !model.writingPageLayoutAvailable {
                Text("Continuous view: this layout cannot yet show exact editable pages. Use Print Preview for page placement.")
                    .font(.caption).padding(.horizontal, 8)
            }
            HStack(spacing: 8) {
                Toggle(isOn: $showsPages) { Label("Pages", systemImage: "sidebar.left") }
                    .toggleStyle(.button)
                    .help("Show or hide the scrollable script page navigator")
                Button("Go to page…") { showsPageBox.toggle() }
                    .popover(isPresented: $showsPageBox) {
                        ScriptPageNavigator(model: model) { showsPageBox = false }
                            .frame(width: 220, height: 360)
                    }
                Spacer(minLength: 0)
                Text("\(model.printedPages.count) pages").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(StudioButtonStyle())
            .padding(.horizontal, 12).padding(.vertical, 5).studioStrip()
            HStack(spacing: 0) {
                if showsPages && !model.focusMode {
                    ScriptPageNavigator(model: model)
                        .frame(width: 160)
                    Divider()
                }
                ScriptPageWell(width: 760 * model.pageZoom) {
                    ContinuousScreenplayEditor(model: model)
                }
            }
            if let element = model.selectedElement {
                HStack {
                    ElementFormatStrip(selectedType: element.type, leading: 0) { model.setType($0, for: element.id) }
                    if let mark = element.revisionMark {
                        Text(mark.label).foregroundStyle(mark.color.swiftUIColor)
                    }
                    Button("Notes (\(model.openNoteCount(for: element.id)))") { model.showNotesForElement(element.id) }
                }.buttonStyle(StudioButtonStyle()).padding(.horizontal, 12).padding(.vertical, 5).studioStrip()
                let suggestions = model.characterSuggestions(for: element)
                if !suggestions.isEmpty {
                    CharacterSuggestionStrip(suggestions: suggestions, leading: 0) { model.applyCharacterSuggestion($0, to: element.id) }
                }
            }
            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .sheet(item: $preview) { snapshot in
            PrintPreviewSheet(snapshot: snapshot) { model.showExportPDFPanel(data: snapshot.data) }
        }
    }
    private var formattingControls: some View {
            WritingFormattingBar(settings: model.writingTypography,
                changeFont: { model.changeWritingTypography(font: $0) }, changeSize: { model.changeWritingTypography(size: $0) },
                active: model.writingEmphasisActive, toggle: model.toggleWritingEmphasis,
                clear: { model.formatWritingSelection(.init(bold: false, italic: false, underline: false, strikethrough: false)) })
                .disabled(model.document == nil)
    }
    private var documentControls: some View {
            HStack(spacing: 6) {
                if model.pagesAreLocked {
                    Label("Pages Locked", systemImage: "lock.fill").font(.caption)
                    Button("Unlock Pages") { model.unlockProductionPages() }
                        .help("Return to flowing page numbers. This can be undone.")
                } else {
                    Button("Lock Pages") { model.lockProductionPages() }
                        .disabled(model.document == nil)
                        .help("Preserve current page numbers; additions use lettered pages and deletions retain omitted pages.")
                }

                Button("Title Page") { model.titlePagePresented = true }
                Button {
                    do { preview = try PrintPreviewSnapshot(data: model.makePrintPDF(), pageLabels: model.printedPages.map(\.label)) }
                    catch { model.errorMessage = error.localizedDescription }
                } label: {
                    Label("Print Preview", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(model.document == nil)
            }
    }

}

private struct ElementFormatStrip: View {
    let selectedType: ElementType
    let leading: CGFloat
    let onSetType: (ElementType) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(ElementType.editorTypes, id: \.self) { type in
                    Button {
                        onSetType(type)
                    } label: {
                        if type == selectedType {
                            Label(type.displayName, systemImage: "checkmark")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                Label(selectedType.displayName, systemImage: "textformat")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .controlSize(.small)

            Text("Return adds \(nextTypeName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, leading)
        .padding(.bottom, 5)
    }

    private var nextTypeName: String {
        switch selectedType {
        case .sceneHeading:
            return ElementType.action.displayName
        case .character, .parenthetical:
            return ElementType.dialogue.displayName
        case .dialogue, .action, .shot, .general, .pageBreak:
            return ElementType.action.displayName
        case .transition:
            return ElementType.sceneHeading.displayName
        }
    }
}

private struct CharacterSuggestionStrip: View {
    let suggestions: [String]
    let leading: CGFloat
    let onSuggestion: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSuggestion(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, leading)
        .padding(.bottom, 5)
    }
}

private struct KeyCommandMonitor: NSViewRepresentable {
    let onDelete: () -> Bool
    let onCommandDelete: () -> Bool
    let onElementShortcut: (ElementType) -> Bool
    let onCommandPalette: () -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelete = onDelete
        context.coordinator.onCommandDelete = onCommandDelete
        context.coordinator.onElementShortcut = onElementShortcut
        context.coordinator.onCommandPalette = onCommandPalette
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDelete: onDelete,
            onCommandDelete: onCommandDelete,
            onElementShortcut: onElementShortcut,
            onCommandPalette: onCommandPalette
        )
    }

    final class Coordinator {
        var onDelete: () -> Bool
        var onCommandDelete: () -> Bool
        var onElementShortcut: (ElementType) -> Bool
        var onCommandPalette: () -> Bool
        private var monitor: Any?

        init(
            onDelete: @escaping () -> Bool,
            onCommandDelete: @escaping () -> Bool,
            onElementShortcut: @escaping (ElementType) -> Bool,
            onCommandPalette: @escaping () -> Bool
        ) {
            self.onDelete = onDelete
            self.onCommandDelete = onCommandDelete
            self.onElementShortcut = onElementShortcut
            self.onCommandPalette = onCommandPalette
        }

        func install() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }

                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   let elementType = Self.elementType(forShortcutKeyCode: event.keyCode) {
                    return self.onElementShortcut(elementType) ? nil : event
                }

                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.keyCode == 40 {
                    return self.onCommandPalette() ? nil : event
                }

                let isDelete = event.keyCode == 51 || event.keyCode == 117
                guard isDelete else {
                    return event
                }

                if event.modifierFlags.contains(.command) {
                    return self.onCommandDelete() ? nil : event
                }

                return self.onDelete() ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            uninstall()
        }

        private static func elementType(forShortcutKeyCode keyCode: UInt16) -> ElementType? {
            switch keyCode {
            case 18:
                return .sceneHeading
            case 19:
                return .action
            case 20:
                return .character
            case 21:
                return .dialogue
            case 23:
                return .parenthetical
            case 22:
                return .transition
            case 26:
                return .shot
            default:
                return nil
            }
        }
    }
}

private extension ElementType {
    var placeholder: String {
        switch self {
        case .sceneHeading:
            return "INT./EXT. LOCATION - TIME"
        case .action:
            return "Action"
        case .character:
            return "CHARACTER"
        case .dialogue:
            return "Dialogue"
        case .parenthetical:
            return "(parenthetical)"
        case .transition:
            return "CUT TO:"
        case .general:
            return "Text"
        case .shot:
            return "Shot"
        case .pageBreak:
            return "Page Break"
        }
    }
}
