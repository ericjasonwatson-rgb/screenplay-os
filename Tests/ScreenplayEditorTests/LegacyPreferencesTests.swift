import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Bundle identifier preference compatibility")
struct LegacyPreferencesTests {
    @Test func copiesOnlyKnownKeysAndNeverOverwritesNewPreferences() throws {
        let suite = "LegacyPreferencesTests.\(UUID())"
        let current = try #require(UserDefaults(suiteName: suite))
        defer { current.removePersistentDomain(forName: suite) }
        current.set(false, forKey: "editSpine.showDurationEstimates")
        let old: [String: Any] = [
            "ScreenplayOSRecentDocuments": ["/tmp/Existing.screenplay"],
            "editSpine.showDurationEstimates": true,
            "dialogue.provider": "openai",
            "unrelated.secret": "must-not-copy"
        ]
        LegacyPreferences.copyMissing(from: old, to: current)
        #expect(current.stringArray(forKey: "ScreenplayOSRecentDocuments") == ["/tmp/Existing.screenplay"])
        #expect(current.bool(forKey: "editSpine.showDurationEstimates") == false)
        #expect(current.string(forKey: "dialogue.provider") == "openai")
        #expect(current.object(forKey: "unrelated.secret") == nil)
        current.set(["/tmp/New.screenplay"], forKey: "ScreenplayOSRecentDocuments")
        LegacyPreferences.copyMissing(from: old, to: current)
        #expect(current.stringArray(forKey: "ScreenplayOSRecentDocuments") == ["/tmp/New.screenplay"])
    }
}
