import AppIntents
import Foundation

/// A deliberately narrow first Siri/Shortcuts surface. It exposes workspace
/// navigation only; no screenplay text, project identity, or media is indexed.
enum SiriWorkspaceChoice: String, AppEnum, CaseIterable {
    case outline, script, shot, boards, edit

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "ScreenplayOS Workspace"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .outline: "Outline", .script: "Script", .shot: "Shot",
        .boards: "Boards", .edit: "Edit"
    ]

    var workflowMode: WorkflowMode {
        switch self {
        case .outline: return .outline
        case .script: return .writing
        case .shot: return .directing
        case .boards: return .boards
        case .edit: return .edit
        }
    }
}

@MainActor
enum SiriWorkspaceNavigation {
    static let notification = Notification.Name("ScreenplayOS.SiriWorkspaceRequested")
    private static let pendingKey = "ScreenplayOS.PendingSiriWorkspace"

    /// Only the requested mode name is stored in application preferences.
    /// No creative material, locations, or AI prompts enter Siri's payload.
    static func request(_ choice: SiriWorkspaceChoice, preferences: UserDefaults = .standard) {
        preferences.set(choice.rawValue, forKey: pendingKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    @discardableResult
    static func consume(model: ScreenplayViewModel, preferences: UserDefaults = .standard) -> Bool {
        guard let raw = preferences.string(forKey: pendingKey),
              let choice = SiriWorkspaceChoice(rawValue: raw) else {
            // Clear malformed requests so an old command cannot run unexpectedly.
            preferences.removeObject(forKey: pendingKey)
            return false
        }
        preferences.removeObject(forKey: pendingKey)
        model.setWorkflowMode(choice.workflowMode)
        return true
    }
}

/// Shows ScreenplayOS in its requested workspace. The app's existing command
/// performs navigation; Siri never writes a document or invokes AI generation.
struct OpenScreenplayWorkspaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open ScreenplayOS Workspace"
    static var description = IntentDescription("Open Outline, Script, Shot, Boards, or Edit in ScreenplayOS.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Workspace")
    var workspace: SiriWorkspaceChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriWorkspaceNavigation.request(workspace)
        return .result(dialog: "Opening the ScreenplayOS \(workspace.rawValue) workspace.")
    }
}
