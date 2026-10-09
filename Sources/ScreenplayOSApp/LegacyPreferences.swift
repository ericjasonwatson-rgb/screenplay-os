import Foundation

/// Changing the bundle ID must not hide the user's recent scripts or preferences.
/// Documents, recovery copies, and Keychain items are stored outside this domain.
enum LegacyPreferences {
    static let oldDomain = "dev.screenplayos.prototype"
    static let newDomain = "com.screenplayos.app"
    static let keys = [
        "ScreenplayOSRecentDocuments",
        "editSpine.showDurationEstimates",
        "dialogue.provider",
        "dialogue.model.openai",
        "dialogue.model.anthropic"
    ]

    static func copyMissing(from old: [String: Any], to defaults: UserDefaults) {
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    static func copyOnProductionLaunch(to defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier == newDomain,
              defaults === UserDefaults.standard,
              let old = defaults.persistentDomain(forName: oldDomain) else { return }
        copyMissing(from: old, to: defaults)
    }
}
