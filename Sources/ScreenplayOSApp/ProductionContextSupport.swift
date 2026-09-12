import SwiftUI
import ScreenplayDomain

extension ProductionEntityKind {
    var displayName: String {
        switch self {
        case .character:
            return "Characters"
        case .location:
            return "Locations"
        case .prop:
            return "Props"
        case .wardrobe:
            return "Wardrobe"
        case .visualEffect:
            return "VFX"
        case .question:
            return "Questions"
        }
    }
}

extension ProductionEntityStatus {
    var displayName: String {
        switch self {
        case .suggested:
            return "Suggested"
        case .accepted:
            return "Accepted"
        case .ignored:
            return "Ignored"
        }
    }

    var color: Color {
        switch self {
        case .suggested:
            return .secondary
        case .accepted:
            return .green
        case .ignored:
            return .orange
        }
    }
}

extension ShotSetup {
    var displayName: String {
        switch self {
        case .establishing:
            return "Establishing"
        case .master:
            return "Master"
        case .coverage:
            return "Coverage"
        case .insert:
            return "Insert"
        case .visualEffect:
            return "VFX"
        }
    }
}

extension ShotStatus {
    var displayName: String {
        switch self {
        case .suggested:
            return "Suggested"
        case .selected:
            return "Selected"
        case .boarded:
            return "Boarded"
        case .shot:
            return "Shot"
        case .omitted:
            return "Omitted"
        }
    }
}

extension AIProposalWorkflow {
    var workflowMode: WorkflowMode {
        switch self {
        case .writing:
            return .writing
        case .outline:
            return .outline
        case .directing:
            return .directing
        case .boards:
            return .boards
        case .production:
            return .production
        case .edit:
            return .edit
        }
    }
}

extension AIProposalStatus {
    var displayName: String {
        switch self {
        case .suggested:
            return "Suggested"
        case .accepted:
            return "Accepted"
        case .rejected:
            return "Rejected"
        case .applied:
            return "Applied"
        }
    }

    var color: Color {
        switch self {
        case .suggested:
            return .secondary
        case .accepted:
            return .blue
        case .rejected:
            return .orange
        case .applied:
            return .green
        }
    }
}

extension AIProposalTarget {
    var displayLabel: String {
        if outlineBeatID != nil, let sceneSpineID {
            return "Outline beat -> Scene \(sceneSpineID)"
        }
        if outlineBeatID != nil {
            return "Outline beat"
        }
        if let sceneSpineID {
            return "Scene \(sceneSpineID)"
        }
        if screenplayElementID != nil {
            return "Screenplay line"
        }
        if shotID != nil {
            return "Shot"
        }
        if boardFrameID != nil {
            return "Board frame"
        }
        if contextRecordID != nil {
            return "Context record"
        }
        return "General"
    }
}

extension EditorialBeatStatus {
    static var editStatuses: [EditorialBeatStatus] {
        [.planned, .readyForEdit, .inEdit, .locked, .needsPickup, .cut]
    }

    var displayName: String {
        switch self {
        case .planned:
            return "Planned"
        case .readyForEdit:
            return "Ready for Edit"
        case .inEdit:
            return "In Edit"
        case .locked:
            return "Locked"
        case .shot:
            return "Shot"
        case .selected:
            return "Selected"
        case .needsPickup:
            return "Needs Pickup"
        case .cut:
            return "Cut"
        }
    }
}

extension EditorialMarkerCategory {
    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension EditClipSourceKind {
    var displayName: String {
        switch self {
        case .shotPlaceholder:
            return "Shot"
        case .boardFrame:
            return "Board"
        case .productionMedia:
            return "Media"
        case .generatedVideo:
            return "Generated"
        }
    }
}

extension EditClipStatus {
    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension ScriptNoteStatus {
    var displayName: String {
        switch self {
        case .open:
            return "Open"
        case .resolved:
            return "Resolved"
        }
    }
}

extension ActivityActor {
    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .proposal:
            return "Proposal"
        case .contextAssistant:
            return "Assistant"
        case .system:
            return "System"
        }
    }
}
