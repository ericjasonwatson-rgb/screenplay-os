import Foundation
import Testing
@testable import ScreenplayDomain
@testable import ScreenplayOSApp

struct ContinuityBibleTests {
    @Test func extractsCharactersLocationsAndRecurringPropsWithEvidence() {
        let elements = [
            ScreenplayElement(type: .sceneHeading, text: "INT./EXT. CAFÉ ÉTOILE – DAY", spineID: "S001"),
            ScreenplayElement(type: .action, text: "MARTA lifts the SILVER LOCKET from the table."),
            ScreenplayElement(type: .character, text: "MARTA (V.O.)"),
            ScreenplayElement(type: .dialogue, text: "I remember."),
            ScreenplayElement(type: .sceneHeading, text: "EXT. RIVER ROAD - NIGHT", spineID: "S002"),
            ScreenplayElement(type: .action, text: "The SILVER LOCKET catches moonlight."),
            ScreenplayElement(type: .character, text: "MARTA (CONT'D) (O.S.)"),
        ]
        let screenplay = Screenplay(metadata: .init(title: "Test"), elements: elements)
        let proposals = ContinuityExtractor.proposals(from: screenplay)

        let marta = proposals.first { $0.kind == .character && $0.name == "MARTA" }
        #expect(marta?.occurrenceCount == 2)
        #expect(marta?.firstAppearance?.elementIndex == 2)
        #expect(marta?.evidence.last?.sceneHeading == "EXT. RIVER ROAD - NIGHT")
        #expect(proposals.contains { $0.kind == .location && $0.name == "CAFÉ ÉTOILE" })
        #expect(proposals.contains { $0.kind == .location && $0.name == "RIVER ROAD" })
        let prop = proposals.first { $0.kind == .prop && $0.name == "SILVER LOCKET" }
        #expect(prop?.occurrenceCount == 2)
        #expect(prop?.evidence.map(\.exactText) == [elements[1].text, elements[5].text])
    }

    @Test func emptyScriptAndOrdinaryCapitalizationDoNotInventProps() {
        let empty = Screenplay(metadata: .init(title: "Empty"))
        #expect(ContinuityExtractor.proposals(from: empty).isEmpty)

        let screenplay = Screenplay(metadata: .init(title: "Plain"), elements: [
            .init(type: .sceneHeading, text: "INT. HOME - DAY"),
            .init(type: .action, text: "Sarah sets a blue cup down."),
            .init(type: .action, text: "She picks the blue cup up.")
        ])
        #expect(!ContinuityExtractor.proposals(from: screenplay).contains { $0.kind == .prop })
    }

    @Test func adoptionIsExplicitRenameableAndUndoable() throws {
        let element = ScreenplayElement(type: .character, text: "MOM")
        let proposal = ContinuityProposal(
            kind: .character, name: "MOM", aliases: ["SARAH"],
            evidence: [.init(elementID: element.id, elementIndex: 0, sceneHeadingID: nil, sceneHeading: nil, exactText: "MOM")]
        )
        var ledger = ContinuityBibleLedger(projectID: UUID(), proposals: [proposal])
        #expect(ledger.entries.isEmpty)
        #expect(ledger.proposals[0].status == .proposed)

        let undo = try ledger.adopt(proposalID: proposal.id, as: "Sarah")
        #expect(ledger.entries.count == 1)
        #expect(ledger.entries[0].name == "Sarah")
        #expect(ledger.entries[0].aliases == ["SARAH"])
        #expect(ledger.entries[0].linkedElementIDs == [element.id])
        #expect(ledger.entries[0].performerClassification == .fictional)
        #expect(ledger.proposals[0].status == .adopted)

        try ledger.undo(undo)
        #expect(ledger.entries.isEmpty)
        #expect(ledger.proposals[0].status == .proposed)
    }

    @Test func locationParserHandlesCommonHeadingVariants() {
        #expect(ContinuityExtractor.sceneLocation("INT. OFFICE - DAY") == "OFFICE")
        #expect(ContinuityExtractor.sceneLocation("EXT./INT. CAR — MOVING") == "CAR")
        #expect(ContinuityExtractor.sceneLocation("I/E. TRAIN – NIGHT") == "TRAIN")
        #expect(ContinuityExtractor.characterBaseName("JOSÉ (V.O.) (CONT'D)") == "JOSÉ")
    }

    @Test func mergeRejectAndUndoPreserveReviewState() throws {
        let first = ContinuityProposal(kind: .character, name: "MOM", evidence: [
            .init(elementID: UUID(), elementIndex: 1, sceneHeadingID: nil, sceneHeading: nil, exactText: "MOM")
        ])
        let second = ContinuityProposal(kind: .character, name: "SARAH", evidence: [
            .init(elementID: UUID(), elementIndex: 4, sceneHeadingID: nil, sceneHeading: nil, exactText: "SARAH")
        ])
        var ledger = ContinuityBibleLedger(projectID: UUID(), proposals: [first, second])
        let mergeUndo = try ledger.merge(proposalID: first.id, into: second.id)
        #expect(ledger.proposals[0].status == .merged)
        #expect(ledger.proposals[0].mergedIntoID == second.id)
        #expect(ledger.proposals[1].aliases == ["MOM"])
        #expect(ledger.proposals[1].occurrenceCount == 2)
        try ledger.undo(mergeUndo)
        #expect(ledger.proposals == [first, second])

        let rejectUndo = try ledger.reject(proposalID: first.id)
        #expect(ledger.proposals[0].status == .rejected)
        try ledger.undo(rejectUndo)
        #expect(ledger.proposals == [first, second])
    }

