import Foundation
import CryptoKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Edited package copy")
struct PackageEditedCopyTests {
    enum Injected: Error { case stop }
    func fixture() throws -> (URL, URL, PackageTextSession, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Original.screenplay")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let fixture = PackageTextSessionTests()
        for (name, bytes) in try fixture.fixture() { try bytes.write(to: source.appendingPathComponent(name)) }
        var session = try PackageEditedCopy.load(source)
        try session.replaceText(elementID: fixture.first, expectedRevision: session.revision, expectedText: "first", replacement: "New 👩🏽‍🚀\ntext")
        return (root, source, session, fixture.first)
    }
    @Test func savesReopensAndPreservesSource() throws {
        let (root, source, session, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Edited.screenplay")
        let receipt = try PackageEditedCopy.save(session, source: source, destination: target)
        let reopened = try PackageEditedCopy.load(target)
        #expect(try reopened.text(for: id) == "New 👩🏽‍🚀\ntext")
        #expect(try PackageEditedCopy.load(source).originalFiles == session.originalFiles)
        #expect(receipt.sessionRevision == session.revision)
        for (name, hash) in receipt.sha256 {
            let bytes = try Data(contentsOf: target.appendingPathComponent(name))
            #expect(hash == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        }
        // An independent Foundation projection confirms text and stable identity.
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("screenplay.json"))) as! [String: Any]
        let elements = parsed["elements"] as! [[String: Any]]
        #expect(elements.first(where: { $0["id"] as? String == id.uuidString })?["text"] as? String == "New 👩🏽‍🚀\ntext")
    }
    @Test func failuresRetainRecoveryAndOriginal() throws {
        for stop in ["staging_created", "write:manifest.json", "write:screenplay.json", "staged_readback", "before_publish", "published", "published_readback"] {
            let (root, source, session, _) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("Edited.screenplay")
            do {
                _ = try PackageEditedCopy.save(session, source: source, destination: target) { phase, _ in
                    if phase == stop { throw Injected.stop }
                }
                Issue.record("Expected injected failure")
            } catch let failure as PackageEditedCopy.RetainedFailure {
                #expect(failure.phase == stop)
                #expect(FileManager.default.fileExists(atPath: failure.recoveryURL.path))
                #expect(failure.published == ["published", "published_readback"].contains(stop))
            }
            #expect(try PackageEditedCopy.load(source).originalFiles == session.originalFiles)
        }
    }
    @Test func changedSourceAndCompetingDestinationAreNotOverwritten() throws {
        for compete in [false, true] {
            let (root, source, session, _) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("Edited.screenplay")
            let changed = Data("outside change".utf8)
            #expect(throws: PackageEditedCopy.RetainedFailure.self) {
                _ = try PackageEditedCopy.save(session, source: source, destination: target) { phase, _ in
                    if phase == "before_publish" {
                        if compete { try changed.write(to: target) }
                        else { try changed.write(to: source.appendingPathComponent("screenplay.json")) }
                    }
                }
            }
            let modified = compete ? target : source.appendingPathComponent("screenplay.json")
            #expect(try Data(contentsOf: modified) == changed)
        }
    }
    @Test func corruptReadbackCannotReportSuccess() throws {
        let (root, source, session, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PackageEditedCopy.RetainedFailure.self) {
            _ = try PackageEditedCopy.save(session, source: source, destination: root.appendingPathComponent("Edited.screenplay")) { phase, stage in
                if phase == "staged_readback" { try Data("bad".utf8).write(to: stage.appendingPathComponent("screenplay.json")) }
            }
        }
        #expect(try PackageEditedCopy.load(source).originalFiles == session.originalFiles)
    }
    @Test func sourceChangeAfterPublicationRetainsCompleteCopy() throws {
        let (root, source, session, id) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Edited.screenplay")
        do {
            _ = try PackageEditedCopy.save(session, source: source, destination: target) { phase, _ in
                if phase == "published" { try Data("outside".utf8).write(to: source.appendingPathComponent("screenplay.json")) }
            }
            Issue.record("Expected changed-source failure")
        } catch let failure as PackageEditedCopy.RetainedFailure {
            #expect(failure.published)
            #expect(failure.recoveryURL.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path)
            #expect(try PackageEditedCopy.load(target).text(for: id) == "New 👩🏽‍🚀\ntext")
        }
    }
    @Test func rejectsUnknownFilesSymlinksAndNestedDestination() throws {
        let (root, source, session, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PackageEditedCopy.Failure.self) {
            _ = try PackageEditedCopy.save(session, source: source, destination: source.appendingPathComponent("Nested.screenplay"))
        }
        let unknown = source.appendingPathComponent("unknown.bin")
        try Data([0, 255]).write(to: unknown)
        #expect(throws: PackageEditedCopy.Failure.self) { _ = try PackageEditedCopy.load(source) }
        #expect(try Data(contentsOf: unknown) == Data([0, 255]))
        try FileManager.default.removeItem(at: unknown)
        let link = root.appendingPathComponent("Link.screenplay")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        #expect(throws: PackageEditedCopy.Failure.self) { _ = try PackageEditedCopy.load(link) }
    }
}
