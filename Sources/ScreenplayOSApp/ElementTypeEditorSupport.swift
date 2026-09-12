import ScreenplayDomain

extension ElementType {
    static var editorTypes: [ElementType] {
        [.sceneHeading, .action, .character, .dialogue, .parenthetical, .transition, .shot, .general]
    }

    var displayName: String {
        switch self {
        case .sceneHeading:
            return "Scene Heading"
        case .action:
            return "Action"
        case .character:
            return "Character"
        case .dialogue:
            return "Dialogue"
        case .parenthetical:
            return "Parenthetical"
        case .transition:
            return "Transition"
        case .general:
            return "General"
        case .shot:
            return "Shot"
        case .pageBreak:
            return "Page Break"
        }
    }
}
