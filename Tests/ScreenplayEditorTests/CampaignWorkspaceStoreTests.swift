import Foundation
import Darwin
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Campaign workspace persistence")
struct CampaignWorkspaceStoreTests {
    private func temporaryRoot() throws -> URL {
        // macOS temporaryDirectory commonly begins with the /var system alias.
        let root = try CampaignWorkspaceStore.canonicalRoot(FileManager.default.temporaryDirectory)
            .appendingPathComponent("CampaignStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func ledger(_ projectID: UUID) -> CampaignLedger {
        var value = CampaignLedger(projectID: projectID)
        value.draft.brief.brand = "Café 👩🏽‍🚀"
        value.draft.brief.objective = "Launch\nwith a second line"
        value.draft.brief.audience = "Independent filmmakers"
        value.draft.brief.keyMessage = "Keep \"creative\" work local"
        value.draft.brief.mandatoryRequirements = "Exact e\u{301} spelling and a \\ slash"
        return value
    }

    @Test func missingReadDoesNotCreateCampaignDirectoriesOrFile() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        let loaded = try CampaignWorkspaceStore.load(projectID: projectID, from: url)
        #expect(loaded.ledger == CampaignLedger(projectID: projectID))
        #expect(loaded.bytes == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func savesAndReloadsExactLedgerAndBytes() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        var value = ledger(projectID)
        let first = try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        #expect(first == (try CampaignWorkspaceStore.encoded(value)))
        let loaded = try CampaignWorkspaceStore.load(projectID: projectID, from: url)
        #expect(loaded.ledger == value)
        #expect(loaded.bytes == first)
        value.draft.brief.objective = "Revised objective"
        let second = try CampaignWorkspaceStore.save(value, to: url, expected: loaded.bytes)
        #expect(second != first)
        #expect(try CampaignWorkspaceStore.load(projectID: projectID, from: url).ledger == value)
        #expect(try Data(contentsOf: url) == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .allSatisfy { $0 == "campaign-v1.json" || $0 == ".campaign.lock" })
    }

