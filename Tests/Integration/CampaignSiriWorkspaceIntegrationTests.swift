import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

// Copied into ScreenplayEditorTests only by the detached-tree integration runner.
// The Campaign branch deliberately does not compile against unmerged PR3 types.
@Suite("Campaign and Siri integration")
@MainActor
struct CampaignSiriWorkspaceIntegrationTests {
    private let pendingKey = "ScreenplayOS.PendingSiriWorkspace"

    private func withEnvironment(_ body: (ScreenplayViewModel, URL, UserDefaults) throws -> Void) throws {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "CampaignSiriIntegrationTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = ScreenplayViewModel(loadInitialDocument: false, autosaveDirectory: root,
                                        preferences: preferences, continuityBibleRoot: root,
                                        takeRoot: root, editAudioRoot: root)
        model.newDocument()
        try body(model, root, preferences)
    }

    @Test(arguments: SiriWorkspaceChoice.allCases)
    func allFiveWorkspacesLeaveTheDocumentAndCampaignBytesUnchanged(choice: SiriWorkspaceChoice) throws {
        try withEnvironment { model, root, preferences in
            model.save()
            let document = try #require(model.document)
            let file = try #require(model.saveURL)
            let documentBytes = try Data(contentsOf: file)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: root)
            session.updateDraft { $0.brief.brand = "Private brand"; $0.brief.objective = "Private scope" }
            let campaignFile = try CampaignWorkspaceStore.url(projectID: document.project.id, root: root)
            let campaignBytes = try Data(contentsOf: campaignFile)
            let ledger = session.ledger
            let canUndo = model.canUndo, canRedo = model.canRedo, dirty = model.hasUnsavedChanges

            SiriWorkspaceNavigation.request(choice, preferences: preferences)
            #expect(preferences.string(forKey: pendingKey) == choice.rawValue)
            #expect(SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == choice.workflowMode)
            #expect(model.document == document)
            #expect(model.canUndo == canUndo && model.canRedo == canRedo && model.hasUnsavedChanges == dirty)
            #expect(try Data(contentsOf: file) == documentBytes)
            #expect(try Data(contentsOf: campaignFile) == campaignBytes)
            #expect(session.ledger == ledger)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
        }
    }

    @Test func campaignRejectsAndClearsRequestsWithoutChangingSelectionOrReplayingAfterClose() throws {
        try withEnvironment { model, _, preferences in
            let document = model.document, selection = model.selectedObject
            let selectedElementID = model.selectedElementID
            model.campaignPresented = true
            for choice in SiriWorkspaceChoice.allCases {
                SiriWorkspaceNavigation.request(choice, preferences: preferences)
                #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
                #expect(model.workflowMode == .writing)
                #expect(model.selectedObject == selection && model.selectedElementID == selectedElementID)
                #expect(model.campaignPresented)
                #expect(model.document == document)
                #expect(preferences.string(forKey: pendingKey) == nil)
            }
            // A newer explicit Go to Source choice must win, including when the
            // user closes/reopens the campaign panel after a blocked request.
            model.setWorkflowMode(.directing)
            model.campaignPresented = false
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .directing)
            model.campaignPresented = true
            model.campaignPresented = false
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .directing)
            SiriWorkspaceNavigation.request(.boards, preferences: preferences)
            #expect(SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .boards)
            #expect(model.document == document)
        }
    }

    enum BlockingPresentation: CaseIterable, Sendable {
        case titlePage, dialogue, continuity, boardGeneration, consent, costs
        case packagePreview, packageEditor, convertedCopyReceipt, sourceAlert
    }

    @Test(arguments: BlockingPresentation.allCases)
    func otherKnownPresentationsRejectNavigation(presentation: BlockingPresentation) throws {
        try withEnvironment { model, root, preferences in
            switch presentation {
            case .titlePage: model.titlePagePresented = true
            case .dialogue: model.dialogueAssistantPresented = true
            case .continuity: model.continuityBiblePresented = true
            case .boardGeneration:
                model.boardGenerationSnapshot = try #require(BoardGenerationSnapshot(model: model, shot: .init(label: "Fixture")))
            case .consent:
                let request = GenerationRequestSnapshot(prompt: "Offline fixture only")
                let job = GenerationJobRecord(id: UUID(), projectID: try #require(model.document?.screenplay.id),
                    capability: .text, providerID: "mock", modelID: "fixture-v1",
                    target: .init(kind: .scene, id: UUID(), sourceRevision: String(repeating: "a", count: 64)),
                    request: request, requestSHA256: try request.sha256(),
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
                model.generationConsentPreview = GenerationConsentPreview(job: job)
            case .costs:
                model.generationCostLedger = try GenerationCostLedger(ledger: .init(projectID: try #require(model.document?.screenplay.id), jobs: []))
            case .packagePreview:
                model.packagePreview = PackagePreview(title: "Fixture", filename: "fixture.screenplay", paragraphs: [], boards: [])
            case .packageEditor:
                model.packageEditor = try PackageEditor.newPackage(directory: root.appendingPathComponent("Package"),
                    recoveryDirectory: root.appendingPathComponent("PackageRecovery"))
            case .convertedCopyReceipt:
                model.convertedCopyReceipt = .init(destination: "fixture.screenplay", sourceSHA256: String(repeating: "b", count: 64),
                    projectRevision: "fixture", payloadFiles: 0, mediaAttachments: 0)
            case .sourceAlert: model.sourceNavigationProblem = "Fixture missing source"
            }
            let document = model.document, selection = model.selectedObject
            #expect(SiriWorkspaceNavigation.navigationIsBlocked(model: model, nativeModalIsOpen: false))
            SiriWorkspaceNavigation.request(.edit, preferences: preferences)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .writing && model.selectedObject == selection)
            #expect(model.document == document)
            #expect(preferences.string(forKey: pendingKey) == nil)
        }
    }

    @Test func nativeSaveOrImportModalRejectsAndDoesNotReplay() throws {
        try withEnvironment { model, _, preferences in
            let document = model.document
            SiriWorkspaceNavigation.request(.edit, preferences: preferences)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: true))
            #expect(model.workflowMode == .writing && model.document == document)
            #expect(preferences.string(forKey: pendingKey) == nil)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .writing)
        }
    }

    @Test func malformedRequestIsClearedEvenWhileCampaignIsOpen() throws {
        try withEnvironment { model, _, preferences in
            model.campaignPresented = true
            preferences.set("erase-film", forKey: pendingKey)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(preferences.string(forKey: pendingKey) == nil)
            #expect(model.workflowMode == .writing && model.campaignPresented)
        }
    }

    @Test func latestUnconsumedRequestWinsWithoutCreativePayload() throws {
        try withEnvironment { model, _, preferences in
            SiriWorkspaceNavigation.request(.outline, preferences: preferences)
            SiriWorkspaceNavigation.request(.boards, preferences: preferences)
            #expect(preferences.string(forKey: pendingKey) == "boards")
            #expect(SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
            #expect(model.workflowMode == .boards)
            #expect(!SiriWorkspaceNavigation.consume(model: model, preferences: preferences, nativeModalIsOpen: false))
        }
    }
}
