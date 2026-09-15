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
    @Published var darkPageMode = false
    @Published var navigationVisible = false
    @Published private(set) var currentURL: URL?
    private var savedFiles: [String: Data] = [:]
    var didSave: ((URL) -> Void)?
    @Published var previousVersionURL: URL?
    let title: String
    @Published private(set) var session: PackageTextSession {
        didSet {
            guard session.revision != oldValue.revision, !replayingHistory else { return }
            if let id = session.undoHistoryID {
                if selectionHistory[id] == nil { selectionHistory[id] = (writingSelection, writingSelection) }
                pendingHistorySelection = id
            }
            selectionHistory = selectionHistory.filter { session.historyIDs.contains($0.key) }
        }
    }
    var typingBoundary = UUID()
    @Published var writingSelection = NSRange(location: 0, length: 0)
    var restoredWritingSelection: NSRange?
    private var selectionHistory: [UUID: (before: NSRange, after: NSRange)] = [:]
    private var pendingHistorySelection: UUID?
    private var replayingHistory = false
    func didRenderWritingSelection(_ range: NSRange) {
        writingSelection = range
        if let id = pendingHistorySelection { selectionHistory[id]?.after = range }
        pendingHistorySelection = nil
    }
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
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var replacementText = ""
    @Published var matchCase = false
    @Published var findFocusRequest = UUID()
    @Published var requestedFindSelection: NSRange?
    var findMatches: [(match: PackageTextSession.TextMatch, range: NSRange)] {
        let projection = PackageWritingProjection(session)
        let starts = Dictionary(uniqueKeysWithValues: projection.entries.map { ($0.id, $0.range.location) })
        return session.find(findQuery, caseSensitive: matchCase).compactMap { match in
            starts[match.elementID].map { (match, NSRange(location: $0 + match.range.location, length: match.range.length)) }
        }
    }
    var currentFindMatch: Int? { findMatches.firstIndex { $0.range == writingSelection } }
    func showFind() {
        typingBoundary = UUID(); dismissCharacterSuggestions()
        findVisible = true; findFocusRequest = UUID()
    }
    func closeFind() {
        findVisible = false; requestedFindSelection = writingSelection
    }
    func navigateFind(backward: Bool = false) {
        typingBoundary = UUID()
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let index = backward
            ? (matches.lastIndex { $0.range.location < writingSelection.location } ?? matches.count - 1)
            : (matches.firstIndex { $0.range.location >= NSMaxRange(writingSelection) } ?? 0)
        requestedFindSelection = matches[index].range
    }
    func replaceFound(all: Bool) {
        typingBoundary = UUID()
        guard apply() else { return }
        let matches = findMatches
        let chosen = all ? matches : matches.filter { $0.range == writingSelection }
        guard !chosen.isEmpty else { return }
        do {
            try session.replaceMatches(chosen.map(\.match), expectedRevision: session.revision, replacement: replacementText)
            if !all, let first = chosen.first {
                requestedFindSelection = NSRange(location: first.range.location, length: (replacementText as NSString).length)
            }
            refreshDraft(); scheduleRecovery()
            message = "Replaced \(chosen.count) match\(chosen.count == 1 ? "" : "es")."
        } catch { message = "The matches changed. Search again before replacing; your screenplay is unchanged." }
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
            let files = candidate.currentFiles
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
        currentURL = nil
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
    var dirty: Bool { pending || session.screenplayBytes != savedBytes || session.settingsBytes != savedFiles["settings.json"] }
    var canUndo: Bool { pending || session.canUndo }
    var canRedo: Bool { !pending && session.canRedo }

    init(source: URL, recoveryDirectory: URL? = nil) throws {
        let loaded = try PackageEditedCopy.load(source)
        self.source = source
        self.currentURL = source
        self.originalSource = source
        self.recoveryDirectory = recoveryDirectory
        savedFiles = loaded.originalFiles
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
    @Published private(set) var insertionStyleOverride: StyledText.Style?
    func moveWritingSelection(_ range: NSRange) {
        if range != writingSelection { insertionStyleOverride = nil }
        writingSelection = range
    }
    var caretStyle: StyledText.Style {
        if let insertionStyleOverride { return insertionStyleOverride }
        let projection = PackageWritingProjection(session)
        guard let (entry, index) = projection.position(writingSelection.location),
              let value = try? session.styledText(for: entry.id) else { return .init() }
        let offset = entry.text.unicodeScalars.distance(from: entry.text.startIndex, to: index)
        let point = max(0, offset - 1)
        return value.resolvedRuns.first { point >= $0.start && point < $0.start + $0.length }?.style ?? .init()
    }
    func emphasisActive(_ key: KeyPath<StyledText.Style, Bool?>) -> Bool {
        guard writingSelection.length > 0 else { return caretStyle[keyPath: key] == true }
        var found = false
        for entry in PackageWritingProjection(session).entries {
            let overlap = NSIntersectionRange(writingSelection, entry.range)
            guard overlap.length > 0, let value = try? session.styledText(for: entry.id),
                  let scalars = try? value.scalarRange(fromUTF16: NSRange(location: overlap.location - entry.range.location, length: overlap.length)) else { continue }
            found = true
            let covered = value.resolvedRuns.filter { $0.style[keyPath: key] == true }.reduce(0) { total, run in
                total + max(0, min(scalars.upperBound, run.start + run.length) - max(scalars.lowerBound, run.start))
            }
            if covered != scalars.count { return false }
        }
        return found
    }
    func toggleEmphasis(_ key: WritableKeyPath<StyledText.Style, Bool?>) {
        var patch = StyledText.Style(); patch[keyPath: key] = !emphasisActive(key)
        formatSelection(patch)
    }
    func formatSelection(_ patch: StyledText.Style) {
        let selection = writingSelection
        guard apply() else { return }
        if selection.length == 0 {
            var style = caretStyle
            if let value = patch.bold { style.bold = value }
            if let value = patch.italic { style.italic = value }
            if let value = patch.underline { style.underline = value }
            if let value = patch.strikethrough { style.strikethrough = value }
            insertionStyleOverride = style; typingBoundary = UUID()
            return
        }
        insertionStyleOverride = nil
        typingBoundary = UUID()
        do {
            try session.formatSelection(selection, expectedRevision: session.revision, patch: patch)
            restoredWritingSelection = selection
            scheduleRecovery()
        } catch { message = "Select complete characters to apply formatting." }
    }
    func changeTypography(font: String? = nil, size: Double? = nil) {
        guard apply() else { return }
        typingBoundary = UUID()
        do {
            let value = try DocumentTypography(fontFamily: font ?? session.typography.fontFamily, fontSize: size ?? session.typography.fontSize)
            try session.setTypography(value, expectedRevision: session.revision)
            scheduleRecovery()
        } catch { message = "That font or size could not be applied." }
    }
    func undo() {
        insertionStyleOverride = nil
        typingBoundary = UUID()
        if pending { refreshDraft(); return }
        let oldIDs = Set(rows.map(\.id)), oldIndex = rows.firstIndex { $0.id == selected } ?? 0
        restoredWritingSelection = session.undoHistoryID.flatMap { selectionHistory[$0]?.before }
        pendingHistorySelection = nil; replayingHistory = true
        session.undo(); replayingHistory = false
        restoreSelection(previousIDs: oldIDs, oldIndex: oldIndex); message = nil
    }
    func redo() {
        insertionStyleOverride = nil
        typingBoundary = UUID()
        guard !pending else { return }
        let oldIDs = Set(rows.map(\.id)), oldIndex = rows.firstIndex { $0.id == selected } ?? 0
        restoredWritingSelection = session.redoHistoryID.flatMap { selectionHistory[$0]?.after }
        pendingHistorySelection = nil; replayingHistory = true
        session.redo(); replayingHistory = false
        restoreSelection(previousIDs: oldIDs, oldIndex: oldIndex); message = nil
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
    func navigateToScene(_ id: UUID) {
        guard rows.contains(where: { $0.id == id && $0.type == "scene_heading" }), apply(),
              let entry = PackageWritingProjection(session).entries.first(where: { $0.id == id }) else { return }
        typingBoundary = UUID()
        selected = id; refreshDraft()
        requestedFindSelection = NSRange(location: entry.range.location, length: 0)
    }
    func selectWritingParagraph(_ id: UUID) {
        guard selected != id else { return }
        selected = id; refreshDraft()
    }
    @discardableResult func editWritingSpan(start: UUID, end: UUID, prefix: String, replacement: String, suffix: String, splitType: String?, historyGroup: UUID? = nil) -> Bool {
        do {
            selected = try session.editSpan(startID: start, endID: end, expectedRevision: session.revision,
                prefix: prefix, replacement: replacement, suffix: suffix, splitType: splitType, historyGroup: historyGroup, insertionStyleOverride: insertionStyleOverride)
            refreshDraft(); message = nil; return true
        } catch { message = "The edit could not be applied. Your previous text is retained."; return false }
    }
    func showPrintPreview() {
        typingBoundary = UUID()
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
        typingBoundary = UUID()
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        for package in [source, currentURL].compactMap({ $0 }) {
            let path = package.standardizedFileURL.resolvingSymlinksInPath().path
            guard target != path, !target.hasPrefix(path + "/") else {
                message = "Choose a new location outside the current package."; return false
            }
        }
        guard apply() else { return false }
        flushRecovery()
        do {
            let result = try PackageCurrentSave.write(session, base: savedFiles, destination: url, replacing: false)
            adoptSave(result)
            message = "Saved and verified: " + result.destination.path
            return true
        } catch let error as PackageCurrentSave.RetainedFailure {
            message = "Save could not be verified. Your edits remain open. Retained output: " + error.location.path
        } catch let error as PackageEditedCopy.RetainedFailure {
            message = "Save could not be verified. Keep this editor open. Retained output (may be incomplete): " + error.recoveryURL.path
        } catch {
            message = "Could not save this copy. The source may have changed or the destination may be unavailable. Your edits remain here. Choose a new destination and keep this editor open."
        }
        return false
    }
    private func adoptSave(_ result: PackageCurrentSave.Receipt) {
        previousVersionURL = result.previous
        currentURL = result.destination; originalSource = result.destination
        savedFiles = result.files; savedBytes = session.screenplayBytes
        discardRecovery(); didSave?(result.destination)
    }
    @discardableResult func saveCurrent(checkpoint: (String, URL) throws -> Void = { _, _ in }) -> Bool {
        guard let currentURL else { return savePanel() }
        typingBoundary = UUID()
        guard apply() else { return false }
        flushRecovery()
        do {
            let result = try PackageCurrentSave.write(session, base: savedFiles, destination: currentURL, replacing: true, checkpoint: checkpoint)
            adoptSave(result)
            message = "Saved: " + result.destination.path

            return true
        } catch let error as PackageCurrentSave.RetainedFailure {
            message = "Save not verified. Keep editing or save a new copy. Retained files: " + error.location.path
        } catch {
            message = "Save stopped: the file changed outside this editor or is unavailable. Your edits remain here. Save a new copy to keep both versions."
        }
        return false
    }
    static func newPackage(directory: URL, title: String = "Untitled Screenplay", recoveryDirectory: URL? = nil) throws -> PackageEditor {
        let source = directory.appendingPathComponent(UUID().uuidString + ".screenplay")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let id = UUID().uuidString, time = ISO8601DateFormatter().string(from: Date())
        let manifest = ["format": "open-screenplay", "format_version": "1.0", "document_id": id,
                        "title": title, "author": "", "created_at": time, "modified_at": time]
        let script: [String: Any] = ["id": id, "elements": [["id": UUID().uuidString, "type": "scene_heading", "text": ""]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: source.appendingPathComponent("manifest.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: script).write(to: source.appendingPathComponent("screenplay.json"), options: .atomic)
        let editor = try PackageEditor(source: source, recoveryDirectory: recoveryDirectory)
        editor.currentURL = nil; editor.savedBytes = Data(); editor.flushRecovery()
        return editor
    }
    @discardableResult func savePanel() -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save Package As"
        panel.directoryURL = currentURL?.deletingLastPathComponent() ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.prompt = "Save Copy"
        panel.nameFieldStringValue = currentURL == nil ? title + ".screenplay" : originalSource.deletingPathExtension().lastPathComponent + " Copy.screenplay"
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        if url.pathExtension != "screenplay" { url.appendPathExtension("screenplay") }
        return save(to: url)
    }
    func confirmClose() -> Bool {
        guard dirty else { discardRecovery(); return true }
        flushRecovery()
        let alert = NSAlert()
        alert.messageText = "Save your package edits before closing?"
        alert.informativeText = "These edits have not been saved to the current file. Keep editing, save, or retain recovery before closing."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        if recoveryDirectory != nil { alert.addButton(withTitle: "Keep Recovery for Later") }
        switch alert.runModal() {
        case .alertSecondButtonReturn: return saveCurrent()
        case .alertThirdButtonReturn: discardRecovery(); return true
        case NSApplication.ModalResponse(rawValue: 1003): return flushRecovery()
        default: return false
        }
    }
}

struct PackageEditorView: View {
    @FocusState private var findFocused: Bool
    @State private var showWritingHelp = false
    @State private var pageZoomPercent = 100
    @ObservedObject var editor: PackageEditor
    let close: () -> Void
    private var formatMenu: some View {
        Menu("Format") {
                Menu("Document Font: " + editor.session.typography.fontFamily) {
                    ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                        Button(family) { editor.changeTypography(font: family) }
                    }
                }
                Menu("Document Size: " + String(format: "%g pt", editor.session.typography.fontSize)) {
                    ForEach([8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72], id: \.self) { size in
                        Button("\(size) pt") { editor.changeTypography(size: Double(size)) }
                    }
                }
                Divider()
                Toggle("Bold", isOn: Binding(get: { editor.emphasisActive(\.bold) }, set: { _ in editor.toggleEmphasis(\.bold) })).keyboardShortcut("b", modifiers: .command)
                Toggle("Italic", isOn: Binding(get: { editor.emphasisActive(\.italic) }, set: { _ in editor.toggleEmphasis(\.italic) })).keyboardShortcut("i", modifiers: .command)
                Toggle("Underline", isOn: Binding(get: { editor.emphasisActive(\.underline) }, set: { _ in editor.toggleEmphasis(\.underline) })).keyboardShortcut("u", modifiers: .command)
                Toggle("Strikethrough", isOn: Binding(get: { editor.emphasisActive(\.strikethrough) }, set: { _ in editor.toggleEmphasis(\.strikethrough) }))
                Button("Clear Emphasis") { editor.formatSelection(.init(bold: false, italic: false, underline: false, strikethrough: false)) }
            }.fixedSize().disabled(findFocused)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(editor.title.isEmpty ? "Untitled Screenplay" : editor.title)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(editor.dirty ? "Unsaved" : "Saved").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Save") { editor.saveCurrent() }
                Menu("Document") {
                    Button("Save As…") { editor.savePanel() }
                    Button("Print Preview", action: editor.showPrintPreview)
                    if let previous = editor.previousVersionURL {
                        Button("Show Previous Version") { NSWorkspace.shared.activateFileViewerSelecting([previous]) }
                    }
                    Divider()
                    Button("Close", action: close)
                }.fixedSize()
            }
            HStack(spacing: 12) {
                Button(action: editor.undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .labelStyle(.iconOnly).help("Undo").disabled(!editor.canUndo)
                Button(action: editor.redo) { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .labelStyle(.iconOnly).help("Redo").disabled(!editor.canRedo)
                if let row = editor.rows.first(where: { $0.id == editor.selected }) {
                    Picker("Paragraph type", selection: Binding(get: { row.type }, set: editor.changeType)) {
                        ForEach(PackageTextSession.supportedTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                        }
                    }.labelsHidden().frame(width: 155).accessibilityLabel("Paragraph type")
                }
                formatMenu
                Spacer(minLength: 8)
                Button("Find", action: editor.showFind)
                Menu("Writing") {
                    Toggle("Dark Page", isOn: $editor.darkPageMode)
                    Divider()
                    Button("Add Paragraph", action: editor.addParagraph)
                    Button("Delete Paragraph", action: editor.deleteParagraph).disabled(editor.selected == nil)
                    Divider()
                    Button("Writing Help") { showWritingHelp = true }
                }.fixedSize()
            }
            if editor.findVisible {
                VStack(spacing: 6) {
                    HStack {
                        TextField("Find", text: $editor.findQuery).focused($findFocused)
                            .onSubmit { editor.navigateFind() }.accessibilityLabel("Find text")
                        Toggle("Match case", isOn: $editor.matchCase)
                        Button("Previous") { editor.navigateFind(backward: true) }.disabled(editor.findMatches.isEmpty)
                        Button("Next") { editor.navigateFind() }.disabled(editor.findMatches.isEmpty)
                        Button("Done", action: editor.closeFind)
                    }
                    HStack {
                        TextField("Replace with", text: $editor.replacementText).accessibilityLabel("Replacement text")
                        Text(editor.findQuery.isEmpty ? "" : "\(editor.findMatches.count) matches").foregroundStyle(.secondary)
                        Button("Replace") { editor.replaceFound(all: false) }.disabled(editor.currentFindMatch == nil)
                        Button("Replace All") { editor.replaceFound(all: true) }.disabled(editor.findMatches.isEmpty)
                    }
                }.onExitCommand(perform: editor.closeFind)
                    .onAppear { findFocused = true }
                    .onChange(of: editor.findFocusRequest) { _ in findFocused = true }
            }
            if editor.rows.isEmpty {
                Text("This screenplay has no paragraphs. Add a paragraph to begin.").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if editor.navigationVisible {
                        PackageDocumentNavigator(editor: editor).frame(width: 210)
                        Divider()
                    }
                    ScriptPageWell(width: pageZoomPercent == 0 ? 10_000 : PackagePageGeometry.width * CGFloat(pageZoomPercent) / 100) {
                        PackageParagraphTextView(editor: editor, zoomPercent: pageZoomPercent)
                    }
                }

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
                    }.frame(height: 30)
                    Text("↓ selects a name; Return accepts it. Escape dismisses.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let recovery = editor.recoveryStatus { Text(recovery).font(.caption).foregroundStyle(.secondary) }
            if let substitution = PackageTypography.substitution(editor.session.typography) {
                Text(substitution).font(.callout)
            }
            if let message = editor.message { Text(message).font(.callout).textSelection(.enabled) }
        }.padding(16).frame(minWidth: 740, idealWidth: 850, minHeight: 520, idealHeight: 650)
            .background(StudioAppearance.panel)
            .preferredColorScheme(.dark)
            .safeAreaInset(edge: .top, spacing: 0) { PackageNavigationBar(zoomPercent: $pageZoomPercent, navigationVisible: $editor.navigationVisible) }
            .interactiveDismissDisabled()
            .popover(isPresented: $showWritingHelp) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Writing").font(.headline)
                    Text("Return starts a paragraph. Shift-Return inserts a line break. Backspace at a paragraph’s start joins it to the previous paragraph.")
                    Text("Tab / Shift-Tab change paragraph type. ⌘B, ⌘I and ⌘U toggle bold, italic and underline.")
                    Text("Page numbers and dialogue continuation labels are generated automatically. Production locks are not supported in this editor.")
                }.padding().frame(width: 340)
            }
            .sheet(item: $editor.printPreview) { snapshot in
                PrintPreviewSheet(snapshot: snapshot, export: editor.exportPrintPreview)
            }
    }
}

private struct PackageDocumentNavigator: View {
    @ObservedObject var editor: PackageEditor
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Document").font(.headline)
                Text(editor.title.isEmpty ? "Untitled Screenplay" : editor.title).lineLimit(3)
                Text(editor.dirty ? "Unsaved" : "Saved").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Scenes").font(.headline)
                let scenes = editor.rows.filter { $0.type == "scene_heading" }
                if scenes.isEmpty { Text("No scene headings yet.").foregroundStyle(.secondary) }
                ForEach(Array(scenes.enumerated()), id: \.element.id) { index, row in
                    Button { editor.navigateToScene(row.id) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                            Text(editor.label(for: row)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(6)
                            .background(editor.selected == row.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Go to scene \(index + 1): \(editor.label(for: row))")
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }.background(StudioAppearance.panel)
        .accessibilityLabel("Document navigator")
    }
}
