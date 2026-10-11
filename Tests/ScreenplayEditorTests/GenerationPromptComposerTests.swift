import Foundation
import Testing
@testable import ScreenplayDomain

@Suite("Grounded generation prompt composition")
struct GenerationPromptComposerTests {
    let projectID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
    let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func composesScriptShotAndBibleWithFrozenConsentProvenance() throws {
        let heading = ScreenplayElement(type: .sceneHeading, text: "INT. WORKSHOP - NIGHT", spineID: "S001")
        let action = ScreenplayElement(type: .action, text: "MARTA raises the silver locket.")
        let cue = ScreenplayElement(type: .character, text: "MARTA")
        let dialogue = ScreenplayElement(type: .dialogue, text: "It remembers us.")
        let shot = Shot(
            sceneSpineID: "S001", shotNumber: 2, label: "S001-SH002 Close on MARTA",
            setup: .coverage, sourceRefs: [.init(screenplayElementID: action.id)], notes: "Hold on the locket."
        )
        let character = ContinuityBibleEntry(
            id: UUID(uuidString: "92000000-0000-0000-0000-000000000002")!, kind: .character,
            name: "MARTA", linkedElementIDs: [cue.id], visualNotes: "Weathered blue coat.",
            negativeConstraints: ["change facial proportions"], performerClassification: .realPerformer
        )
        let location = ContinuityBibleEntry(
            id: UUID(uuidString: "93000000-0000-0000-0000-000000000003")!, kind: .location,
            name: "WORKSHOP", linkedElementIDs: [heading.id], description: "Candlelit timber room."
        )
        let consent = PerformerConsentRecord(
            id: UUID(uuidString: "94000000-0000-0000-0000-000000000004")!,
            characterEntryID: character.id, performerName: "Actor",
            scopes: [.likenessGeneration], validFrom: instant.addingTimeInterval(-60),
            expiresAt: instant.addingTimeInterval(60), recordedAt: instant.addingTimeInterval(-60)
        )
        let ledger = ContinuityBibleLedger(
            projectID: projectID, entries: [location, character], consentRecords: [consent]
        )
        let elements = [heading, action, cue, dialogue]
        let first = try GenerationPromptComposer.compose(
            capability: .image, instruction: "Create one restrained storyboard frame.",
            targetKind: .shot, targetID: shot.id, sceneElements: elements, shot: shot,
            continuity: ledger, projectID: projectID, parameters: ["aspect_ratio": "16:9"],
            evaluatedAt: instant
        )
        let second = try GenerationPromptComposer.compose(
            capability: .image, instruction: "Create one restrained storyboard frame.",
            targetKind: .shot, targetID: shot.id, sceneElements: elements, shot: shot,
            continuity: ledger, projectID: projectID, parameters: ["aspect_ratio": "16:9"],
            evaluatedAt: instant
        )

        #expect(first == second)
        #expect(first.request.prompt.contains("COVERED SCREENPLAY"))
        #expect(first.request.prompt.contains("Hold on the locket."))
        #expect(first.request.prompt.contains("Weathered blue coat."))
        #expect(first.request.prompt.contains("Do not: change facial proportions"))
        #expect(first.request.continuityEntryIDs == [character.id, location.id])
        #expect(first.request.consentRecordIDs == [consent.id])
        #expect(first.target.sourceRevision.count == 64)
    }

    @Test func likenessAndVoiceFailClosedButTextCompositionDoesNotClaimThoseRights() throws {
        let cue = ScreenplayElement(type: .character, text: "MARTA")
        let character = ContinuityBibleEntry(
            kind: .character, name: "MARTA", linkedElementIDs: [cue.id],
            performerClassification: .realPerformer
        )
        let ledger = ContinuityBibleLedger(projectID: projectID, entries: [character])

        for capability in [GenerationCapability.image, .video, .voice] {
            #expect(throws: ContinuityBibleError.consentRequired) {
                try GenerationPromptComposer.compose(
                    capability: capability, instruction: "Generate.", targetKind: .scene,
                    targetID: UUID(), sceneElements: [cue], continuity: ledger,
                    projectID: projectID, evaluatedAt: instant
                )
            }
        }
        let text = try GenerationPromptComposer.compose(
            capability: .text, instruction: "Suggest dialogue.", targetKind: .dialogueLine,
            targetID: cue.id, sceneElements: [cue], continuity: ledger,
            projectID: projectID, evaluatedAt: instant
        )
        #expect(text.request.consentRecordIDs.isEmpty)
    }

    @Test func legacyRequestDecodesWithoutNewProvenanceArrays() throws {
        let json = Data(#"{"prompt":"Legacy","references":[],"parameters":{}}"#.utf8)
        let request = try JSONDecoder().decode(GenerationRequestSnapshot.self, from: json)
        #expect(request.continuityEntryIDs.isEmpty)
        #expect(request.consentRecordIDs.isEmpty)
    }
}
