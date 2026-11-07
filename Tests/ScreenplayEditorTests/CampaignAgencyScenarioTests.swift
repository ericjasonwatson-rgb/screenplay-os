import CryptoKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

/// Synthetic agency work, not real Office compatibility or interactive UI acceptance.
/// Fixtures are source-controlled text and locate themselves in detached CI worktrees.
@Suite("Campaign synthetic agency scenarios", .serialized)
struct CampaignAgencyScenarioTests {
    private struct Corpus: Decodable {
        let version: Int
        let synthetic: Bool
        let fixtureCount: Int
        let fixtures: [Fixture]
    }

    private struct Fixture: Decodable {
        let name: String
        let filename: String
        let compressionMethod: Int
        let originalBase64: String
        let originalSHA256: String
        let expectedText: String?
        let extractedSHA256: String?
        let expectedLineCount: Int?
        let expectedFailure: String?

        var bytes: Data { get throws { try #require(Data(base64Encoded: originalBase64)) } }
    }

    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CampaignAgency/corpus.json")
        let result = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        #expect(result.version == 1)
        #expect(result.synthetic)
        #expect(result.fixtureCount == 16)
        #expect(result.fixtures.count == result.fixtureCount)
        #expect(Set(result.fixtures.map(\.name)).count == result.fixtureCount)
        return result
    }

    private func fixture(_ name: String) throws -> Fixture {
        try #require(corpus().fixtures.first { $0.name == name })
    }

    private func temporaryRoot() throws -> URL {
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func document() -> ScreenplayOSDocument {
        let screenplay = Screenplay(metadata: .init(title: "Synthetic Oat & Ember campaign"),
            elements: [.init(type: .action, text: "A carton stands beside a morning coffee.")])
        return ScreenplayOSDocument(project: .init(metadata: .init(title: "Synthetic agency scenario", author: "Test Author"),
            screenplayID: screenplay.id), screenplay: screenplay)
    }

    private func sourceURL(_ fixture: Fixture, root: URL) throws -> URL {
        let url = root.appendingPathComponent(fixture.filename)
        try fixture.bytes.write(to: url)
        return url
    }

    private func preview(_ name: String, root: URL) throws -> CampaignAgencyImport.Preview {
        try CampaignAgencyImport.read(sourceURL(fixture(name), root: root))
    }

    @MainActor
    private func importFixture(_ name: String, into session: CampaignWorkspaceSession, root: URL,
                               revising documentID: UUID? = nil) throws -> CampaignAgencyRevision {
        let input = try preview(name, root: root)
        try #require(session.importAgencyText(input, revisingDocumentID: documentID))
        return try #require(session.ledger.draft.agency?.revisions.last)
    }

    @MainActor
    private func review(_ revision: CampaignAgencyRevision, in session: CampaignWorkspaceSession, note: String) throws {
        try #require(session.reviewAgencyRevision(revision.id, reviewer: "Synthetic Producer", note: note))
    }

    @MainActor
    private func cite(_ revision: CampaignAgencyRevision, lines: ClosedRange<Int>,
                      kind: CampaignAgencyTargetKind, targetID: UUID, note: String,
                      in session: CampaignWorkspaceSession) throws {
        try #require(session.citeAgencyRevision(revision.id, firstLine: lines.lowerBound, lastLine: lines.upperBound,
            targetKind: kind, targetID: targetID, note: note))
    }

