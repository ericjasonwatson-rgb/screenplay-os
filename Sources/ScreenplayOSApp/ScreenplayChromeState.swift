import Combine
import SwiftUI
import ScreenplayDomain

/// Region-specific writing presentation signals. The native editor and live content
/// panels observe the canonical model; stable navigator rows use display snapshots.
@MainActor
final class ScreenplayChromeState: ObservableObject {
    struct Writing: Equatable {
        let documentID: UUID?
        let typography: DocumentTypography
        let labels: [String]
        let enabledPages: [Bool]
        let values: [String?]
        let emphasis: [Bool]
    }
    enum Snapshot: Equatable {
        case navigator([SceneSummary], [Int], [String], [RecentDocument], Int?)
        case full(UUID), writing(Writing), fields([String?]), pages([String], [Bool])
    }
    enum Region: Hashable { case all, shell, workspace, commands, navigation, identity, status, page, pages, pageMenu, elementType, sidebar, navigator }
    @MainActor final class Signal: ObservableObject {
        @Published private(set) var value: Snapshot
        init(_ value: Snapshot) { self.value = value }
        func update(_ next: Snapshot) { if value != next { value = next } }
    }
    private var signals: [Region: Signal] = [:]
    func signal(for region: Region, model: ScreenplayViewModel) -> Signal {
        if let signal = signals[region] { return signal }
        let signal = Signal(Self.capture(model, region: region))
        signals[region] = signal
        return signal
    }
    @Published private(set) var snapshot: Snapshot
    private var subscription: AnyCancellable?
    private var pending = false

    init(model: ScreenplayViewModel) {
        snapshot = Self.capture(model)
        subscription = model.objectWillChange.sink { [weak self, weak model] in
            guard let self, !self.pending else { return }
            self.pending = true
            // Published sends before mutation. Coalesce a synchronous edit/save and
            // read its final state, rather than capturing stale or half-updated values.
            DispatchQueue.main.async { [weak self, weak model] in
                guard let self, let model, self.pending else { return }
                self.pending = false
                self.refresh(from: model)
            }
        }
    }

    /// Native edits can publish their completed state before SwiftUI's layout pass.
    /// The queued fallback still covers all non-editor commands and changes.
    func refresh(from model: ScreenplayViewModel) {
        // A completed native edit supersedes its queued notification. Later model
        // changes can schedule another refresh without duplicating this one.
        pending = false
        let next = Self.capture(model)
        if snapshot != next { snapshot = next }
        for (region, signal) in signals { signal.update(Self.capture(model, region: region)) }
    }

    /// Each region observes only what it displays. Navigator rows and sidebar
    /// metrics refresh when their displayed values change; live content panels keep
    /// canonical observation. Other modes and modal workflows stay conservative.
    private static func capture(_ model: ScreenplayViewModel, region: Region) -> Snapshot {
        if region == .all { return capture(model) }
        // Retain the collapsed sidebar's view identity without refreshing invisible
        // rows. Reopening captures the current canonical state in the same update.
        if (region == .sidebar || region == .navigator),
           !model.visibleWorkspaceRegions.contains(.navigation) { return .fields([]) }
        guard model.workflowMode == .writing, !model.titlePagePresented,
              !model.commandPaletteVisible, !model.packageSheetOpen else { return .full(UUID()) }
        let selected = model.selectedElement
        switch region {
        case .sidebar:
            return .fields([model.title, model.sidebarMode.rawValue, model.documentDisplayName,
                model.documentLocation, String(model.elements.count), String(model.printedPages.count),
                String(model.sceneCount), String(model.characterNames.count), String(model.revisionMarkCount),
                String(model.formatIssues.count), String(model.openScriptNotes.count),
                String(model.proposalsForCurrentWorkflow.count), model.lastSnapshotSummary, model.subtitle])
        case .navigator:
            return .navigator(model.scenes, model.sceneBreakdowns.map(\.elementCount),
                model.characterNames, model.recentDocuments, model.selectedSceneBreakdown?.number)
        case .all: return capture(model)
        case .shell:
            return .fields([String(model.navigationVisible), String(model.focusMode), model.saveProblem,
                String(!model.recoveryCopies.isEmpty), model.sourceNavigationProblem,
                String(model.dialogueAssistantPresented), model.boardGenerationSnapshot?.id.uuidString,
                String(model.portableExportInProgress), model.portableExportStatus])
        case .workspace:
            return .fields([String(model.contextAssistantVisible), String(model.focusMode)])
        case .commands:
            return .fields([String(model.canUndo), String(model.revisionModeEnabled),
                String(model.contextAssistantVisible), String(model.saveURL != nil)])
        case .navigation:
            return .fields([model.sidebarMode.rawValue, String(model.navigationVisible),
                String(model.focusMode), String(model.pageZoom)])
        case .identity:
            return .fields([model.documentDisplayName, model.documentLocation, model.saveProblem,
                String(model.saveURL != nil), String(model.hasUnsavedChanges)])
        case .status:
            return .fields([model.selectedElementPosition, model.revisionStatusText, model.currentSceneTitle,
                String(model.focusMode), String(model.darkPageMode)])
        case .pageMenu:
            return .fields([model.currentPrintedPageStatus])
        case .elementType:
            return .fields([selected?.id.uuidString, selected?.type.rawValue])
        case .pages:
            let projection = model.printedLayout
            return .pages(projection.pages.map(\.label),
                projection.pages.indices.map { projection.firstSourceCaret(onPage: $0) != nil })
        case .page:
            let values: [String?] = [String(model.printedPages.count), String(model.focusMode),
                String(model.pageZoom), String(model.pagesAreLocked), String(model.writingPageLayoutAvailable),
                model.errorMessage, selected?.id.uuidString, selected?.type.rawValue,
                selected?.revisionMark?.label, String(describing: selected?.revisionMark?.color),
                String(selected.map { model.openNoteCount(for: $0.id) } ?? 0)]
                + (selected.map { model.characterSuggestions(for: $0) } ?? [])
            return .writing(Writing(documentID: model.document?.screenplay.id, typography: model.writingTypography,
                labels: [], enabledPages: [], values: values,
                emphasis: [model.writingEmphasisActive(\.bold), model.writingEmphasisActive(\.italic),
                    model.writingEmphasisActive(\.underline), model.writingEmphasisActive(\.strikethrough)]))
        }
    }

