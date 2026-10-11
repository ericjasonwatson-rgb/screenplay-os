import CryptoKit
import Foundation
import ScreenplayDomain
import Testing
@testable import ScreenplayOSApp

@Suite("Native legacy package writer")
struct NativeLegacyPackageWriterTests {
    enum Injected: Error { case stop }
    private let stamp = "2026-09-12T12:00:00+00:00"

    private func plans() throws -> (URL, URL, NativeLegacyConversionPlan, NativeLegacyIdentityPlan, NativeLegacyPayloadPlan) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projectID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let screenplayID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
        let headingID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let actionID = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
        let document = OpenScreenplayDocument(
            project: Project(id: projectID, metadata: .init(title: "Writer", author: "Author"), screenplayID: screenplayID),
            screenplay: Screenplay(id: screenplayID, metadata: .init(title: "Writer"), elements: [
                ScreenplayElement(id: headingID, type: .sceneHeading, text: "INT. ROOM - DAY", spineID: "S001"),
                ScreenplayElement(id: actionID, type: .action, text: "A lamp hums.")
            ]),
            outline: [.init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000105")!, template: "custom",
                            order: 1, name: "Opening", purpose: "Begin", linkedSceneSpineIDs: ["S001"])]
        )
        let source = root.appendingPathComponent("Source.json")
        try JSONEncoder.openScreenplayEncoder().encode(document).write(to: source)
        let preflight = try NativeLegacyConversionPlan.prepare(sourceURL: source)
        let identities = try NativeLegacyIdentityPlan.build(from: preflight, createdAt: stamp)
        let payloads = try NativeLegacyPayloadPlan.build(from: preflight, identities: identities)
        return (root, source, preflight, identities, payloads)
    }

    @Test func writesReopensAndPreservesAuthenticatedSource() throws {
        let item = try plans(); defer { try? FileManager.default.removeItem(at: item.0) }
        let target = item.0.appendingPathComponent("Converted.screenplay")
        let receipt = try NativeLegacyPackageWriter.write(
            preflight: item.2, identities: item.3, payloadPlan: item.4, destination: target
        )
        let preview = try PackagePreviewReader.read(target)
        #expect(preview.title == "Writer")
        #expect(preview.paragraphs.map(\.text) == ["INT. ROOM - DAY", "A lamp hums."])
        #expect(try Data(contentsOf: item.1) == item.2.sourceBytes)
        #expect(try Data(contentsOf: target.appendingPathComponent("provenance/source.json")) == item.2.sourceBytes)
        #expect(receipt.sourceSHA256 == item.2.sourceSHA256)
        #expect(receipt.projectRevision == item.3.revisionID)
        #expect(receipt.payloadFiles == item.4.payloads.count)
    }

    @Test func failuresRetainRecoveryAndNeverChangeSource() throws {
        for stop in ["staging_created", "write:project.json", "staged_readback", "before_publish", "published", "published_readback"] {
            let item = try plans(); defer { try? FileManager.default.removeItem(at: item.0) }
            let target = item.0.appendingPathComponent("Converted.screenplay")
            do {
                _ = try NativeLegacyPackageWriter.write(
                    preflight: item.2, identities: item.3, payloadPlan: item.4, destination: target
                ) { phase, _ in if phase == stop { throw Injected.stop } }
                Issue.record("Expected failure at \(stop)")
            } catch let failure as NativeLegacyPackageWriter.RetainedFailure {
                #expect(failure.phase == stop)
                #expect(FileManager.default.fileExists(atPath: failure.recoveryURL.path))
                #expect(failure.published == ["published", "published_readback"].contains(stop))
            }
            #expect(try Data(contentsOf: item.1) == item.2.sourceBytes)
        }
    }

    @Test func changedSourceAndCompetingDestinationBlockPublication() throws {
        for competitor in [false, true] {
            let item = try plans(); defer { try? FileManager.default.removeItem(at: item.0) }
            let target = item.0.appendingPathComponent("Converted.screenplay")
            let outside = Data("outside".utf8)
            #expect(throws: NativeLegacyPackageWriter.RetainedFailure.self) {
                _ = try NativeLegacyPackageWriter.write(
                    preflight: item.2, identities: item.3, payloadPlan: item.4, destination: target
                ) { phase, _ in
                    if phase == "before_publish" {
                        try outside.write(to: competitor ? target : item.1)
                    }
                }
            }
            #expect(try Data(contentsOf: competitor ? target : item.1) == outside)
        }
    }

    @Test func corruptedStagedOrPublishedBytesCannotReportSuccess() throws {
        for phaseToCorrupt in ["staged_readback", "published_readback"] {
            let item = try plans(); defer { try? FileManager.default.removeItem(at: item.0) }
            let target = item.0.appendingPathComponent("Converted.screenplay")
            do {
                _ = try NativeLegacyPackageWriter.write(
                    preflight: item.2, identities: item.3, payloadPlan: item.4, destination: target
                ) { phase, package in
                    if phase == phaseToCorrupt {
                        try Data("corrupt".utf8).write(to: package.appendingPathComponent("project.json"))
                    }
                }
                Issue.record("Corrupt output reported success")
            } catch let failure as NativeLegacyPackageWriter.RetainedFailure {
                #expect(failure.phase == phaseToCorrupt)
                #expect(failure.published == (phaseToCorrupt == "published_readback"))
            }
        }
    }
}
