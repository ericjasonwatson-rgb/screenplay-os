import Foundation
import SwiftUI
import ScreenplayDomain

enum WorkspaceRegion: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case primaryWorkspace = "Workspace"
    case context = "Context"

    var id: String {
        rawValue
    }
}

enum SelectionKind: String, CaseIterable, Identifiable {
    case none = "None"
    case screenplayElement = "Screenplay Element"
    case scene = "Scene"
    case outlineBeat = "Outline Beat"
    case shot = "Shot"
    case boardFrame = "Board Frame"
    case productionEntity = "Production Entity"
    case productionNote = "Production Note"
    case editorialBeat = "Editorial Beat"

    var id: String {
        rawValue
    }
}

struct ObjectSelection: Equatable {
    var kind: SelectionKind
    var id: UUID?
    var sceneSpineID: String?

    static let none = ObjectSelection(kind: .none, id: nil, sceneSpineID: nil)

    static func screenplayElement(_ id: UUID) -> ObjectSelection {
        ObjectSelection(kind: .screenplayElement, id: id, sceneSpineID: nil)
    }

    static func scene(_ id: UUID, sceneSpineID: String?) -> ObjectSelection {
        ObjectSelection(kind: .scene, id: id, sceneSpineID: sceneSpineID)
    }

    static func outlineBeat(_ id: UUID) -> ObjectSelection {
        ObjectSelection(kind: .outlineBeat, id: id, sceneSpineID: nil)
    }

    static func shot(_ id: UUID, sceneSpineID: String) -> ObjectSelection {
        ObjectSelection(kind: .shot, id: id, sceneSpineID: sceneSpineID)
    }

    static func boardFrame(_ id: UUID, sceneSpineID: String) -> ObjectSelection {
        ObjectSelection(kind: .boardFrame, id: id, sceneSpineID: sceneSpineID)
    }

    static func productionEntity(_ id: UUID) -> ObjectSelection {
        ObjectSelection(kind: .productionEntity, id: id, sceneSpineID: nil)
    }

    static func productionNote(_ id: UUID) -> ObjectSelection {
        ObjectSelection(kind: .productionNote, id: id, sceneSpineID: nil)
    }

    static func editorialBeat(_ id: UUID, sceneSpineID: String) -> ObjectSelection {
        ObjectSelection(kind: .editorialBeat, id: id, sceneSpineID: sceneSpineID)
    }
}

struct SelectionContext: Equatable {
    var kind: SelectionKind
    var id: UUID?
    var sceneSpineID: String?
    var title: String
    var detail: String
    var workflowMode: WorkflowMode

    static func empty(workflowMode: WorkflowMode) -> SelectionContext {
        SelectionContext(
            kind: .none,
            id: nil,
            sceneSpineID: nil,
            title: "No Selection",
            detail: "Select screenplay material to inspect it.",
            workflowMode: workflowMode
        )
    }
}

enum InspectorAction: String, CaseIterable, Identifiable {
    case jumpToSource = "Source"
    case changeElementType = "Change Element Type"
    case linkOutlineBeat = "Link Outline Beat"
    case generateShots = "Generate Shots"
    case generateBoards = "Generate Boards"
    case refreshContext = "Refresh Context"
    case acceptContext = "Accept"
    case ignoreContext = "Ignore"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .jumpToSource:
            return "arrow.turn.down.right"
        case .changeElementType:
            return "textformat"
        case .linkOutlineBeat:
            return "link"
        case .generateShots:
            return "camera.viewfinder"
        case .generateBoards:
            return "rectangle.on.rectangle"
        case .refreshContext:
            return "arrow.clockwise"
        case .acceptContext:
            return "checkmark.circle"
        case .ignoreContext:
            return "xmark.circle"
        }
    }

    var compactTitle: String {
        switch self {
        case .changeElementType:
            return "Change Type"
        case .linkOutlineBeat:
            return "Link Beat"
        case .generateShots:
            return "Shots"
        case .generateBoards:
            return "Boards"
        case .refreshContext:
            return "Refresh"
        default:
            return rawValue
        }
    }
}

struct InspectorContext: Equatable {
    var selection: SelectionContext
    var title: String
    var subtitle: String
    var details: [InspectorDetail]
    var actions: [InspectorAction]

    static func empty(workflowMode: WorkflowMode) -> InspectorContext {
        let selection = SelectionContext.empty(workflowMode: workflowMode)
        return InspectorContext(
            selection: selection,
            title: selection.title,
            subtitle: selection.detail,
            details: [],
            actions: []
        )
    }
}

struct InspectorDetail: Equatable, Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