    @MainActor
    private func savedBytes(_ session: CampaignWorkspaceSession, root: URL) throws -> Data {
        try Data(contentsOf: CampaignWorkspaceStore.url(projectID: session.ledger.projectID, root: root))
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor @Test func fullAgencyPackHasExactExtractionAndPreviewNeverAdoptsScope() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = document(), originalDocument = doc
        let session = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        let target = CampaignDeliverable(name: "Manually authored placeholder", durationSeconds: 20)
        let assumption = CampaignAssumption(text: "Producer has not reconciled agency scope")
        session.updateDraft {
            $0.brief.brand = "Oat & Ember"; $0.brief.objective = "Introduce the oat drink"
            $0.deliverables = [target]; $0.assumptions = [assumption]
        }
        let accepted = try corpus().fixtures.filter { $0.expectedFailure == nil }
        #expect(accepted.count == 5)
        #expect(Set(accepted.map(\.compressionMethod)) == Set([0, 8]))
        for fixture in accepted {
            let beforePreview = session.ledger, beforeDisk = try savedBytes(session, root: root)
            let url = try sourceURL(fixture, root: root)
            let input = try CampaignAgencyImport.read(url)
            let text = try #require(fixture.expectedText)
            let origin = try #require(input.origin)
            #expect(input.filename == fixture.filename)
            #expect(Data(input.text.utf8) == Data(text.utf8))
            #expect(input.bytes == Data(text.utf8))
            #expect(digest(input.bytes) == fixture.extractedSHA256)
            #expect(origin.originalBytes == (try fixture.bytes))
            #expect(origin.originalSHA256 == fixture.originalSHA256)
            #expect(origin.originalSHA256 == digest(try fixture.bytes))
            #expect(origin.sections == [text])
            #expect(origin.extractor == "docx-body-text-v1")
            #expect(origin.notices.contains { $0.contains("not visual reading order") })
            #expect(origin.notices.contains { $0.contains("headers, footers") })
            #expect(!input.text.contains("FICTIONAL HEADER ONLY"))
            #expect(session.ledger == beforePreview)
            #expect(try savedBytes(session, root: root) == beforeDisk)
            // This covers the command boundary; dismissing a preview has no import to undo.
            #expect(try Data(contentsOf: url) == fixture.bytes)
            try #require(session.importAgencyText(input, revisingDocumentID: nil))
            let revision = try #require(session.ledger.draft.agency?.revisions.last)
            #expect(revision.sha256 == fixture.extractedSHA256)
            #expect(revision.lines.count == fixture.expectedLineCount)
            #expect(session.ledger.draft.deliverables == [target])
            #expect(session.ledger.draft.assumptions == [assumption])
            #expect(session.ledger.draft.agency?.reviews.isEmpty == true)
            #expect(session.ledger.draft.agency?.citations.isEmpty == true)
            #expect(session.ledger.baselines.isEmpty)
            #expect(session.ledger.decisions.isEmpty)
            #expect(doc == originalDocument)
        }
        let reopened = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger == session.ledger)
        #expect(!reopened.canUndoDraft)
    }

    @MainActor @Test func contradictoryDocumentsRequireHumanReconciliationBeforeRevisionAndApproval() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = document(), originalDocument = doc
        let session = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        let hero = CampaignDeliverable(name: "Hero film", durationSeconds: 30, aspectRatio: "16:9", market: "US + UK", language: "en-US")
        let social = CampaignDeliverable(name: "Social cutdown", durationSeconds: 15, aspectRatio: "9:16", market: "US + UK", language: "en-US")
        let location = CampaignAssumption(text: "One studio day, one location, no travel. The memo's second location is excluded pending a revised agreement.")
        session.updateDraft {
            $0.brief = .init(brand: "Oat & Ember", objective: "Introduce an oat drink for everyday coffee rituals")
            $0.deliverables = [hero, social]; $0.assumptions = [location]
        }
        let brief = try importFixture("brief-v1", into: session, root: root)
        let matrix = try importFixture("deliverables-v1", into: session, root: root)
        let memo = try importFixture("production-memo-v1", into: session, root: root)
        #expect(try matrix.excerpt(firstLine: 19, lastLine: 29) == "H1\n\nHero film\n\n30 seconds\n\n16:9\n\nUS + UK\n\nen-US")
        #expect(try memo.excerpt(firstLine: 5, lastLine: 5).contains("45 seconds"))
        #expect(try brief.excerpt(firstLine: 18, lastLine: 18).contains("one location"))
        #expect(try memo.excerpt(firstLine: 7, lastLine: 7).contains("Two locations"))
        #expect(session.ledger.draft.deliverables == [hero, social])
        #expect(session.ledger.draft.assumptions == [location])
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).count == 3)
        let beforeInvalidCitation = session.ledger, diskBeforeInvalidCitation = try savedBytes(session, root: root)
        #expect(!session.citeAgencyRevision(matrix.id, firstLine: 19, lastLine: 29,
            targetKind: .deliverable, targetID: hero.id, note: "Cannot cite an unreviewed matrix"))
        #expect(session.ledger == beforeInvalidCitation)
        #expect(try savedBytes(session, root: root) == diskBeforeInvalidCitation)

        // The app does not detect semantic contradictions. These are explicit human decisions.
        try review(brief, in: session, note: "Compared retained synthetic brief and extraction. One-location bid basis retained.")
        try review(matrix, in: session, note: "Checked each table cell in XML reading order. Matrix v1 specifies a 30-second hero.")
        try review(memo, in: session, note: "Reviewed conflicting 45-second and two-location requests. They are not adopted into this bid basis.")
        try cite(matrix, lines: 19...29, kind: .deliverable, targetID: hero.id,
            note: "Matrix v1 governs 30 seconds; memo's 45-second request is pending a scope revision.", in: session)
        try cite(matrix, lines: 31...41, kind: .deliverable, targetID: social.id,
            note: "Adopt the reviewed 15-second vertical cutdown.", in: session)
        try cite(brief, lines: 18...18, kind: .assumption, targetID: location.id,
            note: "One studio day and one location form the bid basis.", in: session)
        try cite(memo, lines: 5...5, kind: .deliverable, targetID: hero.id,
            note: "Conflicting 45-second request acknowledged and excluded until a revised matrix is accepted.", in: session)
        try cite(memo, lines: 7...11, kind: .assumption, targetID: location.id,
            note: "Second location and travel are excluded; no price or authorization is inferred from this memo.", in: session)
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).isEmpty == true)
        let initialID = try #require(session.freeze(name: "Human-reconciled V1 bid basis", document: doc))
        let initial = try #require(session.ledger.baselines.first { $0.id == initialID })
        #expect(session.record(baselineID: initialID, scope: .creative, approver: "Synthetic Client",
            evidence: "Fictional creative-only approval recorded for this test", document: doc, amount: "", currency: ""))
        #expect(session.ledger.decisions.map(\.scope) == [.creative])
        #expect(session.ledger.decisions.first?.spendCeilingMinorUnits == nil)

        let revised = try importFixture("deliverables-v2", into: session, root: root, revising: matrix.documentID)
        #expect(revised.documentID == matrix.documentID)
        #expect(revised.priorRevisionID == matrix.id)
        #expect(session.ledger.draft.deliverables == [hero, social])
        #expect(session.ledger.draft.agency?.currentReview(revisionID: revised.id) == nil)
        let changes = try session.ledger.compare(baselineID: initialID, document: doc)
        #expect(changes.contains { $0.sourceKind == .agencyDocument && $0.unresolved })
        #expect(changes.contains { $0.sourceKind == .agencyCitation && $0.unresolved })
        #expect(!session.record(baselineID: initialID, scope: .production, approver: "Synthetic Producer",
            evidence: "Must not carry creative approval forward", document: doc, amount: "", currency: ""))
        #expect(session.ledger.decisions.count == 1)
        try review(revised, in: session, note: "Compared retained V2 original. Accept hero 45 seconds and new 6-second bumper; one studio remains the bid basis.")
        let bumper = CampaignDeliverable(name: "Bumper", durationSeconds: 6, aspectRatio: "1:1", market: "US + UK", language: "en-US")
        session.updateDraft { draft in
            if let index = draft.deliverables.firstIndex(where: { $0.id == hero.id }) {
                draft.deliverables[index].durationSeconds = 45
            }
            draft.deliverables.append(bumper)
        }
        // Fresh review and a new baseline do not silently repair old citation endpoints.
        let unresolvedID = try #require(session.freeze(name: "Reviewed V2 still needs citation reconciliation", document: doc))
        #expect(try session.ledger.compare(baselineID: unresolvedID, document: doc).contains {
            $0.sourceKind == .agencyCitation && $0.unresolved
        })
        #expect(!session.record(baselineID: unresolvedID, scope: .spend, approver: "Synthetic Client",
            evidence: "Must not approve unresolved evidence", document: doc, amount: "1250000", currency: "USD"))
        let oldCitations = try #require(session.ledger.draft.agency).citations.filter {
            $0.documentID == matrix.documentID || $0.targetID == hero.id
        }
        #expect(oldCitations.count == 3)
        for citation in oldCitations { session.removeAgencyCitation(citation.id) }
        try cite(revised, lines: 19...29, kind: .deliverable, targetID: hero.id,
            note: "V2 replaces the original 30-second matrix with 45 seconds.", in: session)
        try cite(revised, lines: 31...41, kind: .deliverable, targetID: social.id,
            note: "Rechecked unchanged social scope against the new original.", in: session)
        try cite(revised, lines: 43...53, kind: .deliverable, targetID: bumper.id,
            note: "Producer explicitly adds the new 6-second square bumper.", in: session)
        try cite(memo, lines: 5...5, kind: .deliverable, targetID: hero.id,
            note: "V2 now confirms this 45-second request. Memo's location request remains excluded.", in: session)
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).isEmpty == true)
        let reconciledID = try #require(session.freeze(name: "Human-reconciled V2 bid basis", document: doc))
        #expect(try session.ledger.compare(baselineID: reconciledID, document: doc).isEmpty)
        #expect(session.record(baselineID: reconciledID, scope: .production, approver: "Synthetic Producer",
            evidence: "Fictional production-approach approval for V2 only", document: doc, amount: "", currency: ""))
        #expect(session.record(baselineID: reconciledID, scope: .spend, approver: "Synthetic Client",
            evidence: "Fictional ceiling evidence, not a payment or authenticated authorization", document: doc, amount: "1250000", currency: "USD"))
        #expect(session.ledger.decisions.map(\.scope) == [.creative, .production, .spend])
        #expect(session.ledger.decisions.last?.baselineID == reconciledID)
        #expect(session.ledger.decisions.last?.spendCeilingMinorUnits == 1_250_000)
        #expect(session.ledger.decisions.last?.currencyCode == "USD")
        #expect(session.ledger.baselines.first { $0.id == initialID } == initial)
        #expect(initial.draft.agency?.revisions.first { $0.id == matrix.id }?.origin?.originalBytes == (try fixture("deliverables-v1").bytes))

        let settled = session.ledger
        session.updateDraft { $0.assumptions[0].text = "Two locations and travel now requested; not yet reconciled" }
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).contains {
            $0.sourceKind == .agencyCitation
        } == true)
        #expect(!session.record(baselineID: reconciledID, scope: .creative, approver: "Synthetic Client",
            evidence: "Changed target must block approval", document: doc, amount: "", currency: ""))
        let changedReopen = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(changedReopen.problem == nil)
        #expect(changedReopen.ledger == session.ledger)
        session.undoDraft()
        #expect(session.ledger == settled)
        let reopened = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(reopened.problem == nil)
        #expect(reopened.ledger == settled)
        #expect(!reopened.canUndoDraft)
        #expect(try reopened.ledger.compare(baselineID: reconciledID, document: doc).isEmpty)
        #expect(doc == originalDocument)
        let backup = try CampaignWorkspaceStore.encoded(reopened.ledger)
        #expect(try CampaignWorkspaceStore.decode(backup, projectID: doc.project.id) == settled)
    }

    @MainActor @Test func metadataOnlyOriginalRequiresFreshReviewAndUndoRestoresExactPriorEvidence() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = document()
        let session = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        let hero = CampaignDeliverable(name: "Hero film", durationSeconds: 45)
        session.updateDraft {
            $0.brief = .init(brand: "Oat & Ember", objective: "Synthetic metadata revision check")
            $0.deliverables = [hero]
        }
        let first = try importFixture("deliverables-v2", into: session, root: root)
        try review(first, in: session, note: "Compared synthetic V2 original and all extracted body text.")
        try cite(first, lines: 19...29, kind: .deliverable, targetID: hero.id, note: "Reviewed 45-second hero.", in: session)
        let baselineID = try #require(session.freeze(name: "Reviewed exact original", document: doc))
        #expect(session.record(baselineID: baselineID, scope: .creative, approver: "Synthetic Client",
            evidence: "Fictional approval on the first original", document: doc, amount: "", currency: ""))
        let before = session.ledger
        let second = try importFixture("deliverables-v2-metadata-only", into: session, root: root, revising: first.documentID)
        #expect(first.bytes == second.bytes)
        #expect(first.sha256 == second.sha256)
        #expect(first.id != second.id)
        #expect(first.origin?.originalBytes != second.origin?.originalBytes)
        #expect(first.origin?.originalSHA256 != second.origin?.originalSHA256)
        #expect(session.ledger.draft.agency?.currentReview(revisionID: second.id) == nil)
        #expect(session.ledger.draft.agency?.currentReview(revisionID: first.id) == nil)
        #expect(session.ledger.draft.agency?.warnings(draft: session.ledger.draft).count == 2)
        #expect(session.ledger.baselines == before.baselines)
        #expect(session.ledger.decisions == before.decisions)
        #expect(!session.record(baselineID: baselineID, scope: .production, approver: "Synthetic Producer",
            evidence: "Same extracted text cannot carry review forward", document: doc, amount: "", currency: ""))
        let revisedReopen = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(revisedReopen.problem == nil)
        #expect(revisedReopen.ledger == session.ledger)
        session.undoDraft()
        #expect(session.ledger == before)
        #expect(try session.ledger.compare(baselineID: baselineID, document: doc).isEmpty)
        let restored = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        #expect(restored.problem == nil)
        #expect(restored.ledger == before)
        #expect(restored.ledger.draft.agency?.revisions.first?.origin?.originalBytes == (try fixture("deliverables-v2").bytes))
        #expect(try Data(contentsOf: root.appendingPathComponent("deliverables-v2-metadata-only.docx")) == fixture("deliverables-v2-metadata-only").bytes)
    }

    @MainActor @Test func unsupportedWordFeaturesAndDamagedFilesLeaveSavedScopeAndHistoryUntouched() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = document()
        let session = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
        session.updateDraft {
            $0.brief = .init(brand: "Oat & Ember", objective: "Preserve reviewed work on failed imports")
            $0.deliverables = [.init(name: "Hero film")]
        }
        let accepted = try importFixture("brief-v1", into: session, root: root)
        try review(accepted, in: session, note: "Original compared before trying unsupported revisions.")
        let baselineID = try #require(session.freeze(name: "Existing reviewed state", document: doc))
        #expect(session.record(baselineID: baselineID, scope: .creative, approver: "Synthetic Client",
            evidence: "Fictional historical approval", document: doc, amount: "", currency: ""))
        let before = session.ledger, beforeDisk = try savedBytes(session, root: root), couldUndo = session.canUndoDraft
        let rejected = try corpus().fixtures.filter { $0.expectedFailure != nil }
        #expect(rejected.count == 11)
        for fixture in rejected {
            let url = try sourceURL(fixture, root: root)
            do {
                _ = try CampaignAgencyImport.read(url)
                Issue.record("Unsupported synthetic fixture unexpectedly produced a preview: \(fixture.name)")
            } catch let failure as CampaignAgencyDocumentExtraction.Failure {
                #expect(String(describing: failure) == fixture.expectedFailure)
            } catch {
                Issue.record("Wrong failure type for \(fixture.name): \(error)")
            }
            #expect(try Data(contentsOf: url) == fixture.bytes)
            #expect(session.ledger == before)
            #expect(session.canUndoDraft == couldUndo)
            #expect(try savedBytes(session, root: root) == beforeDisk)
            let reopened = CampaignWorkspaceSession(projectID: doc.project.id, root: root)
            #expect(reopened.problem == nil)
            #expect(reopened.ledger == before)
            #expect(try reopened.ledger.compare(baselineID: baselineID, document: doc).isEmpty)
        }
        // A rejected read must not add an undo entry: one undo removes the prior review.
        session.undoDraft()
        #expect(session.ledger.draft.agency?.reviews.isEmpty == true)
        #expect(session.ledger.draft.agency?.revisions == [accepted])
        #expect(session.ledger.baselines == before.baselines)
        #expect(session.ledger.decisions == before.decisions)
    }
}
