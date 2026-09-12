import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain
import ScreenplayFDX

@MainActor
final class ScreenplayViewModel: ObservableObject {
    @Published private(set) var document: OpenScreenplayDocument?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var saveURL: URL?
    @Published var errorMessage: String?
    @Published var selectedElementID: UUID?
    @Published private(set) var selectedObject: ObjectSelection = .none
    @Published private(set) var currentSceneSpineID: String?
    @Published private(set) var currentShotID: UUID?
    @Published private(set) var currentBoardFrameID: UUID?
    @Published var scrollTargetElementID: UUID?
    @Published var findQuery = ""
    @Published var replaceText = ""
    @Published var characterToRename = ""
    @Published var newCharacterName = ""
    @Published var workflowMode: WorkflowMode = .writing
    @Published var sidebarMode: SidebarMode = .navigator {
        didSet {
            rememberSidebarMode(sidebarMode, for: workflowMode)
        }
    }
    @Published var focusMode = false
    @Published var darkPageMode = false
    @Published var pageZoom = 1.0
    @Published var navigationVisible = true
    @Published var contextAssistantVisible = true
    @Published var commandPaletteVisible = false
    @Published var commandPaletteQuery = ""
    @Published var contextAssistantPrompt = ""
    @Published var selectedReportKind: ReportKind = .scene
    @Published var selectedProductionExportKind: ProductionExportKind = .selectedScenePacket
    @Published var selectedOutlineTemplate: OutlineTemplateKind = .heroJourney
    @Published var snapshotName = ""
    @Published var draftScriptNote = ""
    @Published private(set) var boardomaticIsPlaying = false
    @Published private(set) var boardomaticPlayheadSeconds = 0.0
    @Published private(set) var contextAssistantJobs: [ContextAssistantJob] = []
    @Published private(set) var recentDocuments: [RecentDocument] = []
    @Published private(set) var snapshots: [ProjectSnapshot] = []

    private let importer = FDXImporter()
    private var undoStack: [OpenScreenplayDocument] = []
    private var lastBoardomaticTick: Date?
    private let undoLimit = 100
    private let recentDocumentsKey = "ScreenplayOSRecentDocuments"
    private var lastSidebarModeByWorkflow: [WorkflowMode: SidebarMode] = [
        .writing: .navigator,
        .outline: .outline,
        .directing: .breakdown,
        .boards: .boards,
        .edit: .editorial
    ]

    init() {
        loadRecentDocuments()
        loadMostRecentWorkingDocument()
    }

    var elements: [ScreenplayElement] {
        document?.screenplay.elements ?? []
    }

    var title: String {
        document?.project.metadata.title.replacingOccurrences(of: "_", with: " ") ?? "ScreenplayOS"
    }

    var workflowFocusLabel: String {
        switch workflowMode {
        case .outline:
            return "STORY"
        case .writing:
            return "WORDS"
        case .directing:
            return "COVERAGE"
        case .boards:
            return "IMAGES"
        case .production:
            return "CONTEXT"
        case .edit:
            return "TIME"
        }
    }

    var sceneCount: Int {
        elements.filter { $0.type == .sceneHeading }.count
    }

    var scenes: [SceneSummary] {
        elements.enumerated().compactMap { index, element in
            guard element.type == .sceneHeading else {
                return nil
            }

            return SceneSummary(
                number: sceneNumber(through: index),
                elementID: element.id,
                title: element.text.isEmpty ? "Untitled Scene" : element.text
            )
        }
    }

