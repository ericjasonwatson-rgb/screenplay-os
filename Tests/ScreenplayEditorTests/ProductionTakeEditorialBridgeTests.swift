import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Generated Take to editorial interchange")
struct ProductionTakeEditorialBridgeTests {
    private func generatedTake(shotID: UUID, boardID: UUID, takeID: UUID) -> Take {
        let prompt = "Preserve the approved Cat Island board, high quality."
        let digest = SHA256.hash(data: Data(prompt.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return Take(
            id: takeID, shotID: shotID, boardFrameID: boardID,
            kind: .generatedImage,
            mediaURL: URL(fileURLWithPath: "/tmp/candidate.png"),
            sha256: String(repeating: "a", count: 64),
            durationSeconds: 2, status: .candidate,
            provenance: .init(source: .generationJob,
                generationJobID: UUID(), providerID: "openai",
                modelID: "gpt-image-1.5", prompt: prompt,
                promptSHA256: digest, generatedAt: Date(timeIntervalSince1970: 1700000000))
        )
    }

    @Test func twoOccurrencesKeepOneTakeAndSeparateEditorialIdentities() throws {
        let sceneID = UUID(), shotID = UUID(), boardID = UUID(), takeID = UUID()
        let take = generatedTake(shotID: shotID, boardID: boardID, takeID: takeID)
        let firstID = UUID(), secondID = UUID()
        let first = try ProductionTakeEditorialBridge.occurrence(
            id: firstID, sceneID: sceneID, shotID: shotID, boardID: boardID,
            take: take, relativeMediaPath: "Board Images/generated.png",
            startFrame: 0, durationFrames: 48, note: "First appearance")
        let second = try ProductionTakeEditorialBridge.occurrence(
            id: secondID, sceneID: sceneID, shotID: shotID, boardID: boardID,
            take: take, relativeMediaPath: "Board Images/generated.png",
            startFrame: 48, durationFrames: 48, note: "Repeat after reaction")
        let manifest = try MediaInterchangeManifest.make(
            [first, second], mediaExists: { _ in true })
        let restored = try MediaInterchangeManifest.read(
            MediaInterchangeManifest.json(manifest))
        #expect(restored == manifest)
        #expect(restored.occurrences.map(\.occurrenceID) == [firstID, secondID])
        #expect(restored.occurrences.allSatisfy {
            $0.takeID == takeID && $0.shotID == shotID &&
            $0.generationJobID == take.provenance.generationJobID &&
            $0.mediaSHA256 == take.sha256 &&
            $0.promptSHA256 == take.provenance.promptSHA256
        })

        let exported = try MediaTimelineOTIO.export(restored, projectName: "Offline Film")
        // Opt-in CI artifact produced by the real ScreenplayOS exporter.
        // Synthetic identifiers only; never a user's screenplay or media.
        if let capture = ProcessInfo.processInfo.environment["SCREENPLAYOS_OTIO_CAPTURE_PATH"] {
            try exported.write(to: URL(fileURLWithPath: capture), options: .atomic)
        }
        let json = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let stack = try #require(json["tracks"] as? [String: Any])
        let tracks = try #require(stack["children"] as? [[String: Any]])
        let clips = try #require(tracks[0]["children"] as? [[String: Any]])
        #expect(clips.count == 2)
        for (index, clip) in clips.enumerated() {
            let metadata = try #require(clip["metadata"] as? [String: Any])
            let ids = try #require(metadata["screenplayos"] as? [String: Any])
            #expect(ids["occurrence_id"] as? String ==
                [firstID, secondID][index].uuidString)
            #expect(ids["take_id"] as? String == takeID.uuidString)
            #expect(ids["shot_id"] as? String == shotID.uuidString)
            #expect(ids["board_id"] as? String == boardID.uuidString)
            #expect(ids["generation_job_id"] as? String ==
                take.provenance.generationJobID?.uuidString)
            #expect(ids["media_sha256"] as? String == take.sha256)
            #expect(ids["prompt_sha256"] as? String == take.provenance.promptSHA256)
        }
        #expect(take.status == .candidate)
        #expect(take.durationSeconds == 2)
    }

    @Test func externalTimingChangeIsReviewOnlyButProvenanceChangeFailsClosed() throws {
        let sceneID = UUID(), shotID = UUID(), boardID = UUID()
        let take = generatedTake(shotID: shotID, boardID: boardID, takeID: UUID())
        let id = UUID()
        let base = try ProductionTakeEditorialBridge.occurrence(
            id: id, sceneID: sceneID, shotID: shotID, boardID: boardID,
            take: take, relativeMediaPath: "Board Images/generated.png",
            startFrame: 0, durationFrames: 48, note: "Current")
        let baseline = try MediaInterchangeManifest.make([base], mediaExists: { _ in true })
        let proposed = MediaInterchangeManifest.Occurrence(
            occurrenceID: base.occurrenceID,
            sceneID: base.sceneID, shotID: base.shotID,
            boardID: base.boardID, mediaPath: "Board Images/alternate.mov",
            startFrame: 0, durationFrames: 52, note: "Director review",
            takeID: base.takeID, generationJobID: base.generationJobID,
            mediaSHA256: base.mediaSHA256, promptSHA256: base.promptSHA256)
        let edited = try MediaInterchangeManifest.make([proposed], mediaExists: { _ in true })
        let review = try ProductionTakeEditorialBridge.compareExternalProposal(
            baseline: baseline, edited: edited)
        #expect(review.changes.contains {
            $0.occurrenceID == id &&
            $0.kind == .timing(fromStart: 0, fromDuration: 48, toStart: 0, toDuration: 52)
        })
        #expect(review.changes.contains {
            $0.occurrenceID == id &&
            $0.kind == .media(from: "Board Images/generated.png",
                              to: "Board Images/alternate.mov")
        })
        #expect(baseline.occurrences == [base])

        let forged = MediaInterchangeManifest.Occurrence(
            occurrenceID: id, sceneID: sceneID, shotID: shotID,
            boardID: boardID, mediaPath: base.mediaPath,
            startFrame: 0, durationFrames: 48, note: "Current",
            takeID: UUID(), generationJobID: base.generationJobID,
            mediaSHA256: base.mediaSHA256, promptSHA256: base.promptSHA256)
        #expect(throws: MediaEditReview.ReviewError.sourceTakeChanged(id)) {
            try ProductionTakeEditorialBridge.compareExternalProposal(
                baseline: baseline,
                edited: MediaInterchangeManifest.make([forged], mediaExists: { _ in true }))
        }
    }

    @Test func missingMediaKeepsIdentityAndNeverExportsPrivateAbsolutePath() throws {
        let scene = UUID(), shot = UUID(), board = UUID()
        let take = generatedTake(shotID: shot, boardID: board, takeID: UUID())
        let item = try ProductionTakeEditorialBridge.occurrence(
            id: UUID(), sceneID: scene, shotID: shot, boardID: board,
            take: take, relativeMediaPath: "Board Images/not-present.png",
            startFrame: 0, durationFrames: 48, note: "Missing locally")
        let manifest = try MediaInterchangeManifest.make([item], mediaExists: { _ in false })
        #expect(manifest.missingMedia.count == 1)
        let otio = try MediaTimelineOTIO.export(manifest, projectName: "Offline review")
        #expect(String(decoding: otio, as: UTF8.self).contains("MissingReference.1"))
        #expect(!String(decoding: otio, as: UTF8.self).contains("/tmp/candidate.png"))
        #expect(throws: ProductionTakeEditorialBridge.Failure.unsafeMedia) {
            try ProductionTakeEditorialBridge.occurrence(
                id: UUID(), sceneID: scene, shotID: shot, boardID: board,
                take: take, relativeMediaPath: "../private/candidate.png",
                startFrame: 0, durationFrames: 48, note: "")
        }
    }
}
