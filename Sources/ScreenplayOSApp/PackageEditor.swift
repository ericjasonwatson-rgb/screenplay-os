import AppKit
import SwiftUI
import ScreenplayDomain

@MainActor
final class PackageEditor: ObservableObject, Identifiable {
    let id = UUID()
    struct Row: Identifiable { let id: UUID; let type: String }
    let rows: [Row]
    let source: URL
    let title: String
    @Published private(set) var session: PackageTextSession
    @Published var selected: UUID?
    @Published var draft = "" { didSet { scheduleRecovery() } }
    @Published var message: String?
    private var savedBytes: Data
    private var recoveryID = UUID()
    private let recoveryDirectory: URL?
    private var recoveryTask: Task<Void, Never>?
    @Published var recoveryStatus: String?
    private var originalSource: URL

    private func scheduleRecovery() {
        guard recoveryDirectory != nil else { return }
        recoveryTask?.cancel()
        recoveryStatus = dirty ? "Recovery pending…" : nil
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushRecovery()
        }
    }
    @discardableResult func flushRecovery() -> Bool {
        recoveryTask?.cancel()
        guard let recoveryDirectory else { return false }
        do {
            if !dirty {
                try PackageRecovery.remove(recoveryID, directory: recoveryDirectory)
                recoveryStatus = nil
                return true
            }
            var candidate = session
            if let selected, pending {
                try candidate.replaceText(elementID: selected, expectedRevision: candidate.revision,
                                          expectedText: candidate.text(for: selected), replacement: draft)
            }
            var files = candidate.originalFiles
            files["screenplay.json"] = candidate.screenplayBytes
            try PackageRecovery.write(.init(version: 1, id: recoveryID, title: title,
                originalSource: originalSource, savedAt: Date(), selected: selected, files: files), directory: recoveryDirectory)
            recoveryStatus = "Recovery saved locally"
            return true
        } catch { recoveryStatus = "Recovery failed. Keep this editor open and save an edited copy."; return false }
    }
    private func discardRecovery() {
        recoveryTask?.cancel()
        guard let recoveryDirectory else { return }
        do { try PackageRecovery.remove(recoveryID, directory: recoveryDirectory); recoveryStatus = nil }
        catch { recoveryStatus = "An older recovery copy could not be removed." }
    }
    convenience init(recovery: PackageRecovery.Record, directory: URL) throws {
        let restored = try PackageRecovery.materialize(recovery, directory: directory)
        try self.init(source: restored, recoveryDirectory: directory)
        recoveryID = recovery.id
        originalSource = recovery.originalSource
        savedBytes = Data()
        if let selected = recovery.selected, rows.contains(where: { $0.id == selected }) {
            self.selected = selected
            draft = try session.text(for: selected)
        }
        message = "Recovered unsaved text. Save an edited copy to keep it."
        flushRecovery()
    }
    var pending: Bool {
        guard let selected, let text = try? session.text(for: selected) else { return false }
        return !text.unicodeScalars.elementsEqual(draft.unicodeScalars)
    }
    var dirty: Bool { pending || session.screenplayBytes != savedBytes }
    var canUndo: Bool { pending || session.canUndo }
    var canRedo: Bool { !pending && session.canRedo }

    init(source: URL, recoveryDirectory: URL? = nil) throws {
        let loaded = try PackageEditedCopy.load(source)
        self.source = source
        self.originalSource = source
        self.recoveryDirectory = recoveryDirectory
        session = loaded
        savedBytes = loaded.screenplayBytes
        let manifest = try PreservedJSON(loaded.originalFiles["manifest.json"]!)
        title = try manifest.string(at: [.key("title")])
        let root = try JSONSerialization.jsonObject(with: loaded.screenplayBytes) as! [String: Any]
        rows = (root["elements"] as! [[String: Any]]).map { Row(id: UUID(uuidString: $0["id"] as! String)!, type: $0["type"] as! String) }
        selected = rows.first?.id
        if let selected { draft = try loaded.text(for: selected) }
    }
    @discardableResult func apply() -> Bool {
        guard let selected, pending else { return true }
        do {
            try session.replaceText(elementID: selected, expectedRevision: session.revision,
                                    expectedText: session.text(for: selected), replacement: draft)
            message = nil
            scheduleRecovery()
            return true
        } catch { message = "The paragraph could not be updated. Your text is still here."; return false }
    }
    func select(_ id: UUID) {
        guard apply() else { return }
        selected = id; draft = (try? session.text(for: id)) ?? ""
    }
    func undo() {
        if pending { refreshDraft(); return }
        session.undo(); refreshDraft(); message = nil
    }
    func redo() { guard !pending else { return }; session.redo(); refreshDraft(); message = nil }
    private func refreshDraft() { if let selected { draft = (try? session.text(for: selected)) ?? "" } }
    @discardableResult func save(to url: URL) -> Bool {
        guard apply() else { return false }
        flushRecovery()
        do {
            let result = try PackageEditedCopy.save(session, source: source, destination: url)
            savedBytes = session.screenplayBytes
            discardRecovery()
            message = "Saved and verified: " + result.destination.path
            return true
        } catch let error as PackageEditedCopy.RetainedFailure {
            message = "Save could not be verified. Keep this editor open. Retained output (may be incomplete): " + error.recoveryURL.path
        } catch {
            message = "Could not save this copy. The source may have changed or the destination may be unavailable. Your edits remain here. Choose a new destination and keep this editor open."
        }
        return false
    }
    @discardableResult func savePanel() -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save Edited Copy"
        panel.directoryURL = originalSource.deletingLastPathComponent()
        panel.prompt = "Save Copy"
        panel.nameFieldStringValue = originalSource.deletingPathExtension().lastPathComponent + " Edited.screenplay"
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        if url.pathExtension != "screenplay" { url.appendPathExtension("screenplay") }
        return save(to: url)
    }
    func confirmClose() -> Bool {
        guard dirty else { discardRecovery(); return true }
        flushRecovery()
        let alert = NSAlert()
        alert.messageText = "Save your package edits before closing?"
        alert.informativeText = "These edits have not been saved to a copy. The original package is unchanged."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Save Edited Copy…")
        alert.addButton(withTitle: "Discard Changes")
        if recoveryDirectory != nil { alert.addButton(withTitle: "Keep Recovery for Later") }
        switch alert.runModal() {
        case .alertSecondButtonReturn: return savePanel()
        case .alertThirdButtonReturn: discardRecovery(); return true
        case NSApplication.ModalResponse(rawValue: 1003): return flushRecovery()
        default: return false
        }
    }
}

