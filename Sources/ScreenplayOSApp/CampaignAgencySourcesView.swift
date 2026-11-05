import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain

@MainActor
struct CampaignAgencySourcesView: View {
    @ObservedObject var session: CampaignWorkspaceSession
    @Binding var selectedDocumentID: UUID?
    @State private var preview: CampaignAgencyImport.Preview?
    @State private var previewDocumentID: UUID?
    @State private var problem: String?
    @State private var reviewer = ""
    @State private var reviewNote = ""
    @State private var firstLine = "1"
    @State private var lastLine = "1"
    @State private var targetKind: CampaignAgencyTargetKind = .deliverable
    @State private var targetID: UUID?
    @State private var citationNote = ""

    private var workspace: CampaignAgencyWorkspace? { session.ledger.draft.agency }
    private var selected: CampaignAgencyRevision? {
        guard let selectedDocumentID else { return workspace?.latestRevisions.last }
        return workspace?.latestRevision(documentID: selectedDocumentID)
    }
    private var excerpt: String? {
        guard let selected, let first = Int(firstLine), let last = Int(lastLine) else { return nil }
        return try? selected.excerpt(firstLine: first, lastLine: last)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import an agency script, brief or bid letter as UTF-8 text. Verify exported text against the original before using it. Nothing is uploaded and the screenplay is not changed.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Supported: .txt, .md and .fountain, up to 256 KiB each; 1 MiB / 32 retained revisions total. No PDF, Word, image or OCR extraction. Imported source text can contain confidential material and will be included in your private campaign backup.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Choose New Source…") { chooseSource(revising: nil) }.disabled(preview != nil)
                    if let selected {
                        Button("Choose Revised Text…") { chooseSource(revising: selected.documentID) }.disabled(preview != nil)
                    }
                }
                if let preview { importPreview(preview) }
                if let problem { Text(problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if let workspace, !workspace.latestRevisions.isEmpty {
                    Picker("Source document", selection: $selectedDocumentID) {
                        Text("Latest imported document").tag(Optional<UUID>.none)
                        ForEach(workspace.latestRevisions) { revision in
                            Text(revision.filename).tag(Optional(revision.documentID))
                        }
                    }
                    if let selected { sourceDetail(selected, workspace: workspace) }
                    let warnings = workspace.warnings(draft: session.ledger.draft)
                    if !warnings.isEmpty {
                        Divider()
                        Text("Reconciliation needed").font(.headline)
                        ForEach(warnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.caption).textSelection(.enabled)
                        }
                        Text("Review the new revision, then remove and recreate any outdated citations against current lines and scope. Freezing another baseline does not clear these warnings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if preview == nil {
                    Text("No agency sources imported. You can still use manual bid assumptions and baselines.")
                        .foregroundStyle(.secondary)
                }
            }.padding(.vertical, 12)
        }
        .onChange(of: selected?.id) { _ in
            reviewer = ""; reviewNote = ""; firstLine = "1"; lastLine = "1"; citationNote = ""
        }
        .onChange(of: targetKind) { _ in targetID = nil }
    }