    var sceneBreakdowns: [SceneBreakdown] {
        let sceneIndexes = elements.indices.filter { elements[$0].type == .sceneHeading }

        return sceneIndexes.enumerated().map { offset, startIndex in
            let endIndex = sceneIndexes.dropFirst(offset + 1).first ?? elements.count
            let sceneElements = Array(elements[startIndex..<endIndex])
            let sourceIDs = Set(sceneElements.map(\.id))
            let heading = elements[startIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let characters = Set(sceneElements.filter { $0.type == .character }.map(\.text)).sorted()
            let locations = [locationName(from: heading)].filter { !$0.isEmpty }
            let props = productionEntitiesForScene(sourceIDs: sourceIDs, kind: .prop)
            let vfx = productionEntitiesForScene(sourceIDs: sourceIDs, kind: .visualEffect)
            let notes = productionNotes.filter { note in
                note.status != .ignored && !Set(note.sourceElementIDs).isDisjoint(with: sourceIDs)
            }
            let firstAction = sceneElements.first { $0.type == .action }?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let revisionCount = sceneElements.filter { $0.revisionMark != nil }.count
            let spineID = elements[startIndex].spineID ?? elements[startIndex].id.uuidString

            return SceneBreakdown(
                number: offset + 1,
                editSpineID: spineID,
                elementID: elements[startIndex].id,
                heading: heading.isEmpty ? "Untitled Scene" : heading,
                pageNumber: pageNumber(for: elements[startIndex].id),
                elementCount: sceneElements.count,
                actionBeatCount: sceneElements.filter { $0.type == .action || $0.type == .shot }.count,
                revisionCount: revisionCount,
                characters: characters,
                locations: locations,
                props: props,
                visualEffects: vfx,
                notes: notes.map(\.title),
                firstAction: firstAction
            )
        }
    }

    var screenplayPages: [ScreenplayPage] {
        paginate(elements)
    }

    var formatIssues: [FormatIssue] {
        var issues: [FormatIssue] = []
        for (index, element) in elements.enumerated() {
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append(FormatIssue(
                    elementID: element.id,
                    title: "Empty element",
                    detail: "This blank line can be removed.",
                    severity: .cleanup
                ))
                continue
            }

            switch element.type {
            case .dialogue:
                if !hasPreviousDialogueCue(before: index) {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Dialogue without character",
                        detail: "Dialogue should follow a Character or Parenthetical line.",
                        severity: .warning
                    ))
                }
            case .action:
                if trimmed.count > 650 {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Long action block",
                        detail: "Consider splitting this action into shorter visual beats.",
                        severity: .cleanup
                    ))
                }
            case .character:
                if !trimmed.isUppercase {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Character not uppercase",
                        detail: "Character cues are normally uppercase.",
                        severity: .cleanup
                    ))
                }
                if !hasDialogueAfterCharacter(at: index) {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Character without dialogue",
                        detail: "A Character line should usually be followed by Dialogue or Parenthetical.",
                        severity: .warning
                    ))
                }
            case .parenthetical:
                if !hasPreviousCharacterCue(before: index) {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Parenthetical without character",
                        detail: "Parentheticals should follow a Character line or another Parenthetical.",
                        severity: .warning
                    ))
                }
            case .sceneHeading, .transition, .shot:
                if !trimmed.isUppercase {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "\(element.type.displayName) not uppercase",
                        detail: "This element type is normally uppercase.",
                        severity: .cleanup
                    ))
                }
                if element.type == .sceneHeading,
                   index + 1 < elements.count,
                   elements[index + 1].type == .sceneHeading {
                    issues.append(FormatIssue(
                        elementID: element.id,
                        title: "Scene heading without action",
                        detail: "A scene heading is usually followed by action before the next scene.",
                        severity: .warning
                    ))
                }
            default:
                break
            }
        }

        for page in screenplayPages.dropLast() {
            guard let last = page.elements.last else {
                continue
            }

            switch last.element.type {
            case .character:
                issues.append(FormatIssue(
                    elementID: last.element.id,
                    title: "Character cue at page bottom",
                    detail: "Keep character cues with their dialogue on the next page.",
                    severity: .warning
                ))
            case .sceneHeading:
                issues.append(FormatIssue(
                    elementID: last.element.id,
                    title: "Scene heading at page bottom",
                    detail: "Keep scene headings with the first action line when possible.",
                    severity: .warning
                ))
            default:
                break
            }
        }

        return issues
    }

    var characterNames: [String] {
        Set(elements.filter { $0.type == .character }.map(\.text)).sorted()
    }

    var findMatches: [FindMatch] {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        return elements.enumerated().compactMap { index, element in
            guard element.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                return nil
            }

            return FindMatch(
                number: index + 1,
                elementID: element.id,
                elementType: element.type.displayName,
                preview: element.text
            )
        }
    }

    var selectedElement: ScreenplayElement? {
        guard let selectedElementID else {
            return nil
        }
        return elements.first { $0.id == selectedElementID }
    }

    var selectedElementPosition: String {
        guard let selectedElementID, let index = elementIndex(for: selectedElementID) else {
            return "No selection"
        }

        return "\(index + 1) of \(elements.count)"
    }

    var currentSceneTitle: String {
        guard let selectedElementID, let selectedIndex = elementIndex(for: selectedElementID) else {
            return "No Scene"
        }

        let scene = elements.prefix(through: selectedIndex).last { $0.type == .sceneHeading }
        let title = scene?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "No Scene" : title
    }

    var selectedElementTypeName: String {
        selectedElement?.type.displayName ?? "Element"
    }

    var nextReturnElementName: String {
        guard let selectedElement else {
            return "Action"
        }

        return nextElementType(after: selectedElement.type).displayName
    }

    var nextTabElementName: String {
        guard let selectedElement else {
            return "Action"
        }

        let types = ElementType.editorTypes
        guard let index = types.firstIndex(of: selectedElement.type) else {
            return "Action"
        }

        return types[(index + 1) % types.count].displayName
    }

    var titlePage: TitlePage {
        document?.titlePage ?? TitlePage(title: title)
    }

    var revisionSettings: RevisionSettings {
        document?.screenplay.revisionSettings ?? RevisionSettings()
    }

    var revisionModeEnabled: Bool {
        revisionSettings.modeEnabled
    }

    var revisionLabel: String {
        revisionSettings.label
    }

    var revisionColor: RevisionColor {
        revisionSettings.color
    }

    var revisionMarkCount: Int {
        elements.filter { $0.revisionMark != nil }.count
    }

    var revisionStatusText: String {
        revisionModeEnabled ? "\(revisionLabel) on" : "Revision off"
    }

    var productionContext: ProductionContext {
        document?.productionContext ?? ProductionContext()
    }

    var productionContextEnabled: Bool {
        productionContext.contextEnabled
    }

    var productionEntities: [ProductionEntity] {
        productionContext.entities
    }

    var productionNotes: [ProductionNote] {
        productionContext.notes
    }

    var productionContextSummary: String {
        let accepted = productionEntities.filter { $0.status == .accepted }.count
        return productionContextEnabled ? "\(accepted) accepted / \(productionEntities.count) records" : "Context off"
    }

    var aiSettings: AISettings {
        document?.aiSettings ?? AISettings()
    }

    var currentWorkflowAIEnabled: Bool {
        switch workflowMode {
        case .writing:
            return aiSettings.writingEnabled
        case .outline:
            return aiSettings.outlineEnabled
        case .directing:
            return aiSettings.directingEnabled
        case .boards:
            return aiSettings.boardsEnabled
        case .production:
            return aiSettings.productionEnabled
        case .edit:
            return aiSettings.editEnabled
        }
    }

    var aiProposalSummary: String {
        let current = proposalsForCurrentWorkflow
        let open = current.filter { $0.status == .suggested }.count
        return currentWorkflowAIEnabled ? "\(open) open / \(current.count) proposals" : "AI off"
    }

    var proposals: [AIProposal] {
        document?.proposals ?? []
    }

    var proposalsForCurrentWorkflow: [AIProposal] {
        proposals
            .filter { $0.workflow.workflowMode == workflowMode }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activityEvents: [ActivityEvent] {
        (document?.activity ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var outlineBeats: [OutlineBeat] {
        (document?.outline ?? []).sorted { $0.order < $1.order }
    }

    var scriptNotes: [ScriptNote] {
        (document?.scriptNotes ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var openScriptNotes: [ScriptNote] {
        scriptNotes.filter { $0.status == .open }
    }

    var scriptNotesForSelectedScene: [ScriptNote] {
        guard let selectedSceneBreakdown else {
            return []
        }

        return scriptNotes.filter { $0.sceneSpineID == selectedSceneBreakdown.editSpineID }
    }

    var selectedElementNoteCount: Int {
        guard let selectedElementID else {
            return 0
        }

        return scriptNotes.filter { $0.screenplayElementID == selectedElementID && $0.status == .open }.count
    }

    func openNoteCount(for elementID: UUID) -> Int {
        scriptNotes.filter { $0.screenplayElementID == elementID && $0.status == .open }.count
    }

    var outlineCoverageSummary: String {
        guard !outlineBeats.isEmpty else {
            return "No outline"
        }

        let mapped = outlineBeats.filter { !$0.linkedSceneSpineIDs.isEmpty }.count
        return "\(mapped) of \(outlineBeats.count) beats mapped"
    }

    var shots: [Shot] {
        document?.shots ?? []
    }

    var boardFrames: [BoardFrame] {
        document?.boardFrames ?? []
    }

    var editorialBeats: [EditorialBeat] {
        (document?.editorialSpine.sequences ?? [])
            .flatMap(\.beats)
            .sorted { $0.order < $1.order }
    }

    var editClipsForSelectedScene: [EditClip] {
        guard let selectedSceneBreakdown else {
            return []
        }

        return editorialBeats
            .filter { $0.sceneSpineID == selectedSceneBreakdown.editSpineID }
            .flatMap(\.editClips)
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
    }

    var editTimelineDurationText: String {
        let duration = editorialBeats.flatMap(\.editClips).reduce(0.0) { $0 + $1.timelineDurationSeconds }
        return String(format: "%.1fs edit spine", duration)
    }

    var commandPaletteCommands: [CommandPaletteCommand] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return CommandPaletteCommand.allCases
        }

        return CommandPaletteCommand.allCases.filter {
            $0.searchableText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var sidebarModesForCurrentWorkflow: [SidebarMode] {
        SidebarMode.allCases.filter { $0.workflowMode == workflowMode || $0.isCrossCutting }
    }

    var visibleWorkspaceRegions: Set<WorkspaceRegion> {
        guard !focusMode else {
            return [.primaryWorkspace]
        }

        var regions: Set<WorkspaceRegion> = [.primaryWorkspace]
        if navigationVisible {
            regions.insert(.navigation)
        }
        if contextAssistantVisible {
            regions.insert(.context)
        }
        return regions
    }

    var selectionContext: SelectionContext {
        if let objectContext = selectionContext(for: selectedObject) {
            return objectContext
        }

        return scriptSelectionContext
    }

    private var scriptSelectionContext: SelectionContext {
        guard let selectedElement else {
            return .empty(workflowMode: workflowMode)
        }

        let trimmedText = selectedElement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedText.isEmpty ? selectedElement.type.displayName : trimmedText
        let sceneSpineID = selectedElement.type == .sceneHeading
            ? selectedElement.spineID
            : selectedSceneBreakdown?.editSpineID
        let kind: SelectionKind = selectedElement.type == .sceneHeading ? .scene : .screenplayElement

        return SelectionContext(
            kind: kind,
            id: selectedElement.id,
            sceneSpineID: sceneSpineID,
            title: title,
            detail: "\(selectedElement.type.displayName) | \(selectedElementPosition)",
            workflowMode: workflowMode
        )
    }

    var inspectorContext: InspectorContext {
        let selection = selectionContext
        return InspectorContext(
            selection: selection,
            title: selection.title,
            subtitle: selection.detail,
            details: inspectorDetails(for: selection),
            actions: inspectorActions(for: selection)
        )
    }

    var selectedSceneBreakdown: SceneBreakdown? {
        if let currentSceneSpineID,
           let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == currentSceneSpineID }) {
            return breakdown
        }

        guard let selectedElementID, let index = elementIndex(for: selectedElementID) else {
            return sceneBreakdowns.first
        }

        let sceneIndex = elements.prefix(through: index).last { $0.type == .sceneHeading }?.id
        return sceneBreakdowns.first { $0.elementID == sceneIndex } ?? sceneBreakdowns.first
    }

    var shotsForSelectedScene: [Shot] {
        guard let selectedSceneBreakdown else {
            return []
        }

        return shots
            .filter { $0.sceneSpineID == selectedSceneBreakdown.editSpineID }
            .sorted { $0.shotNumber < $1.shotNumber }
    }

    var boardFramesForSelectedScene: [BoardFrame] {
        guard let selectedSceneBreakdown else {
            return []
        }

        return boardFrames
            .filter { $0.sceneSpineID == selectedSceneBreakdown.editSpineID }
            .sorted { $0.frameNumber < $1.frameNumber }
    }

    var selectedShot: Shot? {
        if let currentShotID,
           let shot = shots.first(where: { $0.id == currentShotID }) {
            return shot
        }

        if selectedObject.kind == .shot,
           let id = selectedObject.id,
           let shot = shots.first(where: { $0.id == id }) {
            return shot
        }

        return shotsForSelectedScene.first
    }

    var selectedBoardFrame: BoardFrame? {
        if let currentBoardFrameID,
           let frame = boardFrames.first(where: { $0.id == currentBoardFrameID }) {
            return frame
        }

        if selectedObject.kind == .boardFrame,
           let id = selectedObject.id,
           let frame = boardFrames.first(where: { $0.id == id }) {
            return frame
        }

        if let currentShotID,
           let frame = boardFrames.first(where: { $0.shotID == currentShotID }) {
            return frame
        }

        return boardFramesForSelectedScene.first
    }

    var selectedSceneScriptElements: [ScreenplayElement] {
        guard let selectedSceneBreakdown,
              let startIndex = elements.firstIndex(where: { $0.id == selectedSceneBreakdown.elementID })
        else {
            return []
        }

        let endIndex = elements.indices.dropFirst(startIndex + 1).first { elements[$0].type == .sceneHeading } ?? elements.count
        return Array(elements[startIndex..<endIndex])
    }

    var boardomaticDurationText: String {
        String(format: "%.1fs", boardomaticTotalDuration)
    }

    var boardomaticTotalDuration: Double {
        boardFramesForSelectedScene.reduce(0.0) { $0 + $1.durationSeconds }
    }

    var boardomaticProgress: Double {
        guard boardomaticTotalDuration > 0 else {
            return 0
        }

        return min(1, max(0, boardomaticPlayheadSeconds / boardomaticTotalDuration))
    }

    var boardomaticPlayheadText: String {
        String(format: "%.1fs / %.1fs", min(boardomaticPlayheadSeconds, boardomaticTotalDuration), boardomaticTotalDuration)
    }

    var activeBoardFrame: BoardFrame? {
        selectedBoardFrame ?? boardFramesForSelectedScene.first
    }

    var contextAssistantStarterPrompts: [String] {
        [
            "Find continuity questions",
            "List production risks",
            "Suggest shot candidates",
            "Summarize character arcs"
        ]
    }

    var reportPreview: String {
        reportText(for: selectedReportKind)
    }

    var productionExportPreview: String {
        switch selectedProductionExportKind {
        case .selectedScenePacket:
            return selectedSceneProductionPacket()
        case .sceneBreakdownCSV:
            return sceneBreakdownCSV()
        case .shotListCSV:
            return shotListCSV()
        case .boardFramesCSV:
            return boardFramesCSV()
        case .editGuideCSV:
            return editGuideCSV()
        case .editTimelineCSV:
            return editTimelineCSV()
        }
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var subtitle: String {
        if let saveURL {
            return saveURL.lastPathComponent
        }
        if let sourceURL {
            return "Imported from \(sourceURL.lastPathComponent)"
        }
        return "Unsaved"
    }

    var documentDisplayName: String {
        if let saveURL {
            return saveURL.deletingPathExtension().deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }

        if let sourceURL {
            return sourceURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }

        return title
    }

    var documentLocation: String {
        if let saveURL {
            return saveURL.path
        }

        if let sourceURL {
            return "Imported from \(sourceURL.path)"
        }

        return "New unsaved screenplay"
    }

    var lastSnapshotSummary: String {
        guard let snapshot = snapshots.first else {
            return "No snapshots"
        }

        return "\(snapshot.name) · \(snapshot.displayDate)"
    }

    func newDocument() {
        let screenplay = Screenplay(
            metadata: ScreenplayMetadata(title: "Untitled Screenplay"),
            elements: [
                ScreenplayElement(type: .sceneHeading, text: ""),
                ScreenplayElement(type: .action, text: "")
            ]
        )
        let project = Project(
            metadata: ProjectMetadata(title: "Untitled Screenplay", author: ""),
            screenplayID: screenplay.id
        )

        document = OpenScreenplayDocument(
            project: project,
            screenplay: screenplay,
            titlePage: TitlePage(title: "Untitled Screenplay")
        )
        sourceURL = nil
        saveURL = nil
        undoStack = []
        findQuery = ""
        replaceText = ""
        characterToRename = ""
        newCharacterName = ""
        sidebarMode = .navigator
        selectInitialElement()
        errorMessage = "New screenplay"
    }

    func setProductionContextEnabled(_ enabled: Bool) {
        guard document != nil else {
            return
        }

        document?.productionContext.contextEnabled = enabled
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func refreshProductionContextFromScript() {
        guard document != nil else {
            return
        }

        rememberUndoState()
        document?.productionContext.entities = extractedProductionEntities()
        document?.productionContext.notes = extractedProductionNotes()
        document?.productionContext.generatedAt = Date()
        recordActivity(
            actor: .manual,
            action: "Refreshed production context",
            detail: "Extracted context records and notes from the screenplay.",
            target: AIProposalTarget()
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setProductionEntityStatus(_ entityID: UUID, status: ProductionEntityStatus) {
        guard let index = document?.productionContext.entities.firstIndex(where: { $0.id == entityID }) else {
            return
        }

        rememberUndoState()
        document?.productionContext.entities[index].status = status
        recordActivity(
            actor: .manual,
            action: "Set context status",
            detail: "\(document?.productionContext.entities[index].name ?? "Context record") -> \(status.rawValue)",
            target: AIProposalTarget(contextRecordID: entityID)
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setProductionNoteStatus(_ noteID: UUID, status: ProductionEntityStatus) {
        guard let index = productionNoteIndex(for: noteID) else {
            return
        }

        rememberUndoState()
        document?.productionContext.notes[index].status = status
        recordActivity(
            actor: .manual,
            action: "Set note status",
            detail: "\(document?.productionContext.notes[index].title ?? "Production note") -> \(status.rawValue)",
            target: AIProposalTarget()
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func seedSelectedOutlineTemplate() {
        guard document != nil else {
            return
        }

        rememberUndoState()
        document?.outline = outlineTemplate(selectedOutlineTemplate)
        recordActivity(
            actor: .manual,
            action: "Seeded outline",
            detail: "Created a \(selectedOutlineTemplate.displayName) outline template.",
            target: AIProposalTarget()
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func bindingForOutlineNotes(_ beat: OutlineBeat) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.outlineBeat(id: beat.id)?.notes ?? beat.notes
            },
            set: { [weak self] value in
                self?.updateOutlineBeat(id: beat.id, notes: value)
            }
        )
    }

    func linkSelectedScene(to beat: OutlineBeat) {
        guard let selectedSceneBreakdown else {
            return
        }
        _ = linkScene(selectedSceneBreakdown.editSpineID, toOutlineBeatID: beat.id)
    }

    func linkScene(_ sceneSpineID: String, toOutlineBeatID outlineBeatID: UUID, actor: ActivityActor = .manual) -> Bool {
        guard
            let outlineIndex = document?.outline.firstIndex(where: { $0.id == outlineBeatID }),
            let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID })
        else {
            return false
        }

        var links = document?.outline[outlineIndex].linkedSceneSpineIDs ?? []
        guard !links.contains(sceneSpineID) else {
            return true
        }

        rememberUndoState()
        links.append(sceneSpineID)
        document?.outline[outlineIndex].linkedSceneSpineIDs = links.sorted()
        let beatName = document?.outline[outlineIndex].name ?? "Outline beat"
        recordActivity(
            actor: actor,
            action: "Linked outline beat",
            detail: "\(beatName) -> \(sceneSpineID)",
            target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: sceneSpineID, outlineBeatID: outlineBeatID)
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
        return true
    }

    func unlinkScene(_ sceneSpineID: String, from beat: OutlineBeat) {
        guard let index = document?.outline.firstIndex(where: { $0.id == beat.id }) else {
            return
        }

        rememberUndoState()
        document?.outline[index].linkedSceneSpineIDs.removeAll { $0 == sceneSpineID }
        recordActivity(
            actor: .manual,
            action: "Unlinked outline beat",
            detail: "\(beat.name) removed \(sceneSpineID)",
            target: AIProposalTarget(sceneSpineID: sceneSpineID)
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func navigateToSceneSpineID(_ sceneSpineID: String) {
        guard let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID }) else {
            return
        }

        navigateToSceneBreakdown(breakdown)
    }

    func sceneTitle(for sceneSpineID: String) -> String {
        sceneBreakdowns.first { $0.editSpineID == sceneSpineID }?.heading ?? sceneSpineID
    }

    func setAIEnabled(_ enabled: Bool, for mode: WorkflowMode) {
        guard document != nil else {
            return
        }

        rememberUndoState()
        switch mode {
        case .writing:
            document?.aiSettings.writingEnabled = enabled
        case .outline:
            document?.aiSettings.outlineEnabled = enabled
        case .directing:
            document?.aiSettings.directingEnabled = enabled
        case .boards:
            document?.aiSettings.boardsEnabled = enabled
        case .production:
            document?.aiSettings.productionEnabled = enabled
        case .edit:
            document?.aiSettings.editEnabled = enabled
        }
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func generateProposalsForCurrentWorkflow() {
        guard document != nil, currentWorkflowAIEnabled else {
            errorMessage = "Turn on \(workflowMode.rawValue) AI first."
            return
        }

        rememberUndoState()
        document?.proposals.removeAll { $0.workflow.workflowMode == workflowMode && $0.status == .suggested }
        document?.proposals.insert(contentsOf: generatedProposals(for: workflowMode), at: 0)
        recordActivity(
            actor: .system,
            action: "Generated proposals",
            detail: "Generated \(workflowMode.rawValue) proposal cards.",
            target: AIProposalTarget()
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setProposalStatus(_ proposalID: UUID, status: AIProposalStatus) {
        guard let index = document?.proposals.firstIndex(where: { $0.id == proposalID }) else {
            return
        }

        rememberUndoState()
        document?.proposals[index].status = status
        recordActivity(
            actor: .manual,
            action: "Set proposal status",
            detail: "\(document?.proposals[index].title ?? "Proposal") -> \(status.rawValue)",
            target: document?.proposals[index].target ?? AIProposalTarget()
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func applyProposal(_ proposal: AIProposal) {
        guard let index = document?.proposals.firstIndex(where: { $0.id == proposal.id }) else {
            return
        }

        let applied = applyTrustedAction(for: proposal)
        if applied {
            document?.proposals[index].status = .applied
            recordActivity(
                actor: .proposal,
                action: "Applied proposal",
                detail: proposal.title,
                target: proposal.target
            )
            document?.project.metadata.modifiedAt = Date()
            autosave()
            errorMessage = "Applied \(proposal.title)"
        }
    }

    func navigateToProposalTarget(_ proposal: AIProposal) {
        if let elementID = proposal.target.screenplayElementID {
            selectElement(id: elementID)
            scrollTargetElementID = elementID
            return
        }

        if let sceneSpineID = proposal.target.sceneSpineID,
           let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID }) {
            navigateToSceneBreakdown(breakdown)
        }
    }

    func runContextAssistantPrompt(_ prompt: String? = nil) {
        let request = (prompt ?? contextAssistantPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, document != nil else {
            return
        }

        let job = ContextAssistantJob(prompt: request, status: .running, summary: "Reading script context")
        contextAssistantJobs.insert(job, at: 0)
        contextAssistantPrompt = ""

        let result = contextAssistantResult(for: request)
        if let index = contextAssistantJobs.firstIndex(where: { $0.id == job.id }) {
            contextAssistantJobs[index].status = .complete
            contextAssistantJobs[index].summary = result.summary
            contextAssistantJobs[index].createdRecords = result.recordCount
        }

        if !result.notes.isEmpty || !result.entities.isEmpty {
            rememberUndoState()
            document?.productionContext.notes.insert(contentsOf: result.notes, at: 0)
            document?.productionContext.entities.append(contentsOf: result.entities)
            document?.productionContext.generatedAt = Date()
            recordActivity(
                actor: .contextAssistant,
                action: "Ran context assistant",
                detail: request,
                target: AIProposalTarget()
            )
            document?.project.metadata.modifiedAt = Date()
            autosave()
        }
    }

    func clearContextAssistantJobs() {
        contextAssistantJobs = []
    }

    func setRevisionMode(_ enabled: Bool) {
        guard document != nil else {
            return
        }

        rememberUndoState()
        document?.screenplay.revisionSettings.modeEnabled = enabled
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setRevisionLabel(_ label: String) {
        guard document != nil else {
            return
        }

        document?.screenplay.revisionSettings.label = label
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setRevisionColor(_ color: RevisionColor) {
        guard document != nil else {
            return
        }

        rememberUndoState()
        document?.screenplay.revisionSettings.color = color
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func clearRevisionMarks() {
        guard document != nil, revisionMarkCount > 0 else {
            return
        }

        rememberUndoState()
        for index in elements.indices {
            document?.screenplay.elements[index].revisionMark = nil
        }
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        let fdxType = UTType(filenameExtension: "fdx") ?? .xml
        panel.allowedContentTypes = [fdxType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Screenplay or Final Draft FDX"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            openDocument(at: url)
        }
    }

    func save() {
        saveDocument(to: saveURL ?? defaultDownloadsSaveURL())
    }

    func showSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.title = "Save Open Screenplay"
        panel.prompt = "Save"
        panel.nameFieldStringValue = defaultSaveFileName()

        if panel.runModal() == .OK, let url = panel.url {
            saveDocument(to: url)
        }
    }

    func showExportPDFPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.title = "Export PDF"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(title.replacingOccurrences(of: "/", with: "-")).pdf"

        if panel.runModal() == .OK, let url = panel.url {
            exportPDF(to: url)
        }
    }

    func showExportReportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Export Report"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultReportFileName(for: selectedReportKind)

        if panel.runModal() == .OK, let url = panel.url {
            exportReport(to: url, kind: selectedReportKind)
        }
    }

    func showProductionExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = selectedProductionExportKind.fileExtension == "csv" ? [.commaSeparatedText] : [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Export Edit File"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultProductionExportFileName(for: selectedProductionExportKind)

        if panel.runModal() == .OK, let url = panel.url {
            exportProductionFile(to: url, kind: selectedProductionExportKind)
        }
    }

    func openDocument(at url: URL) {
        switch url.pathExtension.lowercased() {
        case "json":
            loadOpenScreenplay(at: url)
        default:
            loadFDX(at: url)
        }
    }

    func loadFDX(at url: URL) {
        do {
            let result = try importer.importFile(at: url)
            document = result.document
            undoStack = []
            sourceURL = url
            saveURL = nil
            snapshots = []
            selectInitialElement()
            recordRecentDocument(url)
            errorMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOpenScreenplay(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: data)
            document = decoded
            undoStack = []
            sourceURL = url
            saveURL = url
            selectInitialElement()
            recordRecentDocument(url)
            loadSnapshots()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSnapshot() {
        guard let document else {
            return
        }

        let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? "Snapshot" : name
        let projectURL = saveURL ?? defaultDownloadsSaveURL()

        if saveURL == nil {
            saveDocument(to: projectURL, reportStatus: false)
        }

        do {
            let directory = snapshotsDirectory(for: projectURL)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(snapshotFileName(label: label, date: Date()))
            let data = try JSONEncoder.openScreenplayEncoder().encode(document)
            try data.write(to: url, options: .atomic)
            snapshotName = ""
            loadSnapshots()
            recordActivity(
                actor: .manual,
                action: "Created snapshot",
                detail: "\(label) -> \(url.lastPathComponent)",
                target: AIProposalTarget()
            )
            autosave()
            errorMessage = "Snapshot created: \(label)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreSnapshot(_ snapshot: ProjectSnapshot) {
        guard FileManager.default.fileExists(atPath: snapshot.url.path) else {
            errorMessage = "Snapshot file is missing."
            loadSnapshots()
            return
        }

        do {
            createSafetySnapshotBeforeRestore()
            let data = try Data(contentsOf: snapshot.url)
            let decoded = try JSONDecoder.openScreenplayDecoder().decode(OpenScreenplayDocument.self, from: data)
            rememberUndoState()
            document = decoded
            selectInitialElement()
            if let saveURL {
                saveDocument(to: saveURL, reportStatus: false)
            }
            loadSnapshots()
            recordActivity(
                actor: .manual,
                action: "Restored snapshot",
                detail: snapshot.name,
                target: AIProposalTarget()
            )
            autosave()
            errorMessage = "Restored snapshot: \(snapshot.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealSnapshotInFinder(_ snapshot: ProjectSnapshot) {
        NSWorkspace.shared.activateFileViewerSelecting([snapshot.url])
    }

    func addNoteToSelectedElement() {
        guard
            let selectedElementID,
            let sceneSpineID = sceneSpineID(containing: selectedElementID)
        else {
            errorMessage = "Select a script line before adding a note."
            return
        }

        let body = draftScriptNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return
        }

        rememberUndoState()
        let note = ScriptNote(screenplayElementID: selectedElementID, sceneSpineID: sceneSpineID, body: body)
        self.document?.scriptNotes.insert(note, at: 0)
        self.document?.project.metadata.modifiedAt = Date()
        draftScriptNote = ""
        recordActivity(
            actor: .manual,
            action: "Added script note",
            detail: body,
            target: AIProposalTarget(screenplayElementID: selectedElementID, sceneSpineID: sceneSpineID)
        )
        autosave()
    }

    func setScriptNoteStatus(_ status: ScriptNoteStatus, for noteID: UUID) {
        guard let index = document?.scriptNotes.firstIndex(where: { $0.id == noteID }) else {
            return
        }

        rememberUndoState()
        document?.scriptNotes[index].status = status
        document?.scriptNotes[index].resolvedAt = status == .resolved ? Date() : nil
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func navigateToScriptNote(_ note: ScriptNote) {
        selectedElementID = note.screenplayElementID
        selectedObject = .screenplayElement(note.screenplayElementID)
        setFilmContext(sceneSpineID: note.sceneSpineID, preserveShot: true, preserveBoard: true)
        scrollTargetElementID = note.screenplayElementID
    }

    func showNotesForElement(_ elementID: UUID) {
        selectElement(id: elementID)
        showSidebarMode(.notes)
    }

    func binding(for element: ScreenplayElement) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.element(id: element.id)?.text ?? element.text
            },
            set: { [weak self] newValue in
                self?.updateElement(id: element.id, text: newValue.trimmingCharacters(in: .newlines))
            }
        )
    }

    func titlePageBinding(_ field: TitlePageField) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.titlePageValue(field) ?? ""
            },
            set: { [weak self] newValue in
                self?.updateTitlePage(field, value: newValue)
            }
        )
    }

    func selectElement(id: UUID) {
        selectedElementID = id
        selectedObject = .screenplayElement(id)
        setFilmContext(sceneSpineID: sceneSpineID(containing: id), preserveShot: false, preserveBoard: false)
    }

    func selectOutlineBeat(_ beat: OutlineBeat) {
        selectedObject = .outlineBeat(beat.id)
        if let sceneSpineID = beat.linkedSceneSpineIDs.first {
            setFilmContext(sceneSpineID: sceneSpineID, preserveShot: false, preserveBoard: false)
        }
    }

    func selectShot(_ shot: Shot) {
        selectedObject = .shot(shot.id, sceneSpineID: shot.sceneSpineID)
        let matchingBoardID = boardFrames.first { $0.shotID == shot.id }?.id
        setFilmContext(sceneSpineID: shot.sceneSpineID, shotID: shot.id, boardFrameID: matchingBoardID, preserveBoard: false)
    }

    func selectBoardFrame(_ frame: BoardFrame) {
        selectedObject = .boardFrame(frame.id, sceneSpineID: frame.sceneSpineID)
        setFilmContext(sceneSpineID: frame.sceneSpineID, shotID: frame.shotID, boardFrameID: frame.id)
        if let index = boardFramesForSelectedScene.firstIndex(where: { $0.id == frame.id }) {
            boardomaticPlayheadSeconds = boardomaticStartSeconds(forFrameAt: index)
        }
    }

    func selectProductionEntity(_ entity: ProductionEntity) {
        selectedObject = .productionEntity(entity.id)
    }

    func selectProductionNote(_ note: ProductionNote) {
        selectedObject = .productionNote(note.id)
    }

    func selectEditorialBeat(_ beat: EditorialBeat) {
        selectedObject = .editorialBeat(beat.id, sceneSpineID: beat.sceneSpineID)
        setFilmContext(sceneSpineID: beat.sceneSpineID, preserveShot: true, preserveBoard: true)
    }

    func bindingForEditorialNotes(_ beat: EditorialBeat) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.editorialBeat(id: beat.id)?.editNotes ?? beat.editNotes
            },
            set: { [weak self] value in
                self?.updateEditorialBeat(id: beat.id, notes: value)
            }
        )
    }

    func setEditorialBeatStatus(_ status: EditorialBeatStatus, for beatID: UUID) {
        guard let indexPath = editorialBeatIndexPath(for: beatID) else {
            return
        }

        rememberUndoState()
        document?.editorialSpine.sequences[indexPath.sequence].beats[indexPath.beat].status = status
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func performInspectorAction(_ action: InspectorAction) {
        switch action {
        case .jumpToSource:
            navigateToSelectedObjectSource()
        case .changeElementType:
            if let id = selectedObject.id ?? selectedElementID {
                selectElement(id: id)
                sidebarMode = .assistant
            }
        case .linkOutlineBeat:
            linkSelectionToCurrentScene()
        case .generateShots:
            navigateToSelectionScene()
            generateShotListForSelectedScene()
        case .generateBoards:
            navigateToSelectionScene()
            generateBoardsForSelectedScene()
        case .refreshContext:
            refreshProductionContextFromScript()
        case .acceptContext:
            setSelectedContextStatus(.accepted)
        case .ignoreContext:
            setSelectedContextStatus(.ignored)
        }
    }

    func showCommandPalette() {
        commandPaletteQuery = ""
        commandPaletteVisible = true
    }

    func hideCommandPalette() {
        commandPaletteVisible = false
        commandPaletteQuery = ""
    }

    func performCommand(_ command: CommandPaletteCommand) {
        hideCommandPalette()

        switch command {
        case .newScreenplay:
            newDocument()
        case .open:
            showOpenPanel()
        case .save:
            save()
        case .saveAs:
            showSavePanel()
        case .exportPDF:
            showExportPDFPanel()
        case .focusMode:
            focusMode.toggle()
        case .contextInspector:
            contextAssistantVisible.toggle()
        case .cleanScript:
            cleanScript()
        case .deleteBlankElements:
            deleteEmptyElements()
        case .generateProposals:
            generateProposalsForCurrentWorkflow()
        case .refreshContext:
            refreshProductionContextFromScript()
        case .generateShotList:
            generateShotListForSelectedScene()
        case .generateBoards:
            generateBoardsForSelectedScene()
        case .showNavigator:
            showSidebarMode(.navigator, workflow: .writing)
        case .showOutline:
            showSidebarMode(.outline, workflow: .outline)
        case .showSearch:
            showSidebarMode(.search, workflow: .writing)
        case .showFormat:
            showSidebarMode(.assistant, workflow: .writing)
        case .showTitlePage:
            showSidebarMode(.titlePage, workflow: .writing)
        case .showBreakdown:
            showSidebarMode(.breakdown, workflow: .directing)
        case .showBoards:
            showSidebarMode(.boards, workflow: .boards)
        case .showContext:
            showSidebarMode(.productionContext)
        case .showReports:
            showSidebarMode(.reports)
        case .showExports:
            showSidebarMode(.exports, workflow: .edit)
        case .showEditSpine:
            showSidebarMode(.editorial, workflow: .edit)
        case .showActivity:
            sidebarMode = .activity
        case .showSnapshots:
            showSidebarMode(.snapshots)
        case .createSnapshot:
            createSnapshot()
        case .showNotes:
            showSidebarMode(.notes)
        case .addScriptNote:
            addNoteToSelectedElement()
        }
    }

    func characterSuggestions(for element: ScreenplayElement) -> [String] {
        guard element.type == .character else {
            return []
        }

        let query = (self.element(id: element.id)?.text ?? element.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if query.isEmpty {
            return Array(characterNames.prefix(8))
        }

        return characterNames
            .filter { $0.uppercased().hasPrefix(query) && $0.uppercased() != query }
            .prefix(8)
            .map { $0 }
    }

    func applyCharacterSuggestion(_ suggestion: String, to elementID: UUID) {
        updateElement(id: elementID, text: suggestion)
    }

    func navigateToScene(_ scene: SceneSummary) {
        let sceneSpineID = sceneBreakdowns.first { $0.elementID == scene.elementID }?.editSpineID
        selectedElementID = scene.elementID
        selectedObject = .scene(scene.elementID, sceneSpineID: sceneSpineID)
        setFilmContext(sceneSpineID: sceneSpineID, preserveShot: false, preserveBoard: false)
        scrollTargetElementID = scene.elementID
    }

    func navigateToSceneBreakdown(_ breakdown: SceneBreakdown) {
        selectedElementID = breakdown.elementID
        selectedObject = .scene(breakdown.elementID, sceneSpineID: breakdown.editSpineID)
        setFilmContext(sceneSpineID: breakdown.editSpineID, preserveShot: false, preserveBoard: false)
        scrollTargetElementID = breakdown.elementID
    }

    func addSceneAfterSelectedScene() {
        guard var document else {
            return
        }

        let insertIndex: Int
        if let breakdown = selectedSceneBreakdown,
           let range = sceneElementRange(startingAt: breakdown.elementID) {
            insertIndex = range.upperBound
        } else {
            insertIndex = document.screenplay.elements.endIndex
        }

        rememberUndoState()
        let heading = ScreenplayElement(type: .sceneHeading, text: "INT. NEW SCENE - DAY", revisionMark: currentRevisionMark())
        let action = ScreenplayElement(type: .action, text: "", revisionMark: currentRevisionMark())
        document.screenplay.elements.insert(contentsOf: [heading, action], at: insertIndex)
        document.screenplay.revision += 1
        document.project.metadata.modifiedAt = Date()
        document.ensureSceneSpineIDs()
        document.ensureEditorialSpine()
        document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
        self.document = document
        selectElement(id: heading.id)
        scrollTargetElementID = heading.id
        recordActivity(
            actor: .manual,
            action: "Added scene",
            detail: "Inserted a new scene after the selected scene.",
            target: AIProposalTarget(screenplayElementID: heading.id, sceneSpineID: heading.spineID)
        )
        autosave()
    }

    func duplicateSelectedScene() {
        guard var document,
              let breakdown = selectedSceneBreakdown,
              let range = sceneElementRange(startingAt: breakdown.elementID)
        else {
            return
        }

        rememberUndoState()
        let duplicated = document.screenplay.elements[range].map { element in
            ScreenplayElement(
                type: element.type,
                text: element.text,
                spineID: nil,
                externalIDs: [:],
                revisionMark: currentRevisionMark() ?? element.revisionMark
            )
        }
        document.screenplay.elements.insert(contentsOf: duplicated, at: range.upperBound)
        document.screenplay.revision += 1
        document.project.metadata.modifiedAt = Date()
        document.ensureSceneSpineIDs()
        document.ensureEditorialSpine()
        document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
        self.document = document

        if let firstID = duplicated.first?.id {
            selectElement(id: firstID)
            scrollTargetElementID = firstID
        }

        recordActivity(
            actor: .manual,
            action: "Duplicated scene",
            detail: "Duplicated \(breakdown.editSpineID) as a new script scene.",
            target: AIProposalTarget(sceneSpineID: currentSceneSpineID)
        )
        autosave()
    }

    func deleteSelectedScene() {
        guard var document,
              document.screenplay.elements.filter({ $0.type == .sceneHeading }).count > 1,
              let breakdown = selectedSceneBreakdown,
              let range = sceneElementRange(startingAt: breakdown.elementID)
        else {
            errorMessage = "Keep at least one scene in the screenplay."
            return
        }

        rememberUndoState()
        document.screenplay.elements.removeSubrange(range)
        document.screenplay.revision += 1
        document.project.metadata.modifiedAt = Date()
        document.shots.removeAll { $0.sceneSpineID == breakdown.editSpineID }
        document.boardFrames.removeAll { $0.sceneSpineID == breakdown.editSpineID }
        document.outline = document.outline.map { beat in
            var updated = beat
            updated.linkedSceneSpineIDs.removeAll { $0 == breakdown.editSpineID }
            return updated
        }
        document.ensureSceneSpineIDs()
        document.ensureEditorialSpine()
        document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
        self.document = document

        let fallbackIndex = min(range.lowerBound, max(0, document.screenplay.elements.count - 1))
        if document.screenplay.elements.indices.contains(fallbackIndex) {
            selectElement(id: document.screenplay.elements[fallbackIndex].id)
        } else {
            selectInitialElement()
        }

        recordActivity(
            actor: .manual,
            action: "Deleted scene",
            detail: "Removed \(breakdown.editSpineID) from the script and linked views.",
            target: AIProposalTarget(sceneSpineID: breakdown.editSpineID)
        )
        autosave()
    }

    func moveSelectedSceneEarlier() {
        moveSelectedScene(direction: -1)
    }

    func moveSelectedSceneLater() {
        moveSelectedScene(direction: 1)
    }

    func generateShotListForSelectedScene() {
        guard let breakdown = selectedSceneBreakdown, document != nil else {
            return
        }

        rememberUndoState()
        document?.shots.removeAll { $0.sceneSpineID == breakdown.editSpineID }
        document?.shots.append(contentsOf: generatedShots(for: breakdown))
        document?.editorialSpine.syncEditReferences(shots: document?.shots ?? [], boardFrames: document?.boardFrames ?? [])
        recordActivity(
            actor: .manual,
            action: "Generated shot list",
            detail: "Generated shots for \(breakdown.editSpineID).",
            target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: breakdown.editSpineID)
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func bindingForShotLabel(_ shot: Shot) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.shot(id: shot.id)?.label ?? shot.label
            },
            set: { [weak self] value in
                self?.updateShot(id: shot.id, label: value)
            }
        )
    }

    func bindingForShotNotes(_ shot: Shot) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.shot(id: shot.id)?.notes ?? shot.notes
            },
            set: { [weak self] value in
                self?.updateShot(id: shot.id, notes: value)
            }
        )
    }

    func setShotSetup(_ setup: ShotSetup, for shotID: UUID) {
        guard let index = shotIndex(for: shotID) else {
            return
        }

        rememberUndoState()
        document?.shots[index].setup = setup
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setShotStatus(_ status: ShotStatus, for shotID: UUID) {
        guard let index = shotIndex(for: shotID) else {
            return
        }

        rememberUndoState()
        document?.shots[index].status = status
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func navigateToShotSource(_ shot: Shot) {
        guard let sourceID = shot.sourceRefs.first?.screenplayElementID else {
            return
        }

        selectedElementID = sourceID
        selectedObject = .screenplayElement(sourceID)
        setFilmContext(sceneSpineID: shot.sceneSpineID, shotID: shot.id, preserveBoard: true)
        scrollTargetElementID = sourceID
    }

    func setWorkflowMode(_ mode: WorkflowMode) {
        workflowMode = mode
        reconcileSelectionForCurrentWorkflow()
        if !sidebarMode.isCrossCutting && sidebarMode.workflowMode != mode {
            sidebarMode = lastSidebarModeByWorkflow[mode] ?? mode.defaultSidebarMode
        }
    }

    func showSidebarMode(_ mode: SidebarMode, workflow: WorkflowMode? = nil) {
        if let workflow {
            setWorkflowMode(workflow)
        } else if !mode.isCrossCutting {
            setWorkflowMode(mode.workflowMode)
        }

        sidebarMode = mode
    }

    func resetWorkspaceLayout() {
        focusMode = false
        navigationVisible = true
        contextAssistantVisible = true
        pageZoom = 1.0
        workflowMode = .writing
        sidebarMode = lastSidebarModeByWorkflow[.writing] ?? .navigator
    }

    private func rememberSidebarMode(_ sidebarMode: SidebarMode, for workflowMode: WorkflowMode) {
        guard !sidebarMode.isCrossCutting, sidebarMode.workflowMode == workflowMode else {
            return
        }

        lastSidebarModeByWorkflow[workflowMode] = sidebarMode
    }

    func generateBoardsForSelectedScene() {
        guard let breakdown = selectedSceneBreakdown, document != nil else {
            return
        }

        let sceneShots = shotsForSelectedScene
        guard !sceneShots.isEmpty else {
            errorMessage = "Generate a shot list first."
            return
        }

        rememberUndoState()
        document?.boardFrames.removeAll { $0.sceneSpineID == breakdown.editSpineID }
        document?.boardFrames.append(contentsOf: generatedBoardFrames(for: sceneShots, breakdown: breakdown))
        document?.editorialSpine.syncEditReferences(shots: document?.shots ?? [], boardFrames: document?.boardFrames ?? [])
        recordActivity(
            actor: .manual,
            action: "Generated boards",
            detail: "Generated board frames for \(breakdown.editSpineID).",
            target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: breakdown.editSpineID)
        )
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func bindingForBoardPrompt(_ frame: BoardFrame) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.boardFrame(id: frame.id)?.prompt ?? frame.prompt
            },
            set: { [weak self] value in
                self?.updateBoardFrame(id: frame.id, prompt: value)
            }
        )
    }

    func bindingForBoardNotes(_ frame: BoardFrame) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.boardFrame(id: frame.id)?.notes ?? frame.notes
            },
            set: { [weak self] value in
                self?.updateBoardFrame(id: frame.id, notes: value)
            }
        )
    }

    func bindingForBoardDuration(_ frame: BoardFrame) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                self?.boardFrame(id: frame.id)?.durationSeconds ?? frame.durationSeconds
            },
            set: { [weak self] value in
                self?.setBoardFrameDuration(value, for: frame.id)
            }
        )
    }

    func setBoardFrameStatus(_ status: ShotStatus, for frameID: UUID) {
        guard let index = boardFrameIndex(for: frameID) else {
            return
        }

        rememberUndoState()
        document?.boardFrames[index].status = status
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setBoardFrameDuration(_ duration: Double, for frameID: UUID) {
        guard let index = boardFrameIndex(for: frameID) else {
            return
        }

        rememberUndoState()
        document?.boardFrames[index].durationSeconds = max(0.5, min(30.0, duration))
        if var document {
            document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
            self.document = document
        }
        boardomaticPlayheadSeconds = min(boardomaticPlayheadSeconds, boardomaticTotalDuration)
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func toggleBoardomaticPlayback() {
        guard !boardFramesForSelectedScene.isEmpty else {
            return
        }

        boardomaticIsPlaying ? pauseBoardomatic() : playBoardomatic()
    }

    func playBoardomatic() {
        guard !boardFramesForSelectedScene.isEmpty else {
            return
        }

        if boardomaticPlayheadSeconds >= boardomaticTotalDuration {
            scrubBoardomatic(to: 0)
        }
        boardomaticIsPlaying = true
        lastBoardomaticTick = Date()
        selectBoardFrameForPlayhead()
    }

    func pauseBoardomatic() {
        boardomaticIsPlaying = false
        lastBoardomaticTick = nil
    }

    func advanceBoardomaticTick() {
        guard boardomaticIsPlaying else {
            return
        }

        let now = Date()
        let elapsed = lastBoardomaticTick.map { now.timeIntervalSince($0) } ?? 0
        lastBoardomaticTick = now
        scrubBoardomatic(to: boardomaticPlayheadSeconds + elapsed, keepPlaybackState: true)
    }

    func scrubBoardomatic(to seconds: Double, keepPlaybackState: Bool = false) {
        let total = boardomaticTotalDuration
        guard total > 0 else {
            boardomaticPlayheadSeconds = 0
            pauseBoardomatic()
            return
        }

        if seconds >= total {
            boardomaticPlayheadSeconds = total
            selectBoardFrameForPlayhead()
            if !keepPlaybackState {
                pauseBoardomatic()
            } else {
                boardomaticIsPlaying = false
                lastBoardomaticTick = nil
            }
            return
        }

        boardomaticPlayheadSeconds = max(0, seconds)
        selectBoardFrameForPlayhead()
    }

    func scrubBoardomaticProgress(to progress: Double) {
        pauseBoardomatic()
        scrubBoardomatic(to: max(0, min(1, progress)) * boardomaticTotalDuration)
    }

    func selectPreviousBoardFrame() {
        guard let index = activeBoardFrameIndex else {
            return
        }

        let frames = boardFramesForSelectedScene
        let previousIndex = max(0, index - 1)
        selectBoardFrame(frames[previousIndex])
        boardomaticPlayheadSeconds = boardomaticStartSeconds(forFrameAt: previousIndex)
    }

    func selectNextBoardFrame() {
        guard let index = activeBoardFrameIndex else {
            return
        }

        let frames = boardFramesForSelectedScene
        let nextIndex = min(frames.count - 1, index + 1)
        selectBoardFrame(frames[nextIndex])
        boardomaticPlayheadSeconds = boardomaticStartSeconds(forFrameAt: nextIndex)
    }

    func navigateToBoardSource(_ frame: BoardFrame) {
        guard let sourceID = frame.sourceRefs.first?.screenplayElementID else {
            return
        }

        selectedElementID = sourceID
        selectedObject = .screenplayElement(sourceID)
        setFilmContext(sceneSpineID: frame.sceneSpineID, shotID: frame.shotID, boardFrameID: frame.id)
        scrollTargetElementID = sourceID
    }

    func navigateToIssue(_ issue: FormatIssue) {
        selectElement(id: issue.elementID)
        scrollTargetElementID = issue.elementID
    }

    func navigateToFindMatch(_ match: FindMatch) {
        selectElement(id: match.elementID)
        scrollTargetElementID = match.elementID
    }

    func replaceSelectedMatch() {
        guard
            !findQuery.isEmpty,
            let selectedElementID,
            let index = elementIndex(for: selectedElementID),
            document?.screenplay.elements[index].text.range(of: findQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        else {
            return
        }

        rememberUndoState()
        document?.screenplay.elements[index].text = document?.screenplay.elements[index].text.replacingOccurrences(
            of: findQuery,
            with: replaceText,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) ?? ""
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func replaceAllMatches() {
        guard !findQuery.isEmpty, document != nil else {
            return
        }

        rememberUndoState()
        var changed = false
        for index in elements.indices {
            let original = document?.screenplay.elements[index].text ?? ""
            let replaced = original.replacingOccurrences(
                of: findQuery,
                with: replaceText,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
            if replaced != original {
                document?.screenplay.elements[index].text = replaced
                changed = true
            }
        }

        if changed {
            document?.screenplay.revision += 1
            document?.project.metadata.modifiedAt = Date()
            autosave()
        }
    }

    func renameCharacter() {
        let oldName = characterToRename.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !oldName.isEmpty, !newName.isEmpty, document != nil else {
            return
        }

        rememberUndoState()
        var changed = false
        for index in elements.indices where document?.screenplay.elements[index].type == .character {
            let current = document?.screenplay.elements[index].text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.caseInsensitiveCompare(oldName) == .orderedSame {
                document?.screenplay.elements[index].text = newName
                changed = true
            }
        }

        if changed {
            characterToRename = newName
            newCharacterName = ""
            document?.screenplay.revision += 1
            document?.project.metadata.modifiedAt = Date()
            autosave()
        }
    }

    func syncTitlePageFromProject() {
        guard document != nil else {
            return
        }

        rememberUndoState()
        document?.titlePage.title = document?.project.metadata.title ?? ""
        document?.titlePage.author = document?.project.metadata.author ?? ""
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setType(_ type: ElementType, for elementID: UUID) {
        guard let index = elementIndex(for: elementID) else {
            return
        }
        rememberUndoState()
        document?.screenplay.elements[index].type = type
        document?.screenplay.elements[index].text = normalizedText(
            for: type,
            text: document?.screenplay.elements[index].text ?? ""
        )
        assignSceneSpineIDIfNeeded(at: index)
        markRevisionIfNeeded(at: index)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    func setSelectedElementType(_ type: ElementType) {
        guard let selectedElementID else {
            return
        }

        setType(type, for: selectedElementID)
    }

    func cycleSelectedElementType(forward: Bool = true) {
        guard let selectedElementID else {
            return
        }

        cycleElementType(for: selectedElementID, forward: forward)
    }

    func cycleElementType(for elementID: UUID, forward: Bool = true) {
        guard let element = element(id: elementID) else {
            return
        }

        let types = ElementType.editorTypes
        guard let currentIndex = types.firstIndex(of: element.type) else {
            setType(.action, for: elementID)
            return
        }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % types.count
        } else {
            nextIndex = (currentIndex - 1 + types.count) % types.count
        }

        selectElement(id: elementID)
        setType(types[nextIndex], for: elementID)
    }

    func promoteSelectedElementToCharacter() {
        setSelectedElementType(.character)
    }

    func promoteSelectedElementToSceneHeading() {
        setSelectedElementType(.sceneHeading)
    }

    func insertElement(after elementID: UUID) {
        guard let index = elementIndex(for: elementID) else {
            return
        }

        rememberUndoState()
        let current = document?.screenplay.elements[index]
        var next = ScreenplayElement(type: nextElementType(after: current?.type ?? .action), text: "")
        next.revisionMark = currentRevisionMark()
        document?.screenplay.elements.insert(next, at: index + 1)
        assignSceneSpineIDIfNeeded(at: index + 1)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        selectElement(id: next.id)
        scrollTargetElementID = next.id
        autosave()
    }

    func selectAdjacentElement(from elementID: UUID, direction: Int) -> Bool {
        guard
            let index = elementIndex(for: elementID),
            let elements = document?.screenplay.elements
        else {
            return false
        }

        let nextIndex = index + direction
        guard elements.indices.contains(nextIndex) else {
            return false
        }

        selectElement(id: elements[nextIndex].id)
        scrollTargetElementID = selectedElementID
        return true
    }

    func splitElement(_ elementID: UUID, at cursorOffset: Int) {
        guard
            let index = elementIndex(for: elementID),
            let current = document?.screenplay.elements[index]
        else {
            return
        }

        let nsText = current.text as NSString
        let clampedOffset = max(0, min(cursorOffset, nsText.length))
        let before = nsText.substring(to: clampedOffset).trimmingCharacters(in: .newlines)
        let after = nsText.substring(from: clampedOffset).trimmingCharacters(in: .newlines)

        rememberUndoState()
        document?.screenplay.elements[index].text = before

        var next = ScreenplayElement(
            type: nextElementType(after: current.type),
            text: after
        )
        next.revisionMark = currentRevisionMark()
        document?.screenplay.elements.insert(next, at: index + 1)
        assignSceneSpineIDIfNeeded(at: index + 1)
        markRevisionIfNeeded(at: index)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        selectElement(id: next.id)
        scrollTargetElementID = next.id
        autosave()
    }

    func deleteSelectedElement() {
        guard
            let selectedElementID,
            let index = elementIndex(for: selectedElementID),
            elements.count > 1
        else {
            return
        }

        rememberUndoState()
        document?.screenplay.elements.remove(at: index)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()

        let fallbackIndex = min(index, elements.count - 1)
        if let fallbackID = elements.indices.contains(fallbackIndex) ? elements[fallbackIndex].id : elements.last?.id {
            selectElement(id: fallbackID)
        }
        autosave()
    }

    @discardableResult
    func mergeElementWithPrevious(_ elementID: UUID) -> Bool {
        guard
            let index = elementIndex(for: elementID),
            index > 0,
            let current = document?.screenplay.elements[index]
        else {
            return false
        }

        if current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectElement(id: elementID)
            deleteSelectedElement()
            return true
        }

        rememberUndoState()
        let previousIndex = index - 1
        let previousText = document?.screenplay.elements[previousIndex].text ?? ""
        let separator = previousText.isEmpty ? "" : " "
        document?.screenplay.elements[previousIndex].text = previousText + separator + current.text
        document?.screenplay.elements.remove(at: index)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()

        let previousID = document?.screenplay.elements[previousIndex].id
        if let previousID {
            selectElement(id: previousID)
        }
        scrollTargetElementID = previousID
        autosave()
        return true
    }

    @discardableResult
    func deleteSelectedElementIfEmpty() -> Bool {
        guard
            let selectedElement,
            selectedElement.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        deleteSelectedElement()
        return true
    }

    func deleteEmptyElements() {
        guard let document, document.screenplay.elements.count > 1 else {
            return
        }

        let nonEmptyElements = document.screenplay.elements.filter {
            $0.type == .pageBreak || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !nonEmptyElements.isEmpty, nonEmptyElements.count != document.screenplay.elements.count else {
            return
        }

        rememberUndoState()
        self.document?.screenplay.elements = nonEmptyElements
        self.document?.screenplay.revision += 1
        recordActivity(
            actor: .manual,
            action: "Deleted blank elements",
            detail: "Removed empty screenplay elements.",
            target: AIProposalTarget()
        )
        self.document?.project.metadata.modifiedAt = Date()
        if let firstID = nonEmptyElements.first?.id {
            selectElement(id: firstID)
        }
        scrollTargetElementID = selectedElementID
        autosave()
    }

    func cleanScript() {
        guard var document, document.screenplay.elements.count > 0 else {
            return
        }

        let previousSelection = selectedElementID
        let previousSelectionIndex = previousSelection.flatMap { elementIndex(for: $0) }
        rememberUndoState()
        document.screenplay.elements = document.screenplay.elements.compactMap { element in
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || element.type == .pageBreak else {
                return nil
            }

            var cleaned = element
            cleaned.text = normalizedText(for: cleaned.type, text: trimmed)
            return cleaned
        }
        document.screenplay.revision += 1
        document.project.metadata.modifiedAt = Date()
        document.ensureSceneSpineIDs()
        self.document = document
        recordActivity(
            actor: .manual,
            action: "Cleaned script",
            detail: "Removed blank elements and normalized screenplay casing.",
            target: AIProposalTarget()
        )
        if let previousSelection,
           document.screenplay.elements.contains(where: { $0.id == previousSelection }) {
            selectElement(id: previousSelection)
        } else if let previousSelectionIndex {
            let fallbackIndex = min(previousSelectionIndex, max(0, document.screenplay.elements.count - 1))
            if let fallbackID = document.screenplay.elements.indices.contains(fallbackIndex) ? document.screenplay.elements[fallbackIndex].id : document.screenplay.elements.first?.id {
                selectElement(id: fallbackID)
            }
        } else if let firstID = document.screenplay.elements.first?.id {
            selectElement(id: firstID)
        }
        scrollTargetElementID = selectedElementID
        autosave()
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }

        document = previous
            selectInitialElement()
        autosave()
    }

    private func element(id: UUID) -> ScreenplayElement? {
        document?.screenplay.elements.first { $0.id == id }
    }

    private func selectInitialElement() {
        guard let id = document?.screenplay.elements.first?.id else {
            selectedElementID = nil
            selectedObject = .none
            currentSceneSpineID = nil
            currentShotID = nil
            currentBoardFrameID = nil
            scrollTargetElementID = nil
            return
        }

        selectedElementID = id
        selectedObject = .screenplayElement(id)
        setFilmContext(sceneSpineID: sceneSpineID(containing: id), preserveShot: false, preserveBoard: false)
        scrollTargetElementID = id
    }

    private func shot(id: UUID) -> Shot? {
        document?.shots.first { $0.id == id }
    }

    private func outlineBeat(id: UUID) -> OutlineBeat? {
        document?.outline.first { $0.id == id }
    }

    private func productionEntity(id: UUID) -> ProductionEntity? {
        document?.productionContext.entities.first { $0.id == id }
    }

    private func productionNote(id: UUID) -> ProductionNote? {
        document?.productionContext.notes.first { $0.id == id }
    }

    private func editorialBeat(id: UUID) -> EditorialBeat? {
        document?.editorialSpine.sequences.flatMap(\.beats).first { $0.id == id }
    }

    private func editorialBeatIndexPath(for id: UUID) -> (sequence: Int, beat: Int)? {
        guard let sequences = document?.editorialSpine.sequences else {
            return nil
        }

        for sequenceIndex in sequences.indices {
            if let beatIndex = sequences[sequenceIndex].beats.firstIndex(where: { $0.id == id }) {
                return (sequenceIndex, beatIndex)
            }
        }

        return nil
    }

    private func updateEditorialBeat(id: UUID, notes: String) {
        guard let indexPath = editorialBeatIndexPath(for: id) else {
            return
        }

        rememberUndoState()
        document?.editorialSpine.sequences[indexPath.sequence].beats[indexPath.beat].editNotes = notes
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func shotIndex(for id: UUID) -> Int? {
        document?.shots.firstIndex { $0.id == id }
    }

    private func boardFrame(id: UUID) -> BoardFrame? {
        document?.boardFrames.first { $0.id == id }
    }

    private func boardFrameIndex(for id: UUID) -> Int? {
        document?.boardFrames.firstIndex { $0.id == id }
    }

    private var activeBoardFrameIndex: Int? {
        guard let frame = activeBoardFrame else {
            return nil
        }

        return boardFramesForSelectedScene.firstIndex { $0.id == frame.id }
    }

    private func boardomaticStartSeconds(forFrameAt frameIndex: Int) -> Double {
        let frames = boardFramesForSelectedScene
        guard frameIndex > 0, frames.indices.contains(frameIndex) else {
            return 0
        }

        return frames[..<frameIndex].reduce(0.0) { $0 + $1.durationSeconds }
    }

    private func selectBoardFrameForPlayhead() {
        let frames = boardFramesForSelectedScene
        guard !frames.isEmpty else {
            return
        }

        var cursor = 0.0
        for frame in frames {
            let end = cursor + frame.durationSeconds
            if boardomaticPlayheadSeconds < end {
                selectedObject = .boardFrame(frame.id, sceneSpineID: frame.sceneSpineID)
                setFilmContext(sceneSpineID: frame.sceneSpineID, shotID: frame.shotID, boardFrameID: frame.id)
                return
            }
            cursor = end
        }

        if let frame = frames.last {
            selectedObject = .boardFrame(frame.id, sceneSpineID: frame.sceneSpineID)
            setFilmContext(sceneSpineID: frame.sceneSpineID, shotID: frame.shotID, boardFrameID: frame.id)
        }
    }

    private func sceneSpineID(containing elementID: UUID) -> String? {
        guard let index = elementIndex(for: elementID) else {
            return nil
        }

        return elements.prefix(through: index).last { $0.type == .sceneHeading }?.spineID
    }

    private func sceneElementID(for sceneSpineID: String) -> UUID? {
        sceneBreakdowns.first { $0.editSpineID == sceneSpineID }?.elementID
    }

    private func sceneElementRange(startingAt sceneElementID: UUID) -> Range<Int>? {
        guard let startIndex = elementIndex(for: sceneElementID),
              elements[startIndex].type == .sceneHeading
        else {
            return nil
        }

        let endIndex = elements.indices.dropFirst(startIndex + 1).first { elements[$0].type == .sceneHeading } ?? elements.endIndex
        return startIndex..<endIndex
    }

    private func moveSelectedScene(direction: Int) {
        guard var document,
              let breakdown = selectedSceneBreakdown,
              let currentRange = sceneElementRange(startingAt: breakdown.elementID)
        else {
            return
        }

        let sceneStarts = document.screenplay.elements.indices.filter {
            document.screenplay.elements[$0].type == .sceneHeading
        }
        guard let currentSceneIndex = sceneStarts.firstIndex(of: currentRange.lowerBound) else {
            return
        }

        let targetSceneIndex = currentSceneIndex + direction
        guard sceneStarts.indices.contains(targetSceneIndex) else {
            return
        }
        let targetStart = sceneStarts[targetSceneIndex]
        let targetEnd = document.screenplay.elements.indices.dropFirst(targetStart + 1).first {
            document.screenplay.elements[$0].type == .sceneHeading
        } ?? document.screenplay.elements.endIndex

        rememberUndoState()
        let movingScene = Array(document.screenplay.elements[currentRange])
        document.screenplay.elements.removeSubrange(currentRange)

        let insertionIndex: Int
        if direction < 0 {
            insertionIndex = targetStart
        } else {
            insertionIndex = targetEnd - movingScene.count
        }

        document.screenplay.elements.insert(contentsOf: movingScene, at: insertionIndex)
        document.screenplay.revision += 1
        document.project.metadata.modifiedAt = Date()
        document.ensureEditorialSpine()
        document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
        self.document = document
        navigateToSceneSpineID(breakdown.editSpineID)
        recordActivity(
            actor: .manual,
            action: "Reordered scene",
            detail: "Moved \(breakdown.editSpineID) \(direction < 0 ? "earlier" : "later") in the screenplay.",
            target: AIProposalTarget(sceneSpineID: breakdown.editSpineID)
        )
        autosave()
    }

    private func setFilmContext(
        sceneSpineID: String?,
        shotID: UUID? = nil,
        boardFrameID: UUID? = nil,
        preserveShot: Bool = true,
        preserveBoard: Bool = true
    ) {
        let previousSceneSpineID = currentSceneSpineID
        if let sceneSpineID {
            currentSceneSpineID = sceneSpineID
        }
        if previousSceneSpineID != nil, previousSceneSpineID != currentSceneSpineID {
            boardomaticPlayheadSeconds = 0
            pauseBoardomatic()
        }

        if let shotID {
            currentShotID = shotID
        } else if !preserveShot {
            currentShotID = nil
        } else if let currentShotID,
                  let currentSceneSpineID,
                  shots.first(where: { $0.id == currentShotID && $0.sceneSpineID == currentSceneSpineID }) == nil {
            self.currentShotID = nil
        }

        if let boardFrameID {
            currentBoardFrameID = boardFrameID
        } else if !preserveBoard {
            currentBoardFrameID = nil
        } else if let currentBoardFrameID,
                  let currentSceneSpineID,
                  boardFrames.first(where: { $0.id == currentBoardFrameID && $0.sceneSpineID == currentSceneSpineID }) == nil {
            self.currentBoardFrameID = nil
        }
    }

    private func reconcileSelectionForCurrentWorkflow() {
        guard let currentSceneSpineID else {
            if let selectedElementID {
                setFilmContext(sceneSpineID: sceneSpineID(containing: selectedElementID))
            }
            return
        }

        switch workflowMode {
        case .outline:
            if let beat = outlineBeats.first(where: { $0.linkedSceneSpineIDs.contains(currentSceneSpineID) }) {
                selectedObject = .outlineBeat(beat.id)
            } else if let sceneID = sceneElementID(for: currentSceneSpineID) {
                selectedObject = .scene(sceneID, sceneSpineID: currentSceneSpineID)
            }
        case .writing, .production:
            if let sceneID = sceneElementID(for: currentSceneSpineID) {
                selectedElementID = sceneID
                selectedObject = .scene(sceneID, sceneSpineID: currentSceneSpineID)
                scrollTargetElementID = sceneID
            }
        case .directing:
            if let currentShotID,
               shots.contains(where: { $0.id == currentShotID }) {
                selectedObject = .shot(currentShotID, sceneSpineID: currentSceneSpineID)
            } else if let shot = shotsForSelectedScene.first {
                currentShotID = shot.id
                selectedObject = .shot(shot.id, sceneSpineID: shot.sceneSpineID)
            } else if let sceneID = sceneElementID(for: currentSceneSpineID) {
                selectedObject = .scene(sceneID, sceneSpineID: currentSceneSpineID)
            }
        case .boards:
            if let currentBoardFrameID,
               boardFrames.contains(where: { $0.id == currentBoardFrameID }) {
                selectedObject = .boardFrame(currentBoardFrameID, sceneSpineID: currentSceneSpineID)
            } else if let frame = selectedBoardFrame {
                currentBoardFrameID = frame.id
                currentShotID = frame.shotID
                selectedObject = .boardFrame(frame.id, sceneSpineID: frame.sceneSpineID)
            } else if let currentShotID,
                      shots.contains(where: { $0.id == currentShotID }) {
                selectedObject = .shot(currentShotID, sceneSpineID: currentSceneSpineID)
            } else if let sceneID = sceneElementID(for: currentSceneSpineID) {
                selectedObject = .scene(sceneID, sceneSpineID: currentSceneSpineID)
            }
        case .edit:
            if let currentBoardFrameID,
               boardFrames.contains(where: { $0.id == currentBoardFrameID }) {
                selectedObject = .boardFrame(currentBoardFrameID, sceneSpineID: currentSceneSpineID)
            } else if let beat = editorialBeats.first(where: { $0.sceneSpineID == currentSceneSpineID }) {
                selectedObject = .editorialBeat(beat.id, sceneSpineID: beat.sceneSpineID)
            } else if let sceneID = sceneElementID(for: currentSceneSpineID) {
                selectedObject = .scene(sceneID, sceneSpineID: currentSceneSpineID)
            }
        }
    }

    private func productionNoteIndex(for id: UUID) -> Int? {
        document?.productionContext.notes.firstIndex { $0.id == id }
    }

    private func navigateToSelectionScene() {
        guard let sceneSpineID = selectedObject.sceneSpineID,
              let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID })
        else {
            return
        }

        navigateToSceneBreakdown(breakdown)
    }

    private func navigateToSelectedObjectSource() {
        switch selectedObject.kind {
        case .scene, .screenplayElement:
            guard let id = selectedObject.id else {
                return
            }
            selectElement(id: id)
            scrollTargetElementID = id
        case .outlineBeat:
            guard let id = selectedObject.id,
                  let beat = outlineBeat(id: id),
                  let sceneSpineID = beat.linkedSceneSpineIDs.first
            else {
                return
            }
            navigateToSceneSpineID(sceneSpineID)
        case .shot:
            guard let id = selectedObject.id, let shot = shot(id: id) else {
                return
            }
            navigateToShotSource(shot)
        case .boardFrame:
            guard let id = selectedObject.id, let frame = boardFrame(id: id) else {
                return
            }
            navigateToBoardSource(frame)
        case .productionEntity:
            guard let id = selectedObject.id,
                  let entity = productionEntity(id: id),
                  let sourceID = entity.sourceElementIDs.first
            else {
                return
            }
            selectElement(id: sourceID)
            scrollTargetElementID = sourceID
        case .productionNote:
            guard let id = selectedObject.id,
                  let note = productionNote(id: id),
                  let sourceID = note.sourceElementIDs.first
            else {
                return
            }
            selectElement(id: sourceID)
            scrollTargetElementID = sourceID
        case .editorialBeat:
            navigateToSelectionScene()
        case .none:
            return
        }
    }

    private func linkSelectionToCurrentScene() {
        guard let id = selectedObject.id,
              selectedObject.kind == .outlineBeat,
              let beat = outlineBeat(id: id)
        else {
            return
        }

        linkSelectedScene(to: beat)
    }

    private func setSelectedContextStatus(_ status: ProductionEntityStatus) {
        guard let id = selectedObject.id else {
            return
        }

        switch selectedObject.kind {
        case .productionEntity:
            setProductionEntityStatus(id, status: status)
        case .productionNote:
            setProductionNoteStatus(id, status: status)
        default:
            return
        }
    }

    private func selectionContext(for object: ObjectSelection) -> SelectionContext? {
        guard object.kind != .none else {
            return nil
        }

        switch object.kind {
        case .screenplayElement, .scene:
            guard let id = object.id, let element = element(id: id) else {
                return nil
            }
            let trimmedText = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedText.isEmpty ? element.type.displayName : trimmedText
            let sceneSpineID = object.sceneSpineID
                ?? (element.type == .sceneHeading ? element.spineID : selectedSceneBreakdown?.editSpineID)
            let kind: SelectionKind = object.kind == .scene || element.type == .sceneHeading ? .scene : .screenplayElement
            return SelectionContext(
                kind: kind,
                id: id,
                sceneSpineID: sceneSpineID,
                title: title,
                detail: "\(element.type.displayName) | \(selectedElementPosition)",
                workflowMode: workflowMode
            )
        case .outlineBeat:
            guard let id = object.id, let beat = outlineBeat(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .outlineBeat,
                id: id,
                sceneSpineID: beat.linkedSceneSpineIDs.first,
                title: beat.name,
                detail: "\(beat.template) | beat \(beat.order)",
                workflowMode: workflowMode
            )
        case .shot:
            guard let id = object.id, let shot = shot(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .shot,
                id: id,
                sceneSpineID: shot.sceneSpineID,
                title: shot.label,
                detail: "\(shot.setup.displayName) | \(shot.status.displayName)",
                workflowMode: workflowMode
            )
        case .boardFrame:
            guard let id = object.id, let frame = boardFrame(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .boardFrame,
                id: id,
                sceneSpineID: frame.sceneSpineID,
                title: frame.label,
                detail: "Frame \(frame.frameNumber) | \(frame.status.displayName)",
                workflowMode: workflowMode
            )
        case .productionEntity:
            guard let id = object.id, let entity = productionEntity(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .productionEntity,
                id: id,
                sceneSpineID: nil,
                title: entity.name,
                detail: "\(entity.kind.displayName) | \(entity.status.displayName)",
                workflowMode: workflowMode
            )
        case .productionNote:
            guard let id = object.id, let note = productionNote(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .productionNote,
                id: id,
                sceneSpineID: nil,
                title: note.title,
                detail: note.status.displayName,
                workflowMode: workflowMode
            )
        case .editorialBeat:
            guard let id = object.id, let beat = editorialBeat(id: id) else {
                return nil
            }
            return SelectionContext(
                kind: .editorialBeat,
                id: id,
                sceneSpineID: beat.sceneSpineID,
                title: beat.title,
                detail: "\(beat.markerCategory.displayName) | \(beat.status.displayName)",
                workflowMode: workflowMode
            )
        case .none:
            return nil
        }
    }

    private func inspectorActions(for selection: SelectionContext) -> [InspectorAction] {
        switch selection.kind {
        case .scene:
            return [.jumpToSource, .changeElementType, .generateShots, .generateBoards, .refreshContext]
        case .screenplayElement:
            return [.jumpToSource, .changeElementType, .refreshContext]
        case .outlineBeat:
            return [.linkOutlineBeat, .jumpToSource]
        case .shot:
            return [.jumpToSource, .generateBoards]
        case .boardFrame:
            return [.jumpToSource]
        case .productionEntity, .productionNote:
            return [.jumpToSource, .acceptContext, .ignoreContext, .refreshContext]
        case .editorialBeat:
            return [.jumpToSource]
        case .none:
            return []
        }
    }

    private func inspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        switch selection.kind {
        case .scene:
            return sceneInspectorDetails(for: selection)
        case .screenplayElement:
            return screenplayElementInspectorDetails(for: selection)
        case .outlineBeat:
            return outlineBeatInspectorDetails(for: selection)
        case .shot:
            return shotInspectorDetails(for: selection)
        case .boardFrame:
            return boardFrameInspectorDetails(for: selection)
        case .productionEntity:
            return productionEntityInspectorDetails(for: selection)
        case .productionNote:
            return productionNoteInspectorDetails(for: selection)
        case .editorialBeat:
            return editorialBeatInspectorDetails(for: selection)
        case .none:
            return []
        }
    }

    private func sceneInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let sceneSpineID = selection.sceneSpineID,
              let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID })
        else {
            return []
        }

        let linkedBeats = outlineBeats
            .filter { $0.linkedSceneSpineIDs.contains(sceneSpineID) }
            .map(\.name)
        return [
            InspectorDetail(label: "Scene ID", value: breakdown.editSpineID),
            InspectorDetail(label: "Page", value: breakdown.pageNumber.map(String.init) ?? "-"),
            InspectorDetail(label: "Cast", value: joinedInspectorValue(breakdown.characters)),
            InspectorDetail(label: "Location", value: joinedInspectorValue(breakdown.locations)),
            InspectorDetail(label: "Props", value: joinedInspectorValue(breakdown.props)),
            InspectorDetail(label: "VFX", value: joinedInspectorValue(breakdown.visualEffects)),
            InspectorDetail(label: "Shots", value: "\(shots.filter { $0.sceneSpineID == sceneSpineID }.count)"),
            InspectorDetail(label: "Boards", value: "\(boardFrames.filter { $0.sceneSpineID == sceneSpineID }.count)"),
            InspectorDetail(label: "Open Notes", value: "\(scriptNotes.filter { $0.sceneSpineID == sceneSpineID && $0.status == .open }.count)"),
            InspectorDetail(label: "Outline", value: joinedInspectorValue(linkedBeats))
        ]
    }

    private func screenplayElementInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let element = element(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Type", value: element.type.displayName),
            InspectorDetail(label: "Scene ID", value: selection.sceneSpineID ?? "-"),
            InspectorDetail(label: "Element", value: selectedElementPosition),
            InspectorDetail(label: "Revision", value: element.revisionMark?.label ?? "-"),
            InspectorDetail(label: "Open Notes", value: "\(scriptNotes.filter { $0.screenplayElementID == id && $0.status == .open }.count)"),
            InspectorDetail(label: "Source IDs", value: "\(element.externalIDs.count)")
        ]
    }

    private func outlineBeatInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let beat = outlineBeat(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Template", value: beat.template),
            InspectorDetail(label: "Order", value: "\(beat.order)"),
            InspectorDetail(label: "Linked Scenes", value: joinedInspectorValue(beat.linkedSceneSpineIDs)),
            InspectorDetail(label: "Notes", value: beat.notes.isEmpty ? "-" : beat.notes)
        ]
    }

    private func shotInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let shot = shot(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Shot ID", value: shot.id.uuidString),
            InspectorDetail(label: "Scene ID", value: shot.sceneSpineID),
            InspectorDetail(label: "Setup", value: shot.setup.displayName),
            InspectorDetail(label: "Status", value: shot.status.displayName),
            InspectorDetail(label: "Source Lines", value: "\(shot.sourceRefs.count)"),
            InspectorDetail(label: "Board Frames", value: "\(boardFrames.filter { $0.shotID == shot.id }.count)")
        ]
    }

    private func boardFrameInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let frame = boardFrame(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Frame ID", value: frame.id.uuidString),
            InspectorDetail(label: "Shot ID", value: frame.shotID.uuidString),
            InspectorDetail(label: "Scene ID", value: frame.sceneSpineID),
            InspectorDetail(label: "Frame", value: "\(frame.frameNumber)"),
            InspectorDetail(label: "Status", value: frame.status.displayName),
            InspectorDetail(label: "Source Lines", value: "\(frame.sourceRefs.count)")
        ]
    }

    private func productionEntityInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let entity = productionEntity(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Kind", value: entity.kind.displayName),
            InspectorDetail(label: "Status", value: entity.status.displayName),
            InspectorDetail(label: "Sources", value: "\(entity.sourceElementIDs.count)"),
            InspectorDetail(label: "Notes", value: entity.notes.isEmpty ? "-" : entity.notes)
        ]
    }

    private func productionNoteInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let note = productionNote(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Status", value: note.status.displayName),
            InspectorDetail(label: "Sources", value: "\(note.sourceElementIDs.count)"),
            InspectorDetail(label: "Body", value: note.body)
        ]
    }

    private func editorialBeatInspectorDetails(for selection: SelectionContext) -> [InspectorDetail] {
        guard let id = selection.id, let beat = editorialBeat(id: id) else {
            return []
        }

        return [
            InspectorDetail(label: "Scene ID", value: beat.sceneSpineID),
            InspectorDetail(label: "Marker", value: beat.markerCategory.displayName),
            InspectorDetail(label: "Status", value: beat.status.displayName),
            InspectorDetail(label: "Sources", value: "\(beat.sourceElementIDs.count)"),
            InspectorDetail(label: "Shots", value: "\(beat.shotIDs.count)"),
            InspectorDetail(label: "Boards", value: "\(beat.boardFrameIDs.count)"),
            InspectorDetail(label: "Edit Clips", value: "\(beat.editClips.count)"),
            InspectorDetail(label: "Duration", value: String(format: "%.1fs", beat.editDurationSeconds))
        ]
    }

    private func joinedInspectorValue(_ values: [String]) -> String {
        values.isEmpty ? "-" : values.prefix(6).joined(separator: ", ")
    }

    private func assignSceneSpineIDIfNeeded(at index: Int) {
        guard
            let elements = document?.screenplay.elements,
            elements.indices.contains(index),
            let element = document?.screenplay.elements[index],
            element.type == .sceneHeading,
            (element.spineID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        else {
            return
        }

        document?.ensureSceneSpineIDs()
    }

    private func titlePageValue(_ field: TitlePageField) -> String {
        guard let titlePage = document?.titlePage else {
            return ""
        }

        switch field {
        case .title:
            return titlePage.title
        case .subtitle:
            return titlePage.subtitle
        case .author:
            return titlePage.author
        case .contact:
            return titlePage.contact
        case .draftDate:
            return titlePage.draftDate
        }
    }

    private func updateTitlePage(_ field: TitlePageField, value: String) {
        guard document != nil else {
            return
        }

        rememberUndoState()
        switch field {
        case .title:
            document?.titlePage.title = value
            document?.project.metadata.title = value
            document?.screenplay.metadata.title = value
        case .subtitle:
            document?.titlePage.subtitle = value
            document?.screenplay.metadata.episodeTitle = value.isEmpty ? nil : value
        case .author:
            document?.titlePage.author = value
            document?.project.metadata.author = value
        case .contact:
            document?.titlePage.contact = value
        case .draftDate:
            document?.titlePage.draftDate = value
        }

        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func updateElement(id: UUID, text: String) {
        guard let index = elementIndex(for: id) else {
            return
        }
        rememberUndoState()
        let currentType = document?.screenplay.elements[index].type ?? .action
        let detectedType = automaticElementType(for: text, currentType: currentType)
        document?.screenplay.elements[index].type = detectedType
        document?.screenplay.elements[index].text = normalizedText(for: detectedType, text: text)
        assignSceneSpineIDIfNeeded(at: index)
        markRevisionIfNeeded(at: index)
        document?.screenplay.revision += 1
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func updateShot(id: UUID, label: String? = nil, notes: String? = nil) {
        guard let index = shotIndex(for: id) else {
            return
        }

        rememberUndoState()
        if let label {
            document?.shots[index].label = label
        }
        if let notes {
            document?.shots[index].notes = notes
        }
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func updateOutlineBeat(id: UUID, notes: String) {
        guard let index = document?.outline.firstIndex(where: { $0.id == id }) else {
            return
        }

        rememberUndoState()
        document?.outline[index].notes = notes
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func updateBoardFrame(id: UUID, prompt: String? = nil, notes: String? = nil) {
        guard let index = boardFrameIndex(for: id) else {
            return
        }

        rememberUndoState()
        if let prompt {
            document?.boardFrames[index].prompt = prompt
        }
        if let notes {
            document?.boardFrames[index].notes = notes
        }
        document?.project.metadata.modifiedAt = Date()
        autosave()
    }

    private func recordActivity(actor: ActivityActor, action: String, detail: String, target: AIProposalTarget) {
        document?.activity.insert(ActivityEvent(actor: actor, action: action, detail: detail, target: target), at: 0)
        if let count = document?.activity.count, count > 200 {
            document?.activity.removeLast(count - 200)
        }
    }

    private func markRevisionIfNeeded(at index: Int) {
        guard document?.screenplay.revisionSettings.modeEnabled == true else {
            return
        }

        document?.screenplay.elements[index].revisionMark = currentRevisionMark()
    }

    private func currentRevisionMark() -> RevisionMark? {
        guard document?.screenplay.revisionSettings.modeEnabled == true else {
            return nil
        }

        let settings = document?.screenplay.revisionSettings ?? RevisionSettings()
        return RevisionMark(
            label: settings.label.isEmpty ? settings.color.rawValue.capitalized : settings.label,
            color: settings.color
        )
    }

    private func rememberUndoState() {
        guard let document else {
            return
        }

        if undoStack.last != document {
            undoStack.append(document)
        }

        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
    }

    private func elementIndex(for id: UUID) -> Int? {
        document?.screenplay.elements.firstIndex { $0.id == id }
    }

    private func sceneNumber(through targetIndex: Int) -> Int {
        elements.prefix(through: targetIndex).filter { $0.type == .sceneHeading }.count
    }

    private func nextElementType(after type: ElementType) -> ElementType {
        switch type {
        case .sceneHeading:
            return .action
        case .character, .parenthetical:
            return .dialogue
        case .dialogue:
            return .action
        case .transition:
            return .sceneHeading
        default:
            return .action
        }
    }

    private func automaticElementType(for text: String, currentType: ElementType) -> ElementType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = trimmed.uppercased()

        if currentType == .action || currentType == .general {
            if uppercase.hasPrefix("INT.") || uppercase.hasPrefix("EXT.") || uppercase.hasPrefix("INT/EXT.") || uppercase.hasPrefix("I/E.") {
                return .sceneHeading
            }
        }

        if currentType == .action, uppercase.hasSuffix(" TO:") || uppercase == "CUT TO:" || uppercase == "FADE OUT:" || uppercase == "FADE IN:" {
            return .transition
        }

        return currentType
    }

    private func hasPreviousDialogueCue(before index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        let previous = elements[index - 1].type
        return previous == .character || previous == .parenthetical
    }

    private func hasPreviousCharacterCue(before index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        let previous = elements[index - 1].type
        return previous == .character || previous == .parenthetical
    }

    private func hasDialogueAfterCharacter(at index: Int) -> Bool {
        guard index + 1 < elements.count else {
            return false
        }

        let next = elements[index + 1].type
        return next == .dialogue || next == .parenthetical
    }

    private func normalizedText(for type: ElementType, text: String) -> String {
        switch type {
        case .sceneHeading, .character, .transition, .shot:
            return text.uppercased()
        default:
            return text
        }
    }

    private func saveDocument(to url: URL, reportStatus: Bool = true) {
        guard var document else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            document.project.metadata.modifiedAt = Date()
            let nonEmptyElements = document.screenplay.elements.filter {
                $0.type == .pageBreak || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !nonEmptyElements.isEmpty {
                document.screenplay.elements = nonEmptyElements
            }
            document.ensureSceneSpineIDs()
            document.ensureEditorialSpine()
            document.editorialSpine.syncEditReferences(shots: document.shots, boardFrames: document.boardFrames)
            self.document = document
            let data = try JSONEncoder.openScreenplayEncoder().encode(document)
            try data.write(to: url, options: .atomic)
            saveURL = url
            sourceURL = url
            recordRecentDocument(url)
            if reportStatus {
                errorMessage = "Saved \(url.lastPathComponent)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportPDF(to url: URL) {
        guard let document else {
            return
        }

        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &pageRect, nil) else {
            errorMessage = "Could not create PDF."
            return
        }

        drawTitlePage(document.titlePage, in: context, pageRect: pageRect)
        drawScriptPages(document.screenplay.elements, in: context, pageRect: pageRect)
        context.closePDF()
        errorMessage = "Exported \(url.lastPathComponent)"
    }

    private func exportReport(to url: URL, kind: ReportKind) {
        do {
            try reportText(for: kind).write(to: url, atomically: true, encoding: .utf8)
            recordActivity(
                actor: .manual,
                action: "Exported report",
                detail: "\(kind.displayName) -> \(url.lastPathComponent)",
                target: AIProposalTarget()
            )
            autosave()
            errorMessage = "Exported \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportProductionFile(to url: URL, kind: ProductionExportKind) {
        let text: String
        switch kind {
        case .selectedScenePacket:
            text = selectedSceneProductionPacket()
        case .sceneBreakdownCSV:
            text = sceneBreakdownCSV()
        case .shotListCSV:
            text = shotListCSV()
        case .boardFramesCSV:
            text = boardFramesCSV()
        case .editGuideCSV:
            text = editGuideCSV()
        case .editTimelineCSV:
            text = editTimelineCSV()
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            recordActivity(
                actor: .manual,
                action: "Exported production file",
                detail: "\(kind.displayName) -> \(url.lastPathComponent)",
                target: AIProposalTarget(sceneSpineID: selectedSceneBreakdown?.editSpineID)
            )
            autosave()
            errorMessage = "Exported \(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectedSceneProductionPacket() -> String {
        guard let breakdown = selectedSceneBreakdown else {
            return "No scene selected."
        }

        let sceneShots = shotsForSelectedScene
        let sceneBoards = boardFramesForSelectedScene
        var lines: [String] = [
            "\(title) - Production Packet",
            "Scene: \(breakdown.editSpineID)",
            "Heading: \(breakdown.heading)",
            "Page: \(breakdown.pageNumber.map(String.init) ?? "Unknown")",
            "",
            "Breakdown",
            "  Cast: \(breakdown.characters.joinedOrNone())",
            "  Location: \(breakdown.locations.joinedOrNone())",
            "  Props: \(breakdown.props.joinedOrNone())",
            "  VFX: \(breakdown.visualEffects.joinedOrNone())",
            "  Notes: \(breakdown.notes.joinedOrNone())",
            "  Action beats: \(breakdown.actionBeatCount)",
            "  Revisions: \(breakdown.revisionCount)",
            ""
        ]

        lines.append("Shots")
        if sceneShots.isEmpty {
            lines.append("  No shots generated.")
        } else {
            for shot in sceneShots {
                lines.append("  \(shot.label)")
                lines.append("    Setup: \(shot.setup.displayName)")
                lines.append("    Status: \(shot.status.displayName)")
                lines.append("    Source refs: \(shot.sourceRefs.map { $0.screenplayElementID.uuidString }.joined(separator: ", "))")
                lines.append("    Notes: \(shot.notes)")
            }
        }

        lines.append("")
        lines.append("Boards")
        if sceneBoards.isEmpty {
            lines.append("  No board frames generated.")
        } else {
            for frame in sceneBoards {
                lines.append("  \(frame.label)")
                lines.append("    Status: \(frame.status.displayName)")
                lines.append("    Shot ID: \(frame.shotID.uuidString)")
                lines.append("    Prompt: \(frame.prompt)")
                lines.append("    Notes: \(frame.notes)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func sceneBreakdownCSV() -> String {
        var rows = [["scene_spine_id", "scene_number", "heading", "page", "elements", "action_beats", "revisions", "cast", "locations", "props", "vfx", "notes", "source_element_id"]]
        for breakdown in sceneBreakdowns {
            let page = breakdown.pageNumber.map(String.init) ?? ""
            rows.append([
                breakdown.editSpineID,
                String(breakdown.number),
                breakdown.heading,
                page,
                String(breakdown.elementCount),
                String(breakdown.actionBeatCount),
                String(breakdown.revisionCount),
                breakdown.characters.joined(separator: "; "),
                breakdown.locations.joined(separator: "; "),
                breakdown.props.joined(separator: "; "),
                breakdown.visualEffects.joined(separator: "; "),
                breakdown.notes.joined(separator: "; "),
                breakdown.elementID.uuidString
            ])
        }
        return csv(rows)
    }

    private func shotListCSV() -> String {
        var rows = [["scene_spine_id", "shot_number", "shot_id", "label", "setup", "status", "notes", "source_element_ids"]]
        rows.append(contentsOf: shots.sorted { left, right in
            if left.sceneSpineID == right.sceneSpineID {
                return left.shotNumber < right.shotNumber
            }
            return left.sceneSpineID < right.sceneSpineID
        }.map { shot in
            [
                shot.sceneSpineID,
                String(shot.shotNumber),
                shot.id.uuidString,
                shot.label,
                shot.setup.rawValue,
                shot.status.rawValue,
                shot.notes,
                shot.sourceRefs.map { $0.screenplayElementID.uuidString }.joined(separator: "; ")
            ]
        })
        return csv(rows)
    }

    private func boardFramesCSV() -> String {
        var rows = [["scene_spine_id", "frame_number", "board_frame_id", "shot_id", "label", "status", "prompt", "notes", "source_element_ids"]]
        rows.append(contentsOf: boardFrames.sorted { left, right in
            if left.sceneSpineID == right.sceneSpineID {
                return left.frameNumber < right.frameNumber
            }
            return left.sceneSpineID < right.sceneSpineID
        }.map { frame in
            [
                frame.sceneSpineID,
                String(frame.frameNumber),
                frame.id.uuidString,
                frame.shotID.uuidString,
                frame.label,
                frame.status.rawValue,
                frame.prompt,
                frame.notes,
                frame.sourceRefs.map { $0.screenplayElementID.uuidString }.joined(separator: "; ")
            ]
        })
        return csv(rows)
    }

    private func editGuideCSV() -> String {
        let beats = editorialBeats.sorted { left, right in
            if left.order == right.order {
                return left.sceneSpineID < right.sceneSpineID
            }
            return left.order < right.order
        }
        var rows = [[
            "edit_order",
            "edit_marker_id",
            "scene_spine_id",
            "title",
            "status",
            "marker_category",
            "source_element_ids",
            "shot_ids",
            "board_frame_ids",
            "edit_clip_ids",
            "timeline_start_seconds",
            "timeline_duration_seconds",
            "edit_notes"
        ]]
        rows.append(contentsOf: beats.map { beat in
            let clips = beat.editClips.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
            return [
                String(beat.order),
                beat.id.uuidString,
                beat.sceneSpineID,
                beat.title,
                beat.status.rawValue,
                beat.markerCategory.rawValue,
                beat.sourceElementIDs.map(\.uuidString).joined(separator: "; "),
                beat.shotIDs.map(\.uuidString).joined(separator: "; "),
                beat.boardFrameIDs.map(\.uuidString).joined(separator: "; "),
                clips.map(\.id.uuidString).joined(separator: "; "),
                clips.first.map { String(format: "%.1f", $0.timelineStartSeconds) } ?? "",
                String(format: "%.1f", beat.editDurationSeconds),
                beat.editNotes
            ]
        })
        return csv(rows)
    }

    private func editTimelineCSV() -> String {
        let clips = editorialBeats
            .flatMap { beat in
                beat.editClips.map { clip in
                    (beat: beat, clip: clip)
                }
            }
            .sorted { $0.clip.timelineStartSeconds < $1.clip.timelineStartSeconds }

        var rows = [[
            "sequence_name",
            "edit_order",
            "clip_id",
            "clip_label",
            "scene_spine_id",
            "shot_id",
            "board_frame_id",
            "source_kind",
            "status",
            "timeline_start_seconds",
            "timeline_end_seconds",
            "timeline_duration_seconds",
            "timeline_start_timecode_24",
            "timeline_end_timecode_24",
            "source_start_seconds",
            "source_element_ids",
            "edit_marker_id",
            "edit_marker_title",
            "notes"
        ]]

        rows.append(contentsOf: clips.map { item in
            let clip = item.clip
            let endSeconds = clip.timelineStartSeconds + clip.timelineDurationSeconds
            return [
                "Main Sequence",
                String(item.beat.order),
                clip.id.uuidString,
                clip.label,
                clip.sceneSpineID,
                clip.shotID?.uuidString ?? "",
                clip.boardFrameID?.uuidString ?? "",
                clip.sourceKind.rawValue,
                clip.status.rawValue,
                String(format: "%.3f", clip.timelineStartSeconds),
                String(format: "%.3f", endSeconds),
                String(format: "%.3f", clip.timelineDurationSeconds),
                timecode(seconds: clip.timelineStartSeconds, frameRate: 24),
                timecode(seconds: endSeconds, frameRate: 24),
                String(format: "%.3f", clip.sourceStartSeconds),
                clip.sourceElementIDs.map(\.uuidString).joined(separator: "; "),
                item.beat.id.uuidString,
                item.beat.title,
                clip.notes
            ]
        })

        return csv(rows)
    }

    private func timecode(seconds: Double, frameRate: Int) -> String {
        let totalFrames = max(0, Int((seconds * Double(frameRate)).rounded()))
        let frames = totalFrames % frameRate
        let totalSeconds = totalFrames / frameRate
        let secondsPart = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secondsPart, frames)
    }

    private func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(csvField).joined(separator: ",")
        }
        .joined(separator: "\n") + "\n"
    }

    private func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func reportText(for kind: ReportKind) -> String {
        guard document != nil else {
            return "No screenplay is open."
        }

        switch kind {
        case .scene:
            return sceneReport()
        case .character:
            return characterReport()
        case .location:
            return locationReport()
        case .revision:
            return revisionReport()
        case .productionContext:
            return productionContextReport()
        }
    }

    private func reportHeader(_ name: String) -> [String] {
        [
            "\(title) - \(name)",
            "Generated \(Date().formatted(date: .abbreviated, time: .shortened))",
            ""
        ]
    }

    private func sceneReport() -> String {
        var lines = reportHeader("Scene Report")
        let sceneIndexes = elements.indices.filter { elements[$0].type == .sceneHeading }

        if sceneIndexes.isEmpty {
            lines.append("No scenes found.")
            return lines.joined(separator: "\n")
        }

        for (sceneOffset, startIndex) in sceneIndexes.enumerated() {
            let endIndex = sceneIndexes.dropFirst(sceneOffset + 1).first ?? elements.count
            let sceneElements = Array(elements[startIndex..<endIndex])
            let heading = elements[startIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = pageNumber(for: elements[startIndex].id).map { "Page \($0)" } ?? "Page unknown"
            let characters = Set(sceneElements.filter { $0.type == .character }.map(\.text)).sorted()
            let revisionCount = sceneElements.filter { $0.revisionMark != nil }.count
            let actionBeats = sceneElements.filter { $0.type == .action }.count

            lines.append("Scene \(sceneOffset + 1): \(heading.isEmpty ? "Untitled Scene" : heading)")
            lines.append("  \(page)")
            lines.append("  Elements: \(sceneElements.count)")
            lines.append("  Action beats: \(actionBeats)")
            lines.append("  Revisions: \(revisionCount)")
            lines.append("  Characters: \(characters.isEmpty ? "None" : characters.joined(separator: ", "))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func characterReport() -> String {
        var lines = reportHeader("Character Report")
        let context = entitiesForReport(kind: .character)
        let names = context.entities.isEmpty ? characterNames : context.entities.map(\.name).sorted()

        lines.append("Source: \(context.label)")
        lines.append("")

        if names.isEmpty {
            lines.append("No characters found.")
            return lines.joined(separator: "\n")
        }

        for name in names {
            let cueIDs = elements.filter { $0.type == .character && $0.text.caseInsensitiveCompare(name) == .orderedSame }.map(\.id)
            let dialogueCount = elements.filter { $0.type == .dialogue && previousCharacterName(before: $0.id)?.caseInsensitiveCompare(name) == .orderedSame }.count
            let sceneNumbers = sceneNumbers(containing: cueIDs)
            let status = context.entities.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.status.displayName ?? "Script-derived"

            lines.append(name)
            lines.append("  Status: \(status)")
            lines.append("  Cue count: \(cueIDs.count)")
            lines.append("  Dialogue lines: \(dialogueCount)")
            lines.append("  Scenes: \(sceneNumbers.isEmpty ? "None" : sceneNumbers.map(String.init).joined(separator: ", "))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func locationReport() -> String {
        var lines = reportHeader("Location Report")
        let context = entitiesForReport(kind: .location)
        let scriptLocations = Dictionary(grouping: elements.filter { $0.type == .sceneHeading }) {
            locationName(from: $0.text)
        }
            .filter { !$0.key.isEmpty }
        let names = context.entities.isEmpty ? scriptLocations.keys.sorted() : context.entities.map(\.name).sorted()

        lines.append("Source: \(context.label)")
        lines.append("")

        if names.isEmpty {
            lines.append("No locations found.")
            return lines.joined(separator: "\n")
        }

        for name in names {
            let matchingHeadings = scriptLocations.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? []
            let pages = Set(matchingHeadings.compactMap { pageNumber(for: $0.id) }).sorted()
            let status = context.entities.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.status.displayName ?? "Script-derived"

            lines.append(name)
            lines.append("  Status: \(status)")
            lines.append("  Scene count: \(matchingHeadings.count)")
            lines.append("  Pages: \(pages.isEmpty ? "Unknown" : pages.map(String.init).joined(separator: ", "))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func revisionReport() -> String {
        var lines = reportHeader("Revision Report")
        lines.append("Revision mode: \(revisionStatusText)")
        lines.append("Marked lines: \(revisionMarkCount)")
        lines.append("")

        let revised = elements.filter { $0.revisionMark != nil }
        if revised.isEmpty {
            lines.append("No revision marks in this draft.")
            return lines.joined(separator: "\n")
        }

        for element in revised {
            let mark = element.revisionMark
            let page = pageNumber(for: element.id).map { "Page \($0)" } ?? "Page unknown"
            let scene = sceneNumber(containing: element.id).map { "Scene \($0)" } ?? "No scene"
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(page), \(scene), \(element.type.displayName)")
            lines.append("  \(mark?.label ?? "Revision") / \(mark?.color.displayName ?? "No color")")
            lines.append("  \(text.isEmpty ? "[blank]" : text)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func productionContextReport() -> String {
        var lines = reportHeader("Production Context Report")
        lines.append("Context: \(productionContextSummary)")
        if let generatedAt = productionContext.generatedAt {
            lines.append("Last refreshed: \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        lines.append("")

        if productionEntities.isEmpty && productionNotes.isEmpty {
            lines.append("No production context records yet. Use Context > Refresh From Script.")
            return lines.joined(separator: "\n")
        }

        for kind in ProductionEntityKind.allCases {
            let entities = productionEntities.filter { $0.kind == kind && $0.status != .ignored }
            guard !entities.isEmpty else {
                continue
            }

            lines.append("\(kind.displayName)")
            for entity in entities.sorted(by: { $0.name < $1.name }) {
                let sceneNumbers = sceneNumbers(containing: entity.sourceElementIDs)
                lines.append("  \(entity.name)")
                lines.append("    Status: \(entity.status.displayName)")
                lines.append("    Source refs: \(entity.sourceElementIDs.count)")
                lines.append("    Scenes: \(sceneNumbers.isEmpty ? "Unknown" : sceneNumbers.map(String.init).joined(separator: ", "))")
            }
            lines.append("")
        }

        if !productionNotes.isEmpty {
            lines.append("Notes")
            for note in productionNotes.prefix(30) {
                let sceneNumbers = sceneNumbers(containing: note.sourceElementIDs)
                lines.append("  \(note.title)")
                lines.append("    Status: \(note.status.displayName)")
                lines.append("    Scenes: \(sceneNumbers.isEmpty ? "Unknown" : sceneNumbers.map(String.init).joined(separator: ", "))")
                lines.append("    \(note.body)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func entitiesForReport(kind: ProductionEntityKind) -> (label: String, entities: [ProductionEntity]) {
        let matching = productionEntities.filter { $0.kind == kind }
        let accepted = matching.filter { $0.status == .accepted }
        if !accepted.isEmpty {
            return ("Accepted production context", accepted)
        }

        let suggested = matching.filter { $0.status == .suggested }
        if !suggested.isEmpty {
            return ("Suggested production context fallback", suggested)
        }

        return ("Script-derived fallback", [])
    }

    private func pageNumber(for elementID: UUID) -> Int? {
        for page in screenplayPages where page.elements.contains(where: { $0.element.id == elementID }) {
            return page.number
        }
        return nil
    }

    private func sceneNumber(containing elementID: UUID) -> Int? {
        guard let index = elementIndex(for: elementID) else {
            return nil
        }

        let count = elements.prefix(through: index).filter { $0.type == .sceneHeading }.count
        return count > 0 ? count : nil
    }

    private func sceneNumbers(containing elementIDs: [UUID]) -> [Int] {
        Set(elementIDs.compactMap { sceneNumber(containing: $0) }).sorted()
    }

    private func drawTitlePage(_ titlePage: TitlePage, in context: CGContext, pageRect: CGRect) {
        context.beginPDFPage(nil)
        withPDFGraphicsContext(context) {
            let centerRect = CGRect(x: 108, y: 390, width: 396, height: 120)
            let titleText = [
                titlePage.title.isEmpty ? title : titlePage.title,
                titlePage.subtitle,
                titlePage.author.isEmpty ? "" : "by \(titlePage.author)"
            ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            titleText.draw(
                in: centerRect,
                withAttributes: pdfAttributes(alignment: .center, weight: .regular, size: 12)
            )

            let footerText = [titlePage.draftDate, titlePage.contact]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            footerText.draw(
                in: CGRect(x: 108, y: 96, width: 396, height: 90),
                withAttributes: pdfAttributes(alignment: .center, weight: .regular, size: 10)
            )
        }
        context.endPDFPage()
    }

    private func drawScriptPages(_ elements: [ScreenplayElement], in context: CGContext, pageRect: CGRect) {
        var pageNumber = 1
        var y: CGFloat = pageRect.height - 72

        func beginScriptPage() {
            context.beginPDFPage(nil)
            y = pageRect.height - 72
            withPDFGraphicsContext(context) {
                "\(pageNumber).".draw(
                    at: CGPoint(x: pageRect.width - 72, y: pageRect.height - 42),
                    withAttributes: pdfAttributes(alignment: .right, weight: .regular, size: 12)
                )
            }
        }

        func endScriptPage() {
            context.endPDFPage()
            pageNumber += 1
        }

        for page in paginate(elements) {
            beginScriptPage()
            for item in page.elements {
                let spec = item.layout
                y -= spec.before + item.textHeight
                let rect = CGRect(x: spec.x, y: y, width: spec.width, height: item.textHeight + 4)
                withPDFGraphicsContext(context) {
                    item.text.draw(
                        in: rect,
                        withAttributes: pdfAttributes(alignment: spec.alignment, weight: spec.weight, size: 12)
                    )
                }
                y -= spec.after
            }
            endScriptPage()
        }
    }

    private func paginate(_ sourceElements: [ScreenplayElement]) -> [ScreenplayPage] {
        let visibleElements = sourceElements.filter {
            $0.type == .pageBreak || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var pages: [ScreenplayPage] = []
        var currentItems: [PaginatedElement] = []
        var usedHeight: CGFloat = 0
        var pageNumber = 1
        var index = 0

        func finishPage() {
            pages.append(ScreenplayPage(number: pageNumber, elements: currentItems))
            currentItems = []
            usedHeight = 0
            pageNumber += 1
        }

        while index < visibleElements.count {
            let element = visibleElements[index]

            if element.type == .pageBreak {
                if !currentItems.isEmpty {
                    finishPage()
                }
                index += 1
                continue
            }

            let item = paginatedElement(for: element)
            let keepTogetherHeight = keepTogetherBlockHeight(in: visibleElements, startingAt: index)
            let requiredHeight = max(item.blockHeight, keepTogetherHeight)

            if !currentItems.isEmpty && usedHeight + requiredHeight > scriptContentHeight {
                finishPage()
            }

            currentItems.append(item)
            usedHeight += item.blockHeight
            index += 1
        }

        if !currentItems.isEmpty || pages.isEmpty {
            finishPage()
        }

        return pages
    }

    private var scriptContentHeight: CGFloat {
        792 - 72 - 72
    }

    private func keepTogetherBlockHeight(in elements: [ScreenplayElement], startingAt index: Int) -> CGFloat {
        guard elements.indices.contains(index) else {
            return 0
        }

        let element = elements[index]
        var keepCount = 1

        if element.type == .character,
           elements.indices.contains(index + 1),
           [.dialogue, .parenthetical].contains(elements[index + 1].type) {
            keepCount = 2
            if elements[index + 1].type == .parenthetical,
               elements.indices.contains(index + 2),
               elements[index + 2].type == .dialogue {
                keepCount = 3
            }
        } else if element.type == .sceneHeading,
                  elements.indices.contains(index + 1),
                  elements[index + 1].type == .action {
            keepCount = 2
        }

        return elements[index..<min(index + keepCount, elements.count)]
            .filter { $0.type != .pageBreak }
            .map { paginatedElement(for: $0).blockHeight }
            .reduce(0, +)
    }

    private func paginatedElement(for element: ScreenplayElement) -> PaginatedElement {
        let spec = pdfLayoutSpec(for: element.type)
        let text = normalizedText(for: element.type, text: element.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let textHeight = pdfHeight(for: text, width: spec.width, type: element.type)
        return PaginatedElement(
            element: element,
            text: text,
            layout: spec,
            textHeight: textHeight,
            blockHeight: spec.before + textHeight + spec.after
        )
    }

    private func withPDFGraphicsContext(_ context: CGContext, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func pdfHeight(for text: String, width: CGFloat, type: ElementType) -> CGFloat {
        let attributes = pdfAttributes(
            alignment: pdfLayoutSpec(for: type).alignment,
            weight: pdfLayoutSpec(for: type).weight,
            size: 12
        )
        let rect = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return max(16, ceil(rect.height))
    }

    private func pdfAttributes(alignment: NSTextAlignment, weight: NSFont.Weight, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = 2
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.black
        ]
    }

    private func pdfLayoutSpec(for type: ElementType) -> PDFLayoutSpec {
        switch type {
        case .sceneHeading:
            return PDFLayoutSpec(x: 108, width: 432, before: 24, after: 0, alignment: .left, weight: .semibold)
        case .action, .general:
            return PDFLayoutSpec(x: 108, width: 432, before: 12, after: 0, alignment: .left, weight: .regular)
        case .character:
            return PDFLayoutSpec(x: 252, width: 270, before: 12, after: 0, alignment: .left, weight: .semibold)
        case .dialogue:
            return PDFLayoutSpec(x: 180, width: 252, before: 0, after: 0, alignment: .left, weight: .regular)
        case .parenthetical:
            return PDFLayoutSpec(x: 216, width: 180, before: 0, after: 0, alignment: .left, weight: .regular)
        case .transition:
            return PDFLayoutSpec(x: 396, width: 115, before: 12, after: 0, alignment: .right, weight: .semibold)
        case .shot:
            return PDFLayoutSpec(x: 108, width: 432, before: 12, after: 0, alignment: .left, weight: .semibold)
        case .pageBreak:
            return PDFLayoutSpec(x: 108, width: 432, before: 24, after: 24, alignment: .center, weight: .regular)
        }
    }

    private func autosave() {
        saveDocument(to: saveURL ?? defaultDownloadsSaveURL(), reportStatus: false)
    }

    private func createSafetySnapshotBeforeRestore() {
        guard let document else {
            return
        }

        let projectURL = saveURL ?? defaultDownloadsSaveURL()
        do {
            let directory = snapshotsDirectory(for: projectURL)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(snapshotFileName(label: "Before Restore", date: Date()))
            let data = try JSONEncoder.openScreenplayEncoder().encode(document)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultSaveFileName() -> String {
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return "\(safeTitle).open-screenplay.json"
    }

    private func defaultReportFileName(for kind: ReportKind) -> String {
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let safeReport = kind.displayName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return "\(safeTitle).\(safeReport).txt"
    }

    private func defaultProductionExportFileName(for kind: ProductionExportKind) -> String {
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let safeExport = kind.displayName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return "\(safeTitle).\(safeExport).\(kind.fileExtension)"
    }

    private func defaultDownloadsSaveURL() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .appendingPathComponent(defaultSaveFileName())
    }

    private func snapshotsDirectory(for projectURL: URL) -> URL {
        projectURL
            .deletingLastPathComponent()
            .appendingPathComponent("ScreenplayOS Snapshots", isDirectory: true)
    }

    private func snapshotFileName(label: String, date: Date) -> String {
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let safeLabel = label
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(safeTitle).\(formatter.string(from: date)).\(safeLabel).snapshot.open-screenplay.json"
    }

    private func loadBundledFixture() {
        for url in fixtureCandidates() where FileManager.default.fileExists(atPath: url.path) {
            loadFDX(at: url)
            return
        }
    }

    private func loadMostRecentWorkingDocument() {
        if let savedURL = mostRecentSavedDocumentURL() {
            loadOpenScreenplay(at: savedURL)
            return
        }

        loadBundledFixture()
    }

    private func mostRecentSavedDocumentURL() -> URL? {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let savedDocuments = files.filter {
            $0.lastPathComponent.hasSuffix(".open-screenplay.json")
        }

        return savedDocuments.max { left, right in
            modificationDate(for: left) < modificationDate(for: right)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func loadRecentDocuments() {
        let paths = UserDefaults.standard.stringArray(forKey: recentDocumentsKey) ?? []
        recentDocuments = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { RecentDocument(url: $0) }
    }

    private func loadSnapshots() {
        guard let saveURL else {
            snapshots = []
            return
        }

        let directory = snapshotsDirectory(for: saveURL)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            snapshots = []
            return
        }

        snapshots = files
            .filter { $0.lastPathComponent.hasSuffix(".snapshot.open-screenplay.json") }
            .map { ProjectSnapshot(url: $0, modifiedAt: modificationDate(for: $0), size: fileSize(for: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func fileSize(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func recordRecentDocument(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: recentDocumentsKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        paths = Array(paths.prefix(8))
        UserDefaults.standard.set(paths, forKey: recentDocumentsKey)
        recentDocuments = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { RecentDocument(url: $0) }
    }

    private func extractedProductionEntities() -> [ProductionEntity] {
        var grouped: [ProductionEntityKind: [String: Set<UUID>]] = [:]

        for element in elements {
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            switch element.type {
            case .character:
                addEntity(.character, name: trimmed, sourceID: element.id, to: &grouped)
            case .sceneHeading:
                let location = locationName(from: trimmed)
                if !location.isEmpty {
                    addEntity(.location, name: location, sourceID: element.id, to: &grouped)
                }
            case .action:
                for candidate in productionCandidates(from: trimmed) {
                    addEntity(candidate.kind, name: candidate.name, sourceID: element.id, to: &grouped)
                }
            default:
                break
            }
        }

        return grouped.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { kind in
            grouped[kind, default: [:]].keys.sorted().map { name in
                ProductionEntity(
                    kind: kind,
                    name: name,
                    status: .suggested,
                    sourceElementIDs: Array(grouped[kind]?[name] ?? []).sorted { $0.uuidString < $1.uuidString }
                )
            }
        }
    }

    private func extractedProductionNotes() -> [ProductionNote] {
        formatIssues.prefix(12).map { issue in
            ProductionNote(
                title: issue.title,
                body: issue.detail,
                status: .suggested,
                sourceElementIDs: [issue.elementID]
            )
        }
    }

    private func contextAssistantResult(for prompt: String) -> (summary: String, recordCount: Int, notes: [ProductionNote], entities: [ProductionEntity]) {
        let lowercased = prompt.lowercased()

        if lowercased.contains("continuity") || lowercased.contains("question") {
            let notes = continuityQuestionNotes()
            return ("Found \(notes.count) continuity questions", notes.count, notes, [])
        }

        if lowercased.contains("risk") || lowercased.contains("production") {
            let notes = productionRiskNotes()
            return ("Found \(notes.count) production risks", notes.count, notes, [])
        }

        if lowercased.contains("shot") || lowercased.contains("storyboard") {
            let notes = shotCandidateNotes()
            return ("Suggested \(notes.count) shot candidates", notes.count, notes, [])
        }

        if lowercased.contains("arc") || lowercased.contains("character") {
            let notes = characterArcNotes()
            return ("Summarized \(notes.count) character arcs", notes.count, notes, [])
        }

        let notes = [
            ProductionNote(
                title: "Context assistant note",
                body: "Captured request for future AI processing: \(prompt)",
                status: .suggested
            )
        ]
        return ("Captured request for future AI processing", notes.count, notes, [])
    }

    private func generatedProposals(for mode: WorkflowMode) -> [AIProposal] {
        switch mode {
        case .writing:
            return writingProposals()
        case .outline:
            return outlineProposals()
        case .directing:
            return directingProposals()
        case .boards:
            return boardProposals()
        case .production:
            return productionProposals()
        case .edit:
            return editProposals()
        }
    }

    private func outlineTemplate(_ kind: OutlineTemplateKind) -> [OutlineBeat] {
        let beats: [(String, String)]
        switch kind {
        case .heroJourney:
            beats = [
                ("Ordinary World", "Show the hero's normal life before the story pressure arrives."),
                ("Call to Adventure", "Introduce the invitation, disruption, threat, or need that starts the journey."),
                ("Refusal of the Call", "Let the hero hesitate, resist, or misunderstand the cost of action."),
                ("Meeting the Mentor", "Bring in guidance, a gift, training, or a principle that prepares the hero."),
                ("Crossing the Threshold", "Move the hero into the new world where old rules no longer hold."),
                ("Tests, Allies, Enemies", "Build complications, relationships, rival forces, and new skills."),
                ("Approach to the Inmost Cave", "Focus the hero toward the central ordeal or deepest risk."),
                ("Ordeal", "Force the hero through a major crisis, loss, revelation, or confrontation."),
                ("Reward", "Let the hero gain knowledge, power, proof, or emotional clarity."),
                ("The Road Back", "Turn the gain into a return journey with renewed danger or consequence."),
                ("Resurrection", "Stage the final test where the hero must be changed, not merely lucky."),
                ("Return with the Elixir", "Show what the hero brings back and how the world is different.")
            ]
        case .threeAct:
            beats = [
                ("Act I Setup", "Establish world, tone, central character, and the story problem."),
                ("Inciting Incident", "Introduce the event that makes the old normal unstable."),
                ("First Turning Point", "Push the protagonist into a clear new direction."),
                ("Act II Promise", "Explore the premise through attempts, complications, and discoveries."),
                ("Midpoint", "Shift the stakes, knowledge, or power balance."),
                ("Second Turning Point", "Force a decisive move into the final act."),
                ("Act III Climax", "Resolve the central conflict through a final test."),
                ("Resolution", "Show the new state of the world and character.")
            ]
        case .saveTheCat:
            beats = [
                ("Opening Image", "Present a visual snapshot of the starting world."),
                ("Theme Stated", "Hint at the emotional or moral question."),
                ("Set-Up", "Introduce the hero, world, wants, flaws, and stakes."),
                ("Catalyst", "Disrupt the hero's life with the story event."),
                ("Debate", "Let the hero hesitate, question, or resist action."),
                ("Break into Two", "Move into the main story world or pursuit."),
                ("B Story", "Introduce a relationship or thread that carries theme."),
                ("Fun and Games", "Deliver the premise in its clearest form."),
                ("Midpoint", "Raise stakes with a false victory or false defeat."),
                ("Bad Guys Close In", "Increase pressure from outside and inside."),
                ("All Is Lost", "Push the hero to the low point."),
                ("Dark Night of the Soul", "Let the hero process the loss or revelation."),
                ("Break into Three", "Find the synthesis or final plan."),
                ("Finale", "Resolve the story through escalating final action."),
                ("Final Image", "Mirror or answer the opening image.")
            ]
        case .tvActs:
            beats = [
                ("Teaser", "Hook the audience and set the episode engine in motion."),
                ("Act One", "Launch the problem, stakes, and main episode question."),
                ("Act Two", "Complicate the pursuit and deepen character pressure."),
                ("Act Three", "Escalate consequences and force a harder choice."),
                ("Act Four", "Drive toward climax, reveal, or confrontation."),
                ("Tag", "Land the final button, aftermath, joke, twist, or emotional echo.")
            ]
        case .characterArc:
            beats = [
                ("Initial State", "Define who the character is before change begins."),
                ("Want", "Clarify the external goal or desire."),
                ("Need", "Clarify the internal growth or truth they resist."),
                ("Pressure", "Apply story events that challenge the old pattern."),
                ("Choice", "Force a meaningful decision that reveals change or refusal."),
                ("Cost", "Show what the journey has taken or exposed."),
                ("Transformation", "Let the character act from the new self."),
                ("Aftermath", "Show how the character and world are altered.")
            ]
        case .mystery:
            beats = [
                ("Puzzle Hook", "Introduce the central mystery or impossible question."),
                ("Investigator Frame", "Establish who is asking questions and why."),
                ("Clue Trail Begins", "Present early clues, witnesses, or contradictions."),
                ("First Theory", "Let the characters form an incomplete explanation."),
                ("Complication", "Undermine the first theory with new evidence."),
                ("False Lead", "Pursue an attractive but wrong answer."),
                ("Hidden Connection", "Reveal how separate pieces are related."),
                ("Reversal", "Change the meaning of earlier evidence."),
                ("Solution", "Expose the true answer and logic chain."),
                ("Consequences", "Show what the truth changes.")
            ]
        case .customBlank:
            beats = [
                ("Beat 1", "Define the purpose of this story beat."),
                ("Beat 2", "Define the purpose of this story beat."),
                ("Beat 3", "Define the purpose of this story beat."),
                ("Beat 4", "Define the purpose of this story beat."),
                ("Beat 5", "Define the purpose of this story beat."),
                ("Beat 6", "Define the purpose of this story beat.")
            ]
        }

        return beats.enumerated().map { index, beat in
            OutlineBeat(
                template: kind.displayName,
                order: index + 1,
                name: beat.0,
                purpose: beat.1
            )
        }
    }

    private func applyTrustedAction(for proposal: AIProposal) -> Bool {
        switch proposal.workflow {
        case .writing:
            return applyWritingProposal(proposal)
        case .outline:
            return applyOutlineProposal(proposal)
        case .directing:
            return applyDirectingProposal(proposal)
        case .boards:
            return applyBoardsProposal(proposal)
        case .production:
            return applyProductionProposal(proposal)
        case .edit:
            return applyEditProposal(proposal)
        }
    }

    private func applyWritingProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)

        if proposal.title.localizedCaseInsensitiveContains("empty") {
            deleteEmptyElements()
            return true
        }

        if proposal.title.localizedCaseInsensitiveContains("uppercase")
            || proposal.title.localizedCaseInsensitiveContains("long action")
            || proposal.title.localizedCaseInsensitiveContains("clean") {
            cleanScript()
            return true
        }

        return true
    }

    private func applyOutlineProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)
        workflowMode = .outline
        sidebarMode = .outline

        if let outlineBeatID = proposal.target.outlineBeatID,
           let sceneSpineID = proposal.target.sceneSpineID {
            return linkScene(sceneSpineID, toOutlineBeatID: outlineBeatID, actor: .proposal)
        }

        if proposal.title.localizedCaseInsensitiveContains("template") {
            seedSelectedOutlineTemplate()
            return true
        }

        return true
    }

    private func applyDirectingProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)

        guard let sceneSpineID = proposal.target.sceneSpineID,
              let breakdown = sceneBreakdowns.first(where: { $0.editSpineID == sceneSpineID })
        else {
            return true
        }

        navigateToSceneBreakdown(breakdown)
        scrollTargetElementID = breakdown.elementID

        if proposal.title.localizedCaseInsensitiveContains("shot list")
            || proposal.body.localizedCaseInsensitiveContains("shot list") {
            generateShotListForSelectedScene()
            return true
        }

        if proposal.title.localizedCaseInsensitiveContains("board")
            || proposal.body.localizedCaseInsensitiveContains("board") {
            if shotsForSelectedScene.isEmpty {
                generateShotListForSelectedScene()
            }
            generateBoardsForSelectedScene()
            return true
        }

        return true
    }

    private func applyBoardsProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)
        workflowMode = .boards
        sidebarMode = .boards

        if shotsForSelectedScene.isEmpty {
            generateShotListForSelectedScene()
        }

        if proposal.title.localizedCaseInsensitiveContains("board")
            || proposal.body.localizedCaseInsensitiveContains("board") {
            generateBoardsForSelectedScene()
            return true
        }

        return true
    }

    private func applyProductionProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)

        if let contextRecordID = proposal.target.contextRecordID,
           let index = document?.productionContext.entities.firstIndex(where: { $0.id == contextRecordID }) {
            rememberUndoState()
            document?.productionContext.entities[index].status = .accepted
            document?.project.metadata.modifiedAt = Date()
            return true
        }

        if proposal.title.localizedCaseInsensitiveContains("context")
            || proposal.body.localizedCaseInsensitiveContains("context") {
            refreshProductionContextFromScript()
            return true
        }

        if proposal.title.localizedCaseInsensitiveContains("shot list") {
            workflowMode = .directing
            sidebarMode = .breakdown
            if let first = sceneBreakdowns.first {
                navigateToSceneBreakdown(first)
                generateShotListForSelectedScene()
            }
            return true
        }

        if proposal.title.localizedCaseInsensitiveContains("board") {
            workflowMode = .boards
            sidebarMode = .boards
            if let first = sceneBreakdowns.first {
                navigateToSceneBreakdown(first)
                if shotsForSelectedScene.isEmpty {
                    generateShotListForSelectedScene()
                }
                generateBoardsForSelectedScene()
            }
            return true
        }

        return true
    }

    private func applyEditProposal(_ proposal: AIProposal) -> Bool {
        navigateToProposalTarget(proposal)
        workflowMode = .edit
        sidebarMode = .editorial

        if proposal.title.localizedCaseInsensitiveContains("handoff") {
            sidebarMode = .exports
            return true
        }

        return true
    }

    private func writingProposals() -> [AIProposal] {
        var proposals = formatIssues.prefix(8).map { issue in
            AIProposal(
                workflow: .writing,
                title: issue.title,
                body: issue.detail,
                target: AIProposalTarget(screenplayElementID: issue.elementID)
            )
        }

        if let firstScene = scenes.first, let firstBreakdown = sceneBreakdowns.first {
            proposals.append(AIProposal(
                workflow: .writing,
                title: "Review opening scene hook",
                body: "Check whether the first scene establishes tone, location, and a clear visual question quickly enough.",
                target: AIProposalTarget(screenplayElementID: firstScene.elementID, sceneSpineID: firstBreakdown.editSpineID)
            ))
        }

        return Array(proposals.prefix(10))
    }

    private func outlineProposals() -> [AIProposal] {
        var proposals: [AIProposal] = []

        if outlineBeats.isEmpty {
            proposals.append(AIProposal(
                workflow: .outline,
                title: "Create outline template",
                body: "Seed an outline structure before mapping story beats to screenplay scenes.",
                target: AIProposalTarget(sceneSpineID: selectedSceneBreakdown?.editSpineID)
            ))
        }

        let unmappedBeatCount = outlineBeats.filter { $0.linkedSceneSpineIDs.isEmpty }.count
        if unmappedBeatCount > 0 {
            proposals.append(AIProposal(
                workflow: .outline,
                title: "Map outline beats",
                body: "\(unmappedBeatCount) outline beats are not linked to script scenes yet.",
                target: AIProposalTarget(sceneSpineID: selectedSceneBreakdown?.editSpineID)
            ))
        }

        proposals.append(contentsOf: outlineMappingProposals())
        return Array(proposals.prefix(10))
    }

    private func outlineMappingProposals() -> [AIProposal] {
        guard !outlineBeats.isEmpty, !sceneBreakdowns.isEmpty else {
            return []
        }

        let totalBeats = max(outlineBeats.count, 1)
        let totalScenes = max(sceneBreakdowns.count, 1)

        return outlineBeats
            .filter { $0.linkedSceneSpineIDs.isEmpty }
            .prefix(6)
            .compactMap { beat in
                let sceneIndex = min(
                    sceneBreakdowns.count - 1,
                    max(0, Int(round(Double(beat.order - 1) * Double(totalScenes - 1) / Double(totalBeats - 1))))
                )
                let scene = sceneBreakdowns[sceneIndex]
                return AIProposal(
                    workflow: .outline,
                    title: "Map \(beat.name)",
                    body: "Suggested link: \(scene.editSpineID) \(scene.heading).",
                    target: AIProposalTarget(
                        screenplayElementID: scene.elementID,
                        sceneSpineID: scene.editSpineID,
                        outlineBeatID: beat.id
                    )
                )
            }
    }

    private func directingProposals() -> [AIProposal] {
        var proposals: [AIProposal] = []

        for breakdown in sceneBreakdowns.prefix(8) {
            if shots.filter({ $0.sceneSpineID == breakdown.editSpineID }).isEmpty {
                proposals.append(AIProposal(
                    workflow: .directing,
                    title: "Create shot list for \(breakdown.editSpineID)",
                    body: "This scene has no shot list yet. Generate starter coverage before moving to boards.",
                    target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: breakdown.editSpineID)
                ))
            }

        }

        return Array(proposals.prefix(10))
    }

    private func boardProposals() -> [AIProposal] {
        var proposals: [AIProposal] = []

        for breakdown in sceneBreakdowns.prefix(8) {
            let sceneShots = shots.filter { $0.sceneSpineID == breakdown.editSpineID }
            let sceneBoards = boardFrames.filter { $0.sceneSpineID == breakdown.editSpineID }

            if sceneShots.isEmpty {
                proposals.append(AIProposal(
                    workflow: .boards,
                    title: "Create shot list before boards for \(breakdown.editSpineID)",
                    body: "Boards should attach to canonical shots, so create starter shot intent before generating frames.",
                    target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: breakdown.editSpineID)
                ))
            } else if sceneBoards.isEmpty {
                proposals.append(AIProposal(
                    workflow: .boards,
                    title: "Create board sequence for \(breakdown.editSpineID)",
                    body: "This scene has shots but no board frames yet. Generate boards so the scene can play as a Boardomatic sequence.",
                    target: AIProposalTarget(screenplayElementID: breakdown.elementID, sceneSpineID: breakdown.editSpineID)
                ))
            }
        }

        if !boardFrames.isEmpty && boardFrames.allSatisfy({ $0.durationSeconds == 4.0 }) {
            proposals.append(AIProposal(
                workflow: .boards,
                title: "Review board timing",
                body: "All board frames still use the default duration. Adjust timing before judging the sequence rhythm.",
                target: AIProposalTarget(sceneSpineID: selectedSceneBreakdown?.editSpineID)
            ))
        }

        return Array(proposals.prefix(10))
    }

    private func productionProposals() -> [AIProposal] {
        var proposals: [AIProposal] = []

        let suggestedContext = productionEntities.filter { $0.status == .suggested }.prefix(8)
        proposals.append(contentsOf: suggestedContext.map { entity in
            AIProposal(
                workflow: .production,
                title: "Review \(entity.name)",
                body: "This \(entity.kind.displayName.lowercased()) record is still suggested. Accept or ignore it before production handoff.",
                target: AIProposalTarget(
                    screenplayElementID: entity.sourceElementIDs.first,
                    contextRecordID: entity.id
                )
            )
        })

        if shots.isEmpty {
            proposals.append(AIProposal(
                workflow: .production,
                title: "Shot list missing",
                body: "No shots have been generated yet. Production exports will be more useful after scene shot lists exist.",
                target: AIProposalTarget(sceneSpineID: sceneBreakdowns.first?.editSpineID)
            ))
        }

        return Array(proposals.prefix(10))
    }

    private func editProposals() -> [AIProposal] {
        var proposals: [AIProposal] = []

        if editorialBeats.isEmpty {
            proposals.append(AIProposal(
                workflow: .edit,
                title: "Build edit spine",
                body: "Create scene-linked edit spine beats before handoff to editing software.",
                target: AIProposalTarget(sceneSpineID: sceneBreakdowns.first?.editSpineID)
            ))
        }

        if boardFrames.isEmpty {
            proposals.append(AIProposal(
                workflow: .edit,
                title: "Board frames missing",
                body: "No board frames have been generated yet. Boards can become visual references for the edit spine.",
                target: AIProposalTarget(sceneSpineID: sceneBreakdowns.first?.editSpineID)
            ))
        }

        if !editorialBeats.isEmpty && productionExportPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            proposals.append(AIProposal(
                workflow: .edit,
                title: "Prepare edit handoff",
                body: "Review edit spine scene IDs, shot references, and export packet readiness before Premiere handoff.",
                target: AIProposalTarget(sceneSpineID: selectedSceneBreakdown?.editSpineID)
            ))
        }

        return Array(proposals.prefix(10))
    }

    private func continuityQuestionNotes() -> [ProductionNote] {
        formatIssues.prefix(10).map { issue in
            ProductionNote(
                title: "Continuity question: \(issue.title)",
                body: issue.detail,
                status: .suggested,
                sourceElementIDs: [issue.elementID]
            )
        }
    }

    private func productionRiskNotes() -> [ProductionNote] {
        let longAction = elements.filter { $0.type == .action && $0.text.count > 350 }.prefix(8)
        let vfxHeavy = elements.filter {
            $0.text.localizedCaseInsensitiveContains("glow")
                || $0.text.localizedCaseInsensitiveContains("spark")
                || $0.text.localizedCaseInsensitiveContains("hologram")
                || $0.text.localizedCaseInsensitiveContains("beam")
        }.prefix(8)

        var notes = longAction.map {
            ProductionNote(
                title: "Production risk: dense action",
                body: "This action block may need breakdown into smaller beats for boards, assets, or schedule planning.",
                status: .suggested,
                sourceElementIDs: [$0.id]
            )
        }

        notes.append(contentsOf: vfxHeavy.map {
            ProductionNote(
                title: "Production risk: visual effect",
                body: "This line appears to involve light, magic, hologram, or effects work.",
                status: .suggested,
                sourceElementIDs: [$0.id]
            )
        })

        return Array(notes.prefix(12))
    }

    private func generatedShots(for breakdown: SceneBreakdown) -> [Shot] {
        let sceneElements = elementsForScene(startingAt: breakdown.elementID)
        var shots: [Shot] = []

        func appendShot(
            setup: ShotSetup,
            label: String,
            elementID: UUID,
            notes: String
        ) {
            let nextNumber = shots.count + 1
            shots.append(Shot(
                sceneSpineID: breakdown.editSpineID,
                shotNumber: nextNumber,
                label: "\(breakdown.editSpineID)-SH\(String(format: "%03d", nextNumber)) \(label)",
                setup: setup,
                status: .suggested,
                sourceRefs: [ShotSourceRef(screenplayElementID: elementID)],
                notes: notes
            ))
        }

        if let heading = sceneElements.first {
            appendShot(
                setup: .establishing,
                label: "Establish \(breakdown.locations.first ?? breakdown.heading)",
                elementID: heading.id,
                notes: "Anchor the audience in the scene geography and tone."
            )
        }

        for element in sceneElements where [.action, .shot].contains(element.type) {
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            let setup: ShotSetup = text.localizedCaseInsensitiveContains("glow")
                || text.localizedCaseInsensitiveContains("spark")
                || text.localizedCaseInsensitiveContains("hologram")
                || text.localizedCaseInsensitiveContains("beam") ? .visualEffect : .coverage
            appendShot(
                setup: setup,
                label: shortShotLabel(from: text),
                elementID: element.id,
                notes: text
            )
        }

        let dialogueElements = sceneElements.filter { $0.type == .dialogue }
        for element in dialogueElements.prefix(4) {
            let character = previousCharacterName(before: element.id) ?? "Character"
            appendShot(
                setup: .coverage,
                label: "Cover \(character)",
                elementID: element.id,
                notes: element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return Array(shots.prefix(18))
    }

    private func generatedBoardFrames(for shots: [Shot], breakdown: SceneBreakdown) -> [BoardFrame] {
        shots.enumerated().map { offset, shot in
            BoardFrame(
                shotID: shot.id,
                sceneSpineID: breakdown.editSpineID,
                frameNumber: offset + 1,
                label: shot.label,
                prompt: boardPrompt(for: shot, breakdown: breakdown),
                status: shot.status == .selected ? .selected : .suggested,
                notes: shot.notes,
                sourceRefs: shot.sourceRefs
            )
        }
    }

    private func boardPrompt(for shot: Shot, breakdown: SceneBreakdown) -> String {
        let location = breakdown.locations.first ?? breakdown.heading
        let cast = breakdown.characters.prefix(4).joined(separator: ", ")
        let setup = shot.setup.displayName.lowercased()
        let castPhrase = cast.isEmpty ? "" : " featuring \(cast)"
        return "\(setup) frame for \(location)\(castPhrase): \(shot.notes)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func elementsForScene(startingAt sceneElementID: UUID) -> [ScreenplayElement] {
        guard let startIndex = elementIndex(for: sceneElementID) else {
            return []
        }

        let nextSceneIndex = elements[(startIndex + 1)..<elements.count].firstIndex { $0.type == .sceneHeading } ?? elements.count
        return Array(elements[startIndex..<nextSceneIndex])
    }

    private func shortShotLabel(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 72 else {
            return cleaned
        }

        let cutoff = cleaned.index(cleaned.startIndex, offsetBy: 72)
        return String(cleaned[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func shotCandidateNotes() -> [ProductionNote] {
        scenes.prefix(12).map { scene in
            ProductionNote(
                title: "Shot candidate: \(scene.title)",
                body: "Start with an establishing shot, then cover the first action beat and any character entrance in this scene.",
                status: .suggested,
                sourceElementIDs: [scene.elementID]
            )
        }
    }

    private func characterArcNotes() -> [ProductionNote] {
        characterNames.prefix(12).map { character in
            let dialogueCount = elements.filter { $0.type == .dialogue && previousCharacterName(before: $0.id) == character }.count
            return ProductionNote(
                title: "Character arc: \(character)",
                body: "\(character) has \(dialogueCount) dialogue lines in this draft. Review first entrance, turning point, and last beat before production planning.",
                status: .suggested
            )
        }
    }

    private func previousCharacterName(before elementID: UUID) -> String? {
        guard let index = elementIndex(for: elementID), index > 0 else {
            return nil
        }

        return elements[..<index].last { $0.type == .character }?.text
    }

    private func addEntity(
        _ kind: ProductionEntityKind,
        name: String,
        sourceID: UUID,
        to grouped: inout [ProductionEntityKind: [String: Set<UUID>]]
    ) {
        let cleanedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()[]{}\"'"))

        guard cleanedName.count > 1 else {
            return
        }

        grouped[kind, default: [:]][cleanedName, default: []].insert(sourceID)
    }

    private func locationName(from sceneHeading: String) -> String {
        var heading = sceneHeading.uppercased()
        for prefix in ["INT./EXT.", "INT/EXT.", "I/E.", "INT.", "EXT."] {
            if heading.hasPrefix(prefix) {
                heading.removeFirst(prefix.count)
                break
            }
        }

        return heading
            .components(separatedBy: " - ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func productionCandidates(from actionText: String) -> [(kind: ProductionEntityKind, name: String)] {
        let words = actionText
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?()[]{}\"'")) }
            .filter { !$0.isEmpty }

        var candidates: [(ProductionEntityKind, String)] = []
        for word in words where word.count > 2 {
            if word == word.uppercased(), !commonUppercaseWords.contains(word) {
                candidates.append((.prop, word.capitalized))
            }
        }

        if actionText.localizedCaseInsensitiveContains("glow")
            || actionText.localizedCaseInsensitiveContains("hologram")
            || actionText.localizedCaseInsensitiveContains("spark")
            || actionText.localizedCaseInsensitiveContains("beam") {
            candidates.append((.visualEffect, "Light / glow effect"))
        }

        return candidates
    }

    private func productionEntitiesForScene(sourceIDs: Set<UUID>, kind: ProductionEntityKind) -> [String] {
        productionEntities
            .filter { entity in
                entity.kind == kind
                    && entity.status != .ignored
                    && !Set(entity.sourceElementIDs).isDisjoint(with: sourceIDs)
            }
            .map(\.name)
            .uniqued()
            .sorted()
    }

    private var commonUppercaseWords: Set<String> {
        ["A", "AN", "AND", "AS", "AT", "BUT", "BY", "FOR", "FROM", "IN", "INTO", "IS", "IT", "NO", "OF", "ON", "OR", "THE", "TO", "WITH"]
    }

    private func fixtureCandidates() -> [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoFromSource = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return [
            currentDirectory,
            currentDirectory.deletingLastPathComponent(),
            repoFromSource
        ].map {
            $0.appendingPathComponent("Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx")
        }
    }
}

struct SceneSummary: Equatable, Identifiable {
    let number: Int
    let elementID: UUID
    let title: String

    var id: UUID {
        elementID
    }
}

struct SceneBreakdown: Equatable, Identifiable {
    let number: Int
    let editSpineID: String
    let elementID: UUID
    let heading: String
    let pageNumber: Int?
    let elementCount: Int
    let actionBeatCount: Int
    let revisionCount: Int
    let characters: [String]
    let locations: [String]
    let props: [String]
    let visualEffects: [String]
    let notes: [String]
    let firstAction: String

    var id: UUID {
        elementID
    }
}

struct FormatIssue: Equatable, Identifiable {
    let id = UUID()
    let elementID: UUID
    let title: String
    let detail: String
    let severity: Severity

    enum Severity: String {
        case warning
        case cleanup
    }
}

struct FindMatch: Equatable, Identifiable {
    let number: Int
    let elementID: UUID
    let elementType: String
    let preview: String

    var id: UUID {
        elementID
    }
}

struct ScreenplayPage: Identifiable {
    let number: Int
    let elements: [PaginatedElement]

    var id: Int {
        number
    }
}

struct PaginatedElement: Identifiable {
    let element: ScreenplayElement
    let text: String
    let layout: PDFLayoutSpec
    let textHeight: CGFloat
    let blockHeight: CGFloat

    var id: UUID {
        element.id
    }
}

struct PDFLayoutSpec {
    let x: CGFloat
    let width: CGFloat
    let before: CGFloat
    let after: CGFloat
    let alignment: NSTextAlignment
    let weight: NSFont.Weight
}

struct RecentDocument: Identifiable, Hashable {
    let url: URL

    var id: String {
        url.path
    }

    var name: String {
        url.lastPathComponent
    }
}

struct ProjectSnapshot: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date
    let size: Int

    var id: String {
        url.path
    }

    var name: String {
        let fileName = url.lastPathComponent
        let parts = fileName.components(separatedBy: ".")
        guard parts.count >= 4 else {
            return fileName
        }

        return parts[2].replacingOccurrences(of: "_", with: " ")
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct ContextAssistantJob: Identifiable, Equatable {
    let id: UUID
    let prompt: String
    var status: ContextAssistantJobStatus
    var summary: String
    var createdRecords: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        status: ContextAssistantJobStatus,
        summary: String,
        createdRecords: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.summary = summary
        self.createdRecords = createdRecords
        self.createdAt = createdAt
    }
}

enum ContextAssistantJobStatus: String {
    case queued
    case running
    case complete
    case failed

    var displayName: String {
        rawValue.capitalized
    }
}

enum TitlePageField {
    case title
    case subtitle
    case author
    case contact
    case draftDate
}

enum WorkflowMode: String, CaseIterable, Identifiable {
    case outline = "Outline"
    case writing = "Script"
    case directing = "Shot"
    case boards = "Boards"
    case production = "Production"
    case edit = "Edit"

    static var allCases: [WorkflowMode] {
        [.outline, .writing, .directing, .boards, .edit]
    }

    var id: String {
        rawValue
    }

    var defaultSidebarMode: SidebarMode {
        switch self {
        case .writing:
            return .navigator
        case .outline:
            return .outline
        case .directing:
            return .breakdown
        case .boards:
            return .boards
        case .production:
            return .productionContext
        case .edit:
            return .editorial
        }
    }
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case navigator = "Navigator"
    case outline = "Outline"
    case proposals = "Proposals"
    case activity = "Activity"
    case productionContext = "Context"
    case breakdown = "Breakdown"
    case boards = "Boards"
    case reports = "Reports"
    case exports = "Exports"
    case editorial = "Edit Spine"
    case snapshots = "Snapshots"
    case notes = "Notes"
    case search = "Search"
    case assistant = "Format"
    case titlePage = "Title Page"

    var id: String {
        rawValue
    }

    var workflowMode: WorkflowMode {
        switch self {
        case .navigator, .search, .assistant, .titlePage:
            return .writing
        case .outline:
            return .outline
        case .breakdown:
            return .directing
        case .boards:
            return .boards
        case .productionContext, .reports, .snapshots, .notes:
            return .writing
        case .exports, .editorial:
            return .edit
        case .proposals, .activity:
            return .writing
        }
    }

    var isCrossCutting: Bool {
        switch self {
        case .proposals, .activity, .productionContext, .reports, .snapshots, .notes:
            return true
        default:
            return false
        }
    }
}

enum ReportKind: String, CaseIterable, Identifiable {
    case scene
    case character
    case location
    case revision
    case productionContext

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .scene:
            return "Scene Report"
        case .character:
            return "Character Report"
        case .location:
            return "Location Report"
        case .revision:
            return "Revision Report"
        case .productionContext:
            return "Production Context Report"
        }
    }
}

enum ProductionExportKind: String, CaseIterable, Identifiable {
    case selectedScenePacket
    case sceneBreakdownCSV
    case shotListCSV
    case boardFramesCSV
    case editGuideCSV
    case editTimelineCSV

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .selectedScenePacket:
            return "Selected Scene Packet"
        case .sceneBreakdownCSV:
            return "Scene Breakdown CSV"
        case .shotListCSV:
            return "Shot List CSV"
        case .boardFramesCSV:
            return "Board Frames CSV"
        case .editGuideCSV:
            return "Edit Guide CSV"
        case .editTimelineCSV:
            return "Edit Timeline CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .selectedScenePacket:
            return "txt"
        case .sceneBreakdownCSV, .shotListCSV, .boardFramesCSV, .editGuideCSV, .editTimelineCSV:
            return "csv"
        }
    }
}

enum OutlineTemplateKind: String, CaseIterable, Identifiable {
    case heroJourney
    case threeAct
    case saveTheCat
    case tvActs
    case characterArc
    case mystery
    case customBlank

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .heroJourney:
            return "Hero's Journey"
        case .threeAct:
            return "Three-Act Structure"
        case .saveTheCat:
            return "Save the Cat"
        case .tvActs:
            return "TV Teaser / Acts / Tag"
        case .characterArc:
            return "Character Arc"
        case .mystery:
            return "Mystery / Investigation"
        case .customBlank:
            return "Custom Blank"
        }
    }
}

private extension String {
    var isUppercase: Bool {
        self == uppercased()
    }
}

private extension Array where Element == String {
    func joinedOrNone() -> String {
        isEmpty ? "None" : joined(separator: ", ")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