struct PackageEditorView: View {
    @ObservedObject var editor: PackageEditor
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(editor.title.isEmpty ? "Untitled Screenplay" : editor.title).font(.headline)
                    Text("Experimental package editor · Save to a new copy").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { if editor.confirmClose() { close() } }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Button("Undo", action: editor.undo).disabled(!editor.canUndo)
                Button("Redo", action: editor.redo).disabled(!editor.canRedo)
                Spacer()
                Text(editor.dirty ? "Unsaved changes" : "No unsaved changes").foregroundStyle(.secondary)
                Button("Save Edited Copy…") { editor.savePanel() }
            }
            Divider()
            HStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                            Button {
                                editor.select(row.id)
                            } label: {
                                Text("\(index + 1). " + ((try? editor.session.text(for: row.id)) ?? ""))
                                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.borderless)
                        }
                    }
                }.frame(width: 200).accessibilityLabel("Package paragraphs")
                Divider()
                VStack(alignment: .leading) {
                    if let row = editor.rows.first(where: { $0.id == editor.selected }) {
                        Text(row.type.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
                        TextEditor(text: $editor.draft).font(.system(size: 14, design: .monospaced))
                            .accessibilityLabel("Paragraph text")
                        Button("Apply Paragraph") { editor.apply() }.disabled(!editor.pending)
                    } else { Text("This screenplay has no paragraphs.") }
                }
            }
            Text("Edit existing paragraphs here. Page layout, paragraph creation, and production features are not available in this editor.")
                .font(.caption).foregroundStyle(.secondary)
            if let recovery = editor.recoveryStatus { Text(recovery).font(.caption).foregroundStyle(.secondary) }
            if let message = editor.message { Text(message).font(.callout).textSelection(.enabled) }
        }.padding(16).frame(minWidth: 740, idealWidth: 850, minHeight: 520, idealHeight: 650)
            .interactiveDismissDisabled()
    }
}
