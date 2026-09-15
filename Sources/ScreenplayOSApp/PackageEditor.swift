import AppKit
import SwiftUI
import ScreenplayDomain

@MainActor
final class PackageEditor: ObservableObject, Identifiable {
    let id = UUID()
    struct Row: Identifiable { let id: UUID; let type: String }
    var rows: [Row] { session.paragraphs.map { Row(id: $0.id, type: $0.type) } }
    func label(for row: Row) -> String {
        let text = (try? session.text(for: row.id)) ?? ""
        return text.isEmpty ? row.type.replacingOccurrences(of: "_", with: " ").capitalized + " (empty)" : text
    }
    let source: URL
    let title: String
    @Published private(set) var session: PackageTextSession
    @Published var selected: UUID?
    @Published var draft = "" { didSet { scheduleRecovery() } }
    @Published var message: String?
    @Published var printPreview: PrintPreviewSnapshot?
    @Published var characterSuggestions: [String] = []
    @Published var highlightedSuggestion: Int?
    private var dismissedSuggestion: String?
    private var suggestionContext: String?
    var completionCaret: Int?

    func updateCharacterSuggestions(atEnd: Bool) {
        let context = (selected?.uuidString ?? "") + ":" + draft
        if suggestionContext != context {
            highlightedSuggestion = nil; dismissedSuggestion = nil; suggestionContext = context
        }
        guard atEnd, rows.first(where: { $0.id == selected })?.type == "character",
              !draft.isEmpty, !draft.contains("\n"), context != dismissedSuggestion else {
            characterSuggestions = []; highlightedSuggestion = nil; return
        }
        var seen = Set<String>()
        characterSuggestions = session.paragraphs.compactMap { row -> String? in
            guard row.type == "character", row.id != selected,
                  let name = try? session.text(for: row.id), !name.contains("\n"),
                  name.lowercased().hasPrefix(draft.lowercased()),
                  name.lowercased() != draft.lowercased(),
                  seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }.prefix(5).map { $0 }
        if let highlightedSuggestion, highlightedSuggestion >= characterSuggestions.count { self.highlightedSuggestion = nil }
    }
    func dismissCharacterSuggestions() {
        dismissedSuggestion = suggestionContext
        characterSuggestions = []; highlightedSuggestion = nil
    }
    @discardableResult func acceptCharacterSuggestion(_ name: String) -> Bool {
        guard characterSuggestions.contains(name), let selected,
              rows.first(where: { $0.id == selected })?.type == "character" else { return false }
        draft = name
        guard apply() else { return false }
        let projection = PackageWritingProjection(session)
        completionCaret = projection.entries.first(where: { $0.id == selected }).map { NSMaxRange($0.range) }
        dismissCharacterSuggestions()
        return true
    }
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
        selected = loaded.paragraphs.first?.id
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
        let oldIDs = Set(rows.map(\.id)), oldIndex = rows.firstIndex { $0.id == selected } ?? 0
        session.undo(); restoreSelection(previousIDs: oldIDs, oldIndex: oldIndex); message = nil
    }
    func redo() {
        guard !pending else { return }
        let oldIDs = Set(rows.map(\.id)), oldIndex = rows.firstIndex { $0.id == selected } ?? 0
        session.redo(); restoreSelection(previousIDs: oldIDs, oldIndex: oldIndex); message = nil
    }
    private func restoreSelection(previousIDs: Set<UUID>, oldIndex: Int) {
        if let restored = rows.first(where: { !previousIDs.contains($0.id) }) { selected = restored.id }
        if !rows.contains(where: { $0.id == selected }) { selected = rows.isEmpty ? nil : rows[min(max(0, oldIndex - 1), rows.count - 1)].id }
        refreshDraft()
    }
    private func refreshDraft() { draft = selected.flatMap { try? session.text(for: $0) } ?? "" }
    func addParagraph() {
        guard apply() else { return }
        do {
            selected = try session.insert(after: selected, expectedRevision: session.revision)
            refreshDraft(); message = nil
        } catch { message = "The paragraph could not be added. Your work is still here." }
    }
    func changeType(_ type: String) {
        guard let selected, apply() else { return }
        do {
            try session.changeType(elementID: selected, expectedRevision: session.revision, type: type)
            scheduleRecovery(); message = nil
        } catch { message = "The paragraph type could not be changed." }
    }
    func deleteParagraph() {
        guard let selected, let index = rows.firstIndex(where: { $0.id == selected }), apply() else { return }
        do {
            try session.delete(elementID: selected, expectedRevision: session.revision)
            self.selected = rows.isEmpty ? nil : rows[min(index, rows.count - 1)].id
            refreshDraft(); message = "Paragraph deleted. Undo restores it."
        } catch { message = "The paragraph could not be deleted." }
    }
    @discardableResult func splitParagraph(at range: NSRange) -> Bool {
        guard let selected, let selection = Range(range, in: draft) else { return false }
        // Native selections use UTF-16; require grapheme boundaries before splitting.
        let boundaries = Set(draft.indices).union([draft.endIndex])
        guard boundaries.contains(selection.lowerBound), boundaries.contains(selection.upperBound) else { return false }
        let prefix = String(draft[..<selection.lowerBound]), suffix = String(draft[selection.upperBound...])
        let type = rows.first(where: { $0.id == selected })?.type ?? "action"
        let next = ["character", "parenthetical"].contains(type) ? "dialogue" : "action"
        guard apply() else { return false }
        do {
            self.selected = try session.split(elementID: selected, expectedRevision: session.revision,
                prefix: prefix, suffix: suffix, nextType: next)
            refreshDraft(); message = nil; return true
        } catch { message = "The paragraph could not be split. Your text is still here."; return false }
    }
    func selectWritingParagraph(_ id: UUID) {
        guard selected != id else { return }
        selected = id; refreshDraft()
    }
    @discardableResult func editWritingSpan(start: UUID, end: UUID, prefix: String, replacement: String, suffix: String, splitType: String?) -> Bool {
        do {
            selected = try session.editSpan(startID: start, endID: end, expectedRevision: session.revision,
                prefix: prefix, replacement: replacement, suffix: suffix, splitType: splitType)
            refreshDraft(); message = nil; return true
        } catch { message = "The edit could not be applied. Your previous text is retained."; return false }
    }
    func showPrintPreview() {
        guard apply() else { return }
        do {
            let result = try PackagePrintLayout.make(session)
            printPreview = try PrintPreviewSnapshot(data: result.data, hasTitlePage: false)
        } catch { message = "The print preview could not be created. Your screenplay is unchanged." }
    }
    func exportPrintPreview() {
        guard let snapshot = printPreview else { return }
        let panel = NSSavePanel()
        panel.title = "Export PDF"
        panel.nameFieldStringValue = originalSource.deletingPathExtension().lastPathComponent + ".pdf"
        panel.directoryURL = originalSource.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try snapshot.data.write(to: url, options: .atomic) }
        catch { message = "The PDF could not be exported. Your screenplay is unchanged." }
    }
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
                Button("Print Preview", action: editor.showPrintPreview)
                Button("Save Edited Copy…") { editor.savePanel() }
            }
            Divider()
            if let row = editor.rows.first(where: { $0.id == editor.selected }) {
                Picker("Paragraph type", selection: Binding(get: { row.type }, set: editor.changeType)) {
                    ForEach(PackageTextSession.supportedTypes, id: \.self) { type in
                        Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                    }
                }.frame(maxWidth: 320)
            }
            if editor.rows.isEmpty {
                Text("This screenplay has no paragraphs. Add a paragraph to begin.").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PackageParagraphTextView(editor: editor)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !editor.characterSuggestions.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            Text("Characters:").foregroundStyle(.secondary)
                            ForEach(Array(editor.characterSuggestions.enumerated()), id: \.element) { index, name in
                                Button(name) { editor.acceptCharacterSuggestion(name) }
                                    .fontWeight(editor.highlightedSuggestion == index ? .bold : .regular)
                                    .foregroundStyle(editor.highlightedSuggestion == index ? Color.accentColor : Color.primary)
                                    .lineLimit(1).frame(maxWidth: 140).help(name)
                                    .accessibilityLabel("Use character " + name)
                            }
                            Button("Dismiss", action: editor.dismissCharacterSuggestions)
                        }
                    }
                    Text("↓ selects a name; Return accepts it. Escape dismisses.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Character names from this screenplay appear as you type a character cue.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: 48, alignment: .leading)
            HStack {
                Button("Add Paragraph", action: editor.addParagraph)
                Button("Delete Paragraph", action: editor.deleteParagraph).disabled(editor.selected == nil)
                Spacer()
            }
            Text("Tab / Shift-Tab change paragraph type. Return creates a paragraph. Backspace at its start joins the previous paragraph. Shift-Return inserts a line break. Print Preview shows derived pages. Production locks are not supported here.")
                .font(.caption).foregroundStyle(.secondary)
            if let recovery = editor.recoveryStatus { Text(recovery).font(.caption).foregroundStyle(.secondary) }
            if let message = editor.message { Text(message).font(.callout).textSelection(.enabled) }
        }.padding(16).frame(minWidth: 740, idealWidth: 850, minHeight: 520, idealHeight: 650)
            .interactiveDismissDisabled()
            .sheet(item: $editor.printPreview) { snapshot in
                PrintPreviewSheet(snapshot: snapshot, export: editor.exportPrintPreview)
            }
    }
}
