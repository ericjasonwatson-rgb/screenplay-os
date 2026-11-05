import AppKit
import Foundation
import SwiftUI
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Persistent pending production image jobs")
@MainActor
struct ProductionImagePendingJobsSheetTests {
    @Test func unsentRequestsCanBeReviewedAndCancelledAfterControllerReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let location = root.appendingPathComponent("jobs.json")
        let request = GenerationRequestSnapshot(
            prompt: "Paint from this approved storyboard",
            parameters: ["workflow": "production_image_from_approved_board"])
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let job = GenerationJobRecord(
            id: UUID(), projectID: projectID, capability: .image,
            providerID: "openai", modelID: "gpt-image-1.5",
            target: GenerationTarget(
                kind: .board, id: UUID(),
                sourceRevision: String(repeating: "a", count: 64)),
            request: request, requestSHA256: try request.sha256(),
            status: .awaitingConsent, createdAt: created, updatedAt: created)
        let controller = try GenerationJobController(projectID: projectID, storageURL: location)
        try await controller.add(job)
        let reloaded = try GenerationJobController(projectID: projectID, storageURL: location)
        let recovered = await reloaded.snapshot()
        #expect(recovered.jobs.count == 1)
        #expect(recovered.jobs[0].status == .awaitingConsent)
        try await reloaded.cancel(jobID: job.id, at: created.addingTimeInterval(5))
        let cancelled = await reloaded.snapshot()
        #expect(cancelled.jobs[0].status == .cancelled)
        #expect(cancelled.jobs[0].submittedAt == nil)
    }

    @Test func pendingSheetRendersWithoutTriggeringProvider() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "PendingProductionImages.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let model = ScreenplayViewModel(loadInitialDocument: false,
            autosaveDirectory: root, preferences: preferences, takeRoot: root)
        model.newDocument()
        let original = model.document
        let host = NSHostingView(rootView: ProductionImagePendingJobsSheet(
            model: model, dismiss: {}))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(model.document == original)
    }
}