enum CommandPaletteCommand: String, CaseIterable, Identifiable {
    case newScreenplay
    case open
    case save
    case saveAs
    case exportPDF
    case focusMode
    case contextInspector
    case cleanScript
    case deleteBlankElements
    case generateProposals
    case refreshContext
    case generateShotList
    case generateBoards
    case showNavigator
    case showOutline
    case showSearch
    case showFormat
    case showTitlePage
    case showBreakdown
    case showBoards
    case showContext
    case showReports
    case showExports
    case showEditSpine
    case showActivity
    case showSnapshots
    case createSnapshot
    case showNotes
    case addScriptNote

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .newScreenplay:
            return "New Screenplay"
        case .open:
            return "Open"
        case .save:
            return "Save"
        case .saveAs:
            return "Save As"
        case .exportPDF:
            return "Export PDF"
        case .focusMode:
            return "Toggle Focus Mode"
        case .contextInspector:
            return "Toggle Context Inspector"
        case .cleanScript:
            return "Clean Script"
        case .deleteBlankElements:
            return "Delete Blank Elements"
        case .generateProposals:
            return "Generate Proposals"
        case .refreshContext:
            return "Refresh Context"
        case .generateShotList:
            return "Generate Shot List"
        case .generateBoards:
            return "Generate Boards"
        case .showNavigator:
            return "Show Navigator"
        case .showOutline:
            return "Show Outline"
        case .showSearch:
            return "Show Search"
        case .showFormat:
            return "Show Format"
        case .showTitlePage:
            return "Show Title Page"
        case .showBreakdown:
            return "Show Breakdown"
        case .showBoards:
            return "Show Boards"
        case .showContext:
            return "Show Context"
        case .showReports:
            return "Show Reports"
        case .showExports:
            return "Show Exports"
        case .showEditSpine:
            return "Show Edit Spine"
        case .showActivity:
            return "Show Activity"
        case .showSnapshots:
            return "Show Snapshots"
        case .createSnapshot:
            return "Create Snapshot"
        case .showNotes:
            return "Show Notes"
        case .addScriptNote:
            return "Add Script Note"
        }
    }

    var subtitle: String {
        switch self {
        case .newScreenplay, .open, .save, .saveAs, .exportPDF:
            return "File"
        case .focusMode, .contextInspector:
            return "Workspace"
        case .cleanScript, .deleteBlankElements:
            return "Format"
        case .generateProposals:
            return "Current mode"
        case .refreshContext:
            return "Production context"
        case .generateShotList:
            return "Selected scene"
        case .generateBoards, .showBoards:
            return "Boards"
        case .showNavigator, .showSearch, .showFormat, .showTitlePage:
            return "Script"
        case .showOutline:
            return "Outline"
        case .showBreakdown:
            return "Shot"
        case .showContext, .showReports:
            return "Context"
        case .showExports, .showEditSpine:
            return "Edit"
        case .showActivity, .showSnapshots, .createSnapshot, .showNotes, .addScriptNote:
            return "Workflow"
        }
    }

    var systemImage: String {
        switch self {
        case .newScreenplay:
            return "plus"
        case .open:
            return "folder"
        case .save, .saveAs:
            return "square.and.arrow.down"
        case .exportPDF:
            return "doc.richtext"
        case .focusMode:
            return "scope"
        case .contextInspector:
            return "sidebar.right"
        case .cleanScript:
            return "checklist"
        case .deleteBlankElements:
            return "trash"
        case .generateProposals:
            return "sparkles.rectangle.stack"
        case .refreshContext:
            return "arrow.clockwise"
        case .generateShotList:
            return "camera.viewfinder"
        case .generateBoards:
            return "rectangle.on.rectangle"
        case .showNavigator:
            return "list.bullet"
        case .showOutline:
            return "map"
        case .showSearch:
            return "magnifyingglass"
        case .showFormat:
            return "text.badge.checkmark"
        case .showTitlePage:
            return "doc.text"
        case .showBreakdown:
            return "list.bullet.rectangle"
        case .showBoards:
            return "rectangle.on.rectangle"
        case .showContext:
            return "rectangle.stack"
        case .showReports:
            return "doc.plaintext"
        case .showExports:
            return "square.and.arrow.up"
        case .showEditSpine:
            return "timeline.selection"
        case .showActivity:
            return "clock.arrow.circlepath"
        case .showSnapshots:
            return "tray.full"
        case .createSnapshot:
            return "camera.badge.clock"
        case .showNotes:
            return "note.text"
        case .addScriptNote:
            return "note.text.badge.plus"
        }
    }

    var searchableText: String {
        "\(title) \(subtitle) \(rawValue)"
    }
}

enum ScreenplayOSTokens {
    enum Radius {
        static let control: CGFloat = 3
        static let panel: CGFloat = 4
        static let page: CGFloat = 2
    }

    enum Spacing {
        static let hairline: CGFloat = 1
        static let compact: CGFloat = 6
        static let regular: CGFloat = 10
        static let panelInset: CGFloat = 12
    }

    enum Control {
        static let compactHeight: CGFloat = 24
        static let regularHeight: CGFloat = 30
        static let iconSize: CGFloat = 15
    }

    enum Typography {
        static let inspector = Font.system(size: 12)
        static let panelTitle = Font.system(size: 13, weight: .semibold)
        static let status = Font.caption
    }

    enum Palette {
        static let appBackground = Color(nsColor: .windowBackgroundColor)
        static let workspaceBackground = Color(nsColor: .underPageBackgroundColor)
        static let panelBackground = Color(nsColor: .controlBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let selected = Color.accentColor
    }
}