    @Test func staleWriterCannotOverwriteNewerLedger() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        var value = ledger(projectID)
        let first = try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        value.draft.brief.brand = "Newer writer"
        let second = try CampaignWorkspaceStore.save(value, to: url, expected: first)
        do {
            _ = try CampaignWorkspaceStore.save(ledger(projectID), to: url, expected: first)
            Issue.record("A stale writer must fail")
        } catch CampaignWorkspaceStore.Failure.conflict { }
        #expect(try Data(contentsOf: url) == second)
        #expect(throws: CampaignWorkspaceStore.Failure.self) {
            try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        }
        #expect(try Data(contentsOf: url) == second)
    }

    @Test func leaseComparesExactBytesRatherThanDecodedEquality() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = try CampaignWorkspaceStore.url(projectID: projectID, root: root)
        let value = ledger(projectID)
        let first = try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        let reformatted = first + Data("\n ".utf8)
        try reformatted.write(to: url)
        #expect(try CampaignWorkspaceStore.decode(reformatted, projectID: projectID) == value)
        do {
            _ = try CampaignWorkspaceStore.save(value, to: url, expected: first)
            Issue.record("Semantically equal but changed bytes must invalidate the lease")
        } catch CampaignWorkspaceStore.Failure.conflict { }
        #expect(try Data(contentsOf: url) == reformatted)
    }

    @Test func wrongProjectCannotBeLoadedOrOverwritten() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = root.appendingPathComponent("campaign.json")
        let original = try CampaignWorkspaceStore.save(ledger(projectID), to: url, expected: nil)
        let otherID = UUID()
        do {
            _ = try CampaignWorkspaceStore.load(projectID: otherID, from: url)
            Issue.record("A campaign from another project must fail to load")
        } catch CampaignWorkspaceStore.Failure.wrongProject { }
        #expect(throws: (any Error).self) {
            try CampaignWorkspaceStore.save(ledger(otherID), to: url, expected: original)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func corruptDuplicateAndUnknownDataFailClosed() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let value = ledger(projectID)
        let valid = try CampaignWorkspaceStore.encoded(value)
        var duplicate = Data("{\"projectID\":\"\(projectID.uuidString)\",".utf8)
        duplicate.append(valid.dropFirst())
        var unknownRoot = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        unknownRoot["futureField"] = ["authored": "Do not discard"]
        var unknownNested = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var draft = try #require(unknownNested["draft"] as? [String: Any])
        var brief = try #require(draft["brief"] as? [String: Any])
        brief["futureRequirement"] = "Do not discard nested creative work"
        draft["brief"] = brief
        unknownNested["draft"] = draft
        let invalid = [Data("{broken".utf8), duplicate,
                       try JSONSerialization.data(withJSONObject: unknownRoot),
                       try JSONSerialization.data(withJSONObject: unknownNested)]
        for (index, bytes) in invalid.enumerated() {
            let url = root.appendingPathComponent("invalid-\(index).json")
            try bytes.write(to: url)
            #expect(throws: (any Error).self) { try CampaignWorkspaceStore.load(projectID: projectID, from: url) }
            #expect(try Data(contentsOf: url) == bytes)
            // Even possession of the exact disk bytes is not permission to discard unsupported data.
            #expect(throws: (any Error).self) { try CampaignWorkspaceStore.save(value, to: url, expected: bytes) }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func rejectsFileSymlinkAndPreservesTarget() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let target = root.appendingPathComponent("target.json")
        let bytes = try CampaignWorkspaceStore.save(ledger(projectID), to: target, expected: nil)
        let link = root.appendingPathComponent("campaign.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.load(projectID: projectID, from: link) }
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.save(ledger(projectID), to: link, expected: bytes) }
        #expect(try Data(contentsOf: target) == bytes)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func rejectsParentAndDanglingSymlinks() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let target = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let url = link.appendingPathComponent("new/campaign.json")
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.load(projectID: projectID, from: url) }
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.save(ledger(projectID), to: url, expected: nil) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        let dangling = root.appendingPathComponent("dangling.json")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("absent.json"))
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.save(ledger(projectID), to: dangling, expected: nil) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("absent.json").path))
    }

    @Test func savedFilePermissionsAreOwnerOnlyAfterReplacement() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = root.appendingPathComponent("campaign.json")
        let value = ledger(projectID)
        let first = try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        func permissions() throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
        }
        #expect(try permissions() == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        _ = try CampaignWorkspaceStore.save(value, to: url, expected: first)
        #expect(try permissions() == 0o600)
    }

    @Test func rejectsRemoteDirectoryAndNondirectoryParentDestinations() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let value = ledger(projectID)
        let remote = try #require(URL(string: "https://example.invalid/campaign.json"))
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.load(projectID: projectID, from: remote) }
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.save(value, to: remote, expected: nil) }
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.save(value, to: root, expected: nil) }
        let blocker = root.appendingPathComponent("ordinary-file")
        let sentinel = Data("untouched".utf8)
        try sentinel.write(to: blocker)
        let blocked = blocker.appendingPathComponent("campaign.json")
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.load(projectID: projectID, from: blocked) }
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.save(value, to: blocked, expected: nil) }
        #expect(try Data(contentsOf: blocker) == sentinel)
    }

    @Test func rejectsOversizedInputAndOutputWithoutOverwriting() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let url = root.appendingPathComponent("campaign.json")
        var value = ledger(projectID)
        let original = try CampaignWorkspaceStore.save(value, to: url, expected: nil)
        value.draft.brief.objective = String(repeating: "x", count: CampaignWorkspaceStore.maximumBytes + 1)
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.encoded(value) }
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.save(value, to: url, expected: original) }
        #expect(try Data(contentsOf: url) == original)
        let oversized = Data(repeating: 0x20, count: CampaignWorkspaceStore.maximumBytes + 1)
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.decode(oversized, projectID: projectID) }
        let oversizedURL = root.appendingPathComponent("oversized.json")
        try oversized.write(to: oversizedURL)
        #expect(throws: CampaignWorkspaceStore.Failure.self) { try CampaignWorkspaceStore.load(projectID: projectID, from: oversizedURL) }
        #expect(try Data(contentsOf: oversizedURL) == oversized)
    }
    @Test func backupReaderPreservesExactLimitAndRejectsOversizedBytes() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Backup.json")
        var bytes = try CampaignWorkspaceStore.encoded(CampaignLedger(projectID: UUID()))
        bytes.append(Data(repeating: 32, count: CampaignWorkspaceStore.maximumBytes - bytes.count))
        try bytes.write(to: url)
        #expect(try CampaignWorkspaceStore.readBackup(url) == bytes)
        bytes.append(32); try bytes.write(to: url)
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.readBackup(url) }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func backupReaderRejectsUnsafeAndNonregularSourcesWithoutBlocking() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.json"); try Data("{}".utf8).write(to: real)
        let link = root.appendingPathComponent("Link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let missing = root.appendingPathComponent("Missing.json")
        let dangling = root.appendingPathComponent("Dangling.json")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: missing)
        let fifo = root.appendingPathComponent("Pipe.json"); #expect(mkfifo(fifo.path, 0o600) == 0)
        for url in [root, link, dangling, fifo, missing, URL(string: "https://example.invalid/backup.json")!] {
            #expect(throws: (any Error).self) { try CampaignWorkspaceStore.readBackup(url) }
        }
        #expect(try Data(contentsOf: real) == Data("{}".utf8))
    }

    @Test func growingBackupReaderNeverRequestsOrRetainsMoreThanLimitPlusOne() throws {
        var allowances: [Int] = []
        var supplied = 0
        #expect(throws: (any Error).self) {
            try CampaignWorkspaceStore.readBounded(limit: 8) { allowance in
                allowances.append(allowance)
                let count = min(3, allowance); supplied += count
                return Data(repeating: 65, count: count)
            }
        }
        #expect(allowances == [9, 6, 3])
        #expect(supplied == 9)
        #expect(throws: (any Error).self) { try CampaignWorkspaceStore.readBounded(limit: 8) { _ in Data(repeating: 65, count: 10) } }
    }

}