    @Test func ledgerPersistsAtomicallyAndRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("continuity.json")
        let ledger = ContinuityBibleLedger(projectID: UUID(), proposals: [
            .init(kind: .location, name: "RIVER", evidence: [
                .init(elementID: UUID(), elementIndex: 0, sceneHeadingID: nil, sceneHeading: nil, exactText: "EXT. RIVER - DAY")
            ])
        ])
        try ContinuityBibleFileStore.write(ledger, to: url)
        #expect(try ContinuityBibleFileStore.read(from: url) == ledger)

        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: ContinuityBibleError.invalidFile) { try ContinuityBibleFileStore.read(from: link) }
    }

    @MainActor @Test func reviewAdoptionPersistsWithoutChangingTheScreenplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScreenplayViewModel(loadInitialDocument: false, continuityBibleRoot: root)
        model.newDocument()
        let projectID = try #require(model.document?.screenplay.id)
        let heading = try #require(model.document?.screenplay.elements.first)
        model.editText(
            id: heading.id, text: "INT. KITCHEN - DAY",
            before: NSRange(location: 0, length: 0),
            after: NSRange(location: 18, length: 0), groupable: false
        )
        let scriptBeforeReview = model.document?.screenplay
        model.scanContinuityBible()
        let proposal = try #require(model.continuityBible?.proposals.first { $0.kind == .location })
        model.adoptContinuityProposal(proposal.id, name: "Family Kitchen")

        #expect(model.document?.screenplay == scriptBeforeReview)
        #expect(model.continuityBible?.entries.first?.name == "Family Kitchen")
        let url = try ContinuityBibleWorkflow.storageURL(projectID: projectID, root: root)
        #expect(try ContinuityBibleFileStore.read(from: url) == model.continuityBible)

        model.undoContinuityReviewAction()
        #expect(model.continuityBible?.entries.isEmpty == true)
        #expect(model.continuityBible?.proposals.first?.status == .proposed)
    }

    @Test func realPerformerGenerationFailsClosedAcrossExpiryAndRevocation() throws {
        let entry = ContinuityBibleEntry(kind: .character, name: "SARAH", performerClassification: .realPerformer)
        let now = Date(timeIntervalSince1970: 2_000_000)
        var ledger = ContinuityBibleLedger(projectID: UUID(), entries: [entry])
        #expect(throws: ContinuityBibleError.consentRequired) {
            try ContinuityGenerationGate.authorize(entryID: entry.id, scope: .likenessGeneration, at: now, ledger: ledger)
        }

        let record = PerformerConsentRecord(
            characterEntryID: entry.id, performerName: "Sarah Actor",
            scopes: [.likenessGeneration], validFrom: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(60), recordedAt: now.addingTimeInterval(-60)
        )
        try ledger.addConsent(record)
        #expect(try ContinuityGenerationGate.authorize(
            entryID: entry.id, scope: .likenessGeneration, at: now, ledger: ledger
        ) == [record.id])
        #expect(throws: ContinuityBibleError.consentRequired) {
            try ContinuityGenerationGate.authorize(entryID: entry.id, scope: .voiceCloning, at: now, ledger: ledger)
        }
        #expect(throws: ContinuityBibleError.consentRequired) {
            try ContinuityGenerationGate.authorize(entryID: entry.id, scope: .likenessGeneration,
                                                   at: now.addingTimeInterval(61), ledger: ledger)
        }
        try ledger.revokeConsent(recordID: record.id, at: now)
        #expect(throws: ContinuityBibleError.consentRequired) {
            try ContinuityGenerationGate.authorize(entryID: entry.id, scope: .likenessGeneration, at: now, ledger: ledger)
        }
    }

    @Test func fictionalCharactersNeedNoPerformerConsentAndLegacyLedgersDecode() throws {
        let entry = ContinuityBibleEntry(kind: .character, name: "MARTA", performerClassification: .fictional)
        let ledger = ContinuityBibleLedger(projectID: UUID(), entries: [entry])
        #expect(try ContinuityGenerationGate.authorize(
            entryID: entry.id, scope: .voiceCloning, at: Date(), ledger: ledger
        ).isEmpty)

        let encoded = try JSONEncoder().encode(ledger)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "consent_records")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ContinuityBibleLedger.self, from: legacy).consentRecords.isEmpty)

        let unclassified = ContinuityBibleEntry(kind: .character, name: "UNKNOWN")
        let unclassifiedLedger = ContinuityBibleLedger(projectID: UUID(), entries: [unclassified])
        #expect(throws: ContinuityBibleError.invalidConsent) {
            try ContinuityGenerationGate.authorize(
                entryID: unclassified.id, scope: .likenessGeneration,
                at: Date(), ledger: unclassifiedLedger
            )
        }
    }
}