    private func chooseSource(revising documentID: UUID?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, UTType(filenameExtension: "md"), UTType(filenameExtension: "fountain")].compactMap { $0 }
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose local UTF-8 text for preview. Nothing is imported until you confirm the preview."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            preview = try CampaignAgencyImport.read(url); previewDocumentID = documentID; problem = nil
        } catch { problem = error.localizedDescription }
    }

    private func importPreview(_ preview: CampaignAgencyImport.Preview) -> some View {
        GroupBox("Preview before importing") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(preview.filename) · \(preview.bytes.count) bytes")
                if let documentID = previewDocumentID {
                    Text("New revision of \(workspace?.latestRevision(documentID: documentID)?.filename ?? documentID.uuidString). Prior evidence remains saved. Existing review and citations will need reconciliation.")
                        .font(.caption).foregroundStyle(.orange)
                }
                sourceText(preview.text, height: 180)
                HStack {
                    Button("Cancel Import") { self.preview = nil; previewDocumentID = nil; problem = nil }
                    Spacer()
                    Button("Import Exact Text Locally") {
                        if session.importAgencyText(preview, revisingDocumentID: previewDocumentID) {
                            selectedDocumentID = previewDocumentID ?? session.ledger.draft.agency?.latestRevisions.last?.documentID
                            self.preview = nil; previewDocumentID = nil; problem = nil
                        }
                    }
                }
            }.padding(6)
        }
    }

    private func sourceDetail(_ revision: CampaignAgencyRevision, workspace: CampaignAgencyWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(revision.filename) · imported \(revision.importedAt.formatted())").font(.headline)
            Text("Revision \(revision.id.uuidString)\nSHA-256 \(revision.sha256)")
                .font(.caption.monospaced()).textSelection(.enabled)
            Text("\(revision.lines.count) lines. Line numbers use LF/CRLF text lines, not the original document’s pages. The hash identifies imported bytes, not the sender or authenticity of the source.")
                .font(.caption).foregroundStyle(.secondary)
            sourceText(numberedText(revision), height: 200)
            if let priorID = revision.priorRevisionID,
               let previous = workspace.revisions.first(where: { $0.id == priorID }) {
                DisclosureGroup("Previous revision: \(previous.filename)") {
                    Text("SHA-256 \(previous.sha256)").font(.caption.monospaced()).textSelection(.enabled)
                    sourceText(numberedText(previous), height: 180)
                }
            }
            if let review = workspace.currentReview(revisionID: revision.id) {
                Label("Reviewed locally by \(review.reviewer)", systemImage: "checkmark.circle")
                Text(review.note).font(.caption).textSelection(.enabled)
                citationEditor(revision)
            } else {
                Text("Read the source and compare revised text against its previous version. This review does not approve creative work or authorize spend.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Reviewed by", text: $reviewer).textFieldStyle(.roundedBorder)
                TextField("Review note / changes found", text: $reviewNote, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button("Record Source Review") {
                    if session.reviewAgencyRevision(revision.id, reviewer: reviewer, note: reviewNote) { reviewer = ""; reviewNote = "" }
                }.disabled(reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            citations(revision, workspace: workspace)
        }
    }

    private func citationEditor(_ revision: CampaignAgencyRevision) -> some View {
        GroupBox("Link reviewed lines to campaign scope") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("First line", text: $firstLine).accessibilityLabel("First source line").frame(width: 90)
                    Text("through")
                    TextField("Last line", text: $lastLine).accessibilityLabel("Last source line").frame(width: 90)
                    Spacer()
                    Picker("Target type", selection: $targetKind) {
                        Text("Deliverable").tag(CampaignAgencyTargetKind.deliverable)
                        Text("Assumption").tag(CampaignAgencyTargetKind.assumption)
                    }.frame(width: 220)
                }
                Picker("Campaign target", selection: $targetID) {
                    Text("Choose target").tag(Optional<UUID>.none)
                    if targetKind == .deliverable {
                        ForEach(session.ledger.draft.deliverables) { item in Text(item.name).tag(Optional(item.id)) }
                    } else {
                        ForEach(session.ledger.draft.assumptions) { item in Text(item.text).tag(Optional(item.id)) }
                    }
                }
                if let excerpt { sourceText(excerpt, height: 90) }
                else { Text("Enter a valid inclusive line range from this source.").font(.caption).foregroundStyle(.orange) }
                TextField("Why these lines support the target", text: $citationNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                Button("Add Reviewed Citation") {
                    guard let first = Int(firstLine), let last = Int(lastLine), let targetID else { return }
                    if session.citeAgencyRevision(revision.id, firstLine: first, lastLine: last,
                                                  targetKind: targetKind, targetID: targetID, note: citationNote) { citationNote = "" }
                }.disabled(excerpt == nil || targetID == nil || citationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Links retain exact source and target revisions. Later changes require review; no scope text or screenplay is automatically rewritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }

    private func citations(_ revision: CampaignAgencyRevision, workspace: CampaignAgencyWorkspace) -> some View {
        let linked = workspace.citations.filter { $0.documentID == revision.documentID }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Source citations (\(linked.count))").font(.headline)
            ForEach(linked) { citation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(citation.targetKind.rawValue.capitalized): \(targetName(citation)) · lines \(citation.firstLine)–\(citation.lastLine)")
                            .font(.callout)
                        Spacer()
                        Button("Remove Citation") { session.removeAgencyCitation(citation.id) }
                    }
                    Text("Revision \(citation.revisionID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                    Text(citation.note).font(.caption).textSelection(.enabled)
                    if let source = workspace.revisions.first(where: { $0.id == citation.revisionID }),
                       let text = try? source.excerpt(firstLine: citation.firstLine, lastLine: citation.lastLine) {
                        DisclosureGroup("Cited source text") { sourceText(text, height: 90) }
                    }
                }
                Divider()
            }
        }
    }

    private func targetName(_ citation: CampaignAgencyCitation) -> String {
        if citation.targetKind == .deliverable {
            return session.ledger.draft.deliverables.first { $0.id == citation.targetID }?.name ?? "Missing deliverable"
        }
        return session.ledger.draft.assumptions.first { $0.id == citation.targetID }?.text ?? "Missing assumption"
    }

    private func numberedText(_ revision: CampaignAgencyRevision) -> String {
        revision.lines.enumerated().map { "\($0.offset + 1)  \($0.element)" }.joined(separator: "\n")
    }

    private func sourceText(_ text: String, height: CGFloat) -> some View {
        // A read-only native text surface, not interpreted Markdown or a WebView.
        CampaignReadOnlyText(text: text).frame(height: height).border(Color.secondary.opacity(0.25))
    }
}

private struct CampaignReadOnlyText: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false; view.isSelectable = true; view.isRichText = false
            view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            view.textContainerInset = NSSize(width: 6, height: 6)
            view.setAccessibilityLabel("Imported agency source text")
        }
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let editor = view.documentView as? NSTextView else { return }
        if !editor.string.utf8.elementsEqual(text.utf8) { editor.string = text }
    }
}
