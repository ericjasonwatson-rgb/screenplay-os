import AppKit
import Foundation
import SwiftUI

struct LegacyConvertedCopyReceipt: Identifiable, Codable, Sendable {
    var id: String { destination }
    let destination: String
    let sourceSHA256: String
    let projectRevision: String
    let payloadFiles: Int
    let mediaAttachments: Int

    enum CodingKeys: String, CodingKey {
        case destination
        case sourceSHA256 = "source_sha256"
        case projectRevision = "project_revision"
        case payloadFiles = "payload_files"
        case mediaAttachments = "media_attachments"
    }
}

struct LegacyConvertedCopyService: Sendable {
    enum Failure: LocalizedError {
        case unavailable, invalidSource, invalidDestination, process(String), invalidReport, failedVerification
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The experimental converter needs a local Python 3 runtime with the jsonschema package. No compatible runtime was found. The source was not changed."
            case .invalidSource:
                return "Save the current legacy screenplay as a JSON file before creating a converted copy."
            case .invalidDestination:
                return "Choose a new destination ending in .screenplay. Existing destinations are never replaced."
            case let .process(message):
                return "Conversion failed. The source was not changed. \(message)"
            case .invalidReport:
                return "The converter did not return a valid completion report. No success is claimed."
            case .failedVerification:
                return "The converted package failed independent app verification. Do not use it as a complete copy."
            }
        }
    }

    let scriptURL: URL?
    let runtimeURL: URL?

    init(scriptURL: URL? = LegacyConvertedCopyService.bundledScript(),
         runtimeURL: URL? = LegacyConvertedCopyService.compatibleRuntime()) {
        self.scriptURL = scriptURL
        self.runtimeURL = runtimeURL
    }

    var isAvailable: Bool { scriptURL != nil && runtimeURL != nil }

    func convert(source: URL, destination: URL) throws -> LegacyConvertedCopyReceipt {
        guard let scriptURL, let runtimeURL else { throw Failure.unavailable }
        guard source.pathExtension.lowercased() == "json" else { throw Failure.invalidSource }
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceValues.isRegularFile == true,
              sourceValues.isSymbolicLink != true else { throw Failure.invalidSource }
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        guard target.pathExtension.lowercased() == "screenplay",
              !FileManager.default.fileExists(atPath: target.path) else { throw Failure.invalidDestination }

        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = runtimeURL
        process.arguments = [scriptURL.path, "convert", source.path, target.path]
        process.standardOutput = output
        process.standardError = errors
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let report = try? JSONSerialization.jsonObject(with: stderr) as? [String: Any]
            var message = report?["message"] as? String ?? "The retained output, if any, requires manual verification."
            if let retained = report?["retained_path"] as? String { message += " Retained output: \(retained)" }
            throw Failure.process(message)
        }
        guard let receipt = try? JSONDecoder().decode(LegacyConvertedCopyReceipt.self, from: stdout),
              URL(fileURLWithPath: receipt.destination).standardizedFileURL == target.standardizedFileURL else {
            throw Failure.invalidReport
        }
        guard (try? PackagePreviewReader.read(target)) != nil else { throw Failure.failedVerification }
        return receipt
    }

    static func bundledScript(bundle: Bundle = .main) -> URL? {
        guard let url = bundle.resourceURL?.appendingPathComponent("LegacyConverter/Scripts/convert-legacy-copy.py"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }

    static func compatibleRuntime() -> URL? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"
        ]
        for url in candidates.map(URL.init(fileURLWithPath:)) where FileManager.default.isExecutableFile(atPath: url.path) {
            let process = Process()
            process.executableURL = url
            process.arguments = ["-c", "import jsonschema"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                process.waitUntilExit()
                if process.terminationStatus == 0 { return url }
            }
        }
        return nil
    }
}

struct LegacyConvertedCopyReportView: View {
    let receipt: LegacyConvertedCopyReceipt
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Converted copy verified").font(.title2.bold()); Spacer(); Button("Done", action: close) }
            Text("A separate experimental package was created. Your active screenplay and its source file were not replaced.")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { Text("Destination").foregroundStyle(.secondary); Text(receipt.destination).textSelection(.enabled) }
                GridRow { Text("Project revision").foregroundStyle(.secondary); Text(receipt.projectRevision).textSelection(.enabled) }
                GridRow { Text("Payload files").foregroundStyle(.secondary); Text("\(receipt.payloadFiles)") }
                GridRow { Text("Board images").foregroundStyle(.secondary); Text("\(receipt.mediaAttachments)") }
                GridRow { Text("Source SHA-256").foregroundStyle(.secondary); Text(receipt.sourceSHA256).font(.caption.monospaced()).textSelection(.enabled) }
            }
            Text("This package opens read-only in this build. Keep the original JSON file.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: receipt.destination)]) }
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(minWidth: 620)
    }
}
