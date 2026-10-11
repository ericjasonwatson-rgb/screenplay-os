import Foundation
import Testing
@testable import ScreenplayDomain

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
}
