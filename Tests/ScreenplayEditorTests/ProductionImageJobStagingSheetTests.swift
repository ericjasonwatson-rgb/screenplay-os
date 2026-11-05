import AppKit
import Foundation
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Production image job staging presentation")
@MainActor
struct ProductionImageJobStagingSheetTests {
    @Test func reviewOnlyScreenRendersWithoutMutatingJobLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ProductionStageUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: root, preferences: defaults, takeRoot: root)
        model.newDocument()
        let before = model.document
        let host = NSHostingView(rootView: ProductionImageJobStagingSheet(
            model: model, boardID: UUID(), dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 620)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(model.document == before)
        // Rendering alone does not stage, consent to or send a provider job.
    }
}
