import AppKit
import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Paid production-image result recovery")
struct ProductionImageResultVaultTests {
    private func png(width: Int) throws -> Data {
        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(image.representation(using: .png, properties: [:]))
    }

    @Test func savedResultCanBeRecoveredWithoutProviderRequest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = UUID(), job = UUID()
        let image = try png(width: 2)
        let destination = try ProductionImageResultVault.store(
            image, projectID: project, jobID: job, root: root)
        #expect(try ProductionImageResultVault.load(
            projectID: project, jobID: job, root: root) == image)
        let recovered = try ProductionImageResultVault.recoverResponse(
            projectID: project, jobID: job, root: root)
        #expect(try OpenAIReferenceImageResponse.decode(recovered) == image)
        #expect(try ProductionImageResultVault.store(
            image, projectID: project, jobID: job, root: root) == destination)
    }

    @Test func differentImageCannotReplaceEarlierPaidResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = UUID(), job = UUID()
        let initial = try png(width: 1), different = try png(width: 2)
        _ = try ProductionImageResultVault.store(initial, projectID: project, jobID: job, root: root)
        #expect(throws: ProductionImageResultVault.Failure.conflictingResult) {
            try ProductionImageResultVault.store(
                different, projectID: project, jobID: job, root: root)
        }
        #expect(try ProductionImageResultVault.load(
            projectID: project, jobID: job, root: root) == initial)
    }

    @Test func unsafeSymlinkAndCorruptedResultAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        defer { try? FileManager.default.removeItem(at: outside) }
        let project = UUID(), job = UUID()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("ScreenplayOS"), withDestinationURL: outside)
        #expect(throws: ProductionImageResultVault.Failure.unsafeStorage) {
            try ProductionImageResultVault.store(
                png(width: 1), projectID: project, jobID: job, root: root)
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("ScreenplayOS"))
        let saved = try ProductionImageResultVault.store(
            png(width: 1), projectID: project, jobID: job, root: root)
        try Data([0, 1, 2]).write(to: saved)
        #expect(throws: ProductionImageResultVault.Failure.missingResult) {
            try ProductionImageResultVault.load(
                projectID: project, jobID: job, root: root)
        }
    }
}