    private static func capture(_ model: ScreenplayViewModel) -> Snapshot {
        guard model.workflowMode == .writing, !model.navigationVisible, !model.contextAssistantVisible,
              !model.titlePagePresented, !model.commandPaletteVisible, !model.packageSheetOpen else {
            return .full(UUID())
        }
        let selected = model.selectedElement
        let projection = model.printedLayout
        // Each entry corresponds to displayed writing chrome or a bound control.
        // Keep text/selection offsets out: commands read the live model when invoked.
        let values: [String?] = [model.documentDisplayName, model.documentLocation,
            model.saveProblem, String(model.hasUnsavedChanges), String(model.saveURL != nil),
            String(!model.recoveryCopies.isEmpty), model.sourceNavigationProblem,
            String(model.canUndo), String(model.canRedo), model.sidebarMode.rawValue,
            String(model.focusMode), String(model.darkPageMode), String(model.pageZoom),
            String(model.pagesAreLocked), String(model.writingPageLayoutAvailable),
            model.errorMessage, model.selectedElementPosition, model.currentPrintedPageStatus,
            model.revisionStatusText, model.currentSceneTitle, selected?.id.uuidString ?? "",
            selected?.type.rawValue ?? "", selected?.revisionMark?.label ?? "",
            String(describing: selected?.revisionMark?.color),
            String(selected.map { model.openNoteCount(for: $0.id) } ?? 0)]
            + (selected.map { model.characterSuggestions(for: $0) } ?? [])
        return .writing(Writing(documentID: model.document?.screenplay.id, typography: model.writingTypography,
            labels: projection.pages.map(\.label),
            enabledPages: projection.pages.indices.map { projection.firstSourceCaret(onPage: $0) != nil },
            values: values, emphasis: [model.writingEmphasisActive(\.bold), model.writingEmphasisActive(\.italic),
                model.writingEmphasisActive(\.underline), model.writingEmphasisActive(\.strikethrough)]))
    }
}

/// Bindings still invoke the canonical model; only redraw notifications are filtered.
@MainActor
@propertyWrapper
struct ChromeObserved: DynamicProperty {
    let wrappedValue: ScreenplayViewModel
    @ObservedObject private var changes: ScreenplayChromeState.Signal
    init(wrappedValue model: ScreenplayViewModel, _ region: ScreenplayChromeState.Region = .all) {
        wrappedValue = model
        _changes = ObservedObject(wrappedValue: model.chromeState.signal(for: region, model: model))
    }
    @dynamicMemberLookup
    @MainActor
    struct Bindings {
        let model: ScreenplayViewModel
        subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ScreenplayViewModel, Value>) -> Binding<Value> {
            Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
        }
    }
    var projectedValue: Bindings { Bindings(model: wrappedValue) }
}
