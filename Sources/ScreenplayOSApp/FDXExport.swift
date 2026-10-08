import AppKit
import UniformTypeIdentifiers
import ScreenplayDomain
import ScreenplayFDX

@MainActor extension ScreenplayViewModel {
    /// Capture pending package text without applying a command or changing Undo history.
    func fdxExportSnapshot() throws -> FDXExporter.Result? {
        if let editor = packageEditor {
            var session = editor.session
            if let id = editor.selected, editor.pending {
                try session.replaceText(elementID: id, expectedRevision: session.revision,
                                        expectedText: session.text(for: id), replacement: editor.draft)
            }
            let elements = try session.paragraphs.map { row -> ScreenplayElement in
                var element = ScreenplayElement(id: row.id, type: ElementType(rawValue: row.type)!, text: "")
                element.setStyledText(try session.styledText(for: row.id))
                return element
            }
            let manifest = try PreservedJSON(session.originalFiles["manifest.json"]!)
            return try FDXExporter.export(elements: elements, titlePage: TitlePage(title: editor.title,
                author: manifest.string(at: [.key("author")])))
        }
        guard let document else { return nil }
        return try FDXExporter.export(elements: document.screenplay.elements, titlePage: document.titlePage)
    }

    func writeFDX(_ data: Data, to url: URL, approvedExistingData: Data? = nil) throws {
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        let protected = [sourceURL, saveURL, packageEditor?.source, packageEditor?.currentURL].compactMap { $0 }
        guard !protected.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == destination }) else {
            throw NSError(domain: "ScreenplayOS.FDX", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Choose a separate export file. The open document and imported source cannot be overwritten."])
        }
        try DocumentFileWriter.write(data, to: url, overwriteExisting: approvedExistingData != nil,
                                     expectedExistingData: approvedExistingData)
    }

    func showExportFDXPanel() {
        do {
            guard let snapshot = try fdxExportSnapshot() else { return }
            let review = NSAlert()
            review.messageText = "Export screenplay to Final Draft"
            review.informativeText = snapshot.warnings.joined(separator: "\n\n")
            review.addButton(withTitle: "Continue")
            review.addButton(withTitle: "Cancel")
            guard review.runModal() == .alertFirstButtonReturn else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "fdx") ?? .xml]
            panel.title = "Export Final Draft FDX"
            panel.prompt = "Export"
            panel.canCreateDirectories = true
            let title = packageEditor?.title ?? self.title
            let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)).joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            panel.nameFieldStringValue = (safe.isEmpty ? "Screenplay" : String(safe.prefix(100))) + ".fdx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let approved = try? Data(contentsOf: url)
            try writeFDX(snapshot.data, to: url, approvedExistingData: approved)
        } catch { errorMessage = "FDX export failed: " + error.localizedDescription }
    }
}
