import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScreenplayDomain

@MainActor
struct CampaignAgencySourcesView: View {
    @ObservedObject var session: CampaignWorkspaceSession
    @Binding var selectedDocumentID: UUID?
    @StateObject private var importLifecycle: CampaignAgencyImportLifecycle
    private let privateExportLifecycle: CampaignPrivateExportLifecycle?
    private let currentContext: () -> CampaignRecoveryContext?
    @State private var reviewer = ""
    @State private var reviewNote = ""
    @State private var firstLine = "1"
    @State private var lastLine = "1"
    @State private var targetKind: CampaignAgencyTargetKind = .deliverable
    @State private var targetID: UUID?
    @State private var citationNote = ""
    @State private var reconciliation: CampaignAgencyReconciliationContext?

    init(session: CampaignWorkspaceSession, selectedDocumentID: Binding<UUID?>,
         importLifecycle: CampaignAgencyImportLifecycle? = nil,
         privateExportLifecycle: CampaignPrivateExportLifecycle? = nil,
         currentContext: @escaping () -> CampaignRecoveryContext?) {
        self.session = session
        _selectedDocumentID = selectedDocumentID
        _importLifecycle = StateObject(wrappedValue: importLifecycle ?? CampaignAgencyImportLifecycle())
        self.privateExportLifecycle = privateExportLifecycle
        self.currentContext = currentContext
    }

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
                Text("Import an agency script, brief or bid letter as text or a supported Word DOCX. Verify extracted text against the original before using it. Nothing is uploaded and the screenplay is not changed.")
                    .font(.callout).foregroundStyle(.secondary)
                    .id("campaign.section.agencySources")
                Text("Text: .txt, .md, .fountain, up to 256 KiB. DOCX: up to 2 MiB, with bounded text extraction. PDF remains disabled pending parser isolation; no legacy .doc or OCR. Originals and extracted text are retained in private campaign backups and may contain confidential material.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Choose New Source…") { chooseSource(revising: nil) }.disabled(importLifecycle.preview != nil || importLifecycle.isReading || reconciliation != nil)
                        .accessibilityIdentifier("campaign.agency.choose.new")
                    if let selected {
                        Button("Choose Revised Source…") { chooseSource(revising: selected.documentID) }.disabled(importLifecycle.preview != nil || importLifecycle.isReading || reconciliation != nil)
                            .accessibilityIdentifier("campaign.agency.choose.revision")
                    }
                }
                if importLifecycle.isReading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading local document…").font(.callout)
                        Spacer()
                        Button("Cancel Reading", action: importLifecycle.cancel)
                    }
                }
                if let preview = importLifecycle.preview { importPreview(preview) }
                if let problem = importLifecycle.problem { Text(problem).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if let workspace, !workspace.latestRevisions.isEmpty {
                    Picker("Source document", selection: $selectedDocumentID) {
                        Text("Latest imported document").tag(Optional<UUID>.none)
                        ForEach(workspace.latestRevisions) { revision in
                            Text(revision.filename).tag(Optional(revision.documentID))
                        }
                    }
                    .accessibilityIdentifier("campaign.agency.document")
                    if let reconciliation {
                        CampaignAgencyReconciliationView(session: session, context: reconciliation) {
                            self.reconciliation = nil
                        }.id(reconciliation.citation.id)
                    } else if let selected { sourceDetail(selected, workspace: workspace) }
                    let warnings = workspace.warnings(draft: session.ledger.draft)
                    if !warnings.isEmpty {
                        Divider()
                        Text("Reconciliation needed").font(.headline)
                        ForEach(warnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.caption).textSelection(.enabled)
                        }
                        Text("Review the current revision, then use Reconcile Citation to preview and replace an outdated link, or remove it. Freezing another baseline does not clear these warnings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if importLifecycle.preview == nil {
                    Text("No agency sources imported. You can still use manual bid assumptions and baselines.")
                        .foregroundStyle(.secondary)
                }
            }.padding(.vertical, 12)
        }
        .onChange(of: selectedDocumentID) { _ in resetEditors() }
        .onChange(of: selected?.id) { _ in resetEditors() }
        .onChange(of: session.ledger.projectID) { _ in resetEditors() }
        .onChange(of: targetKind) { _ in targetID = nil }
        .onDisappear { importLifecycle.cancel(); resetEditors() }
    }

    private func chooseSource(revising documentID: UUID?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.plainText, UTType(filenameExtension: "md"), UTType(filenameExtension: "fountain"), UTType(filenameExtension: "docx")].compactMap { $0 }
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose local text or DOCX for preview. Nothing is imported until you confirm the extraction and its limits."
        importLifecycle.chooseSource(revising: documentID) {
            panel.runModal() == .OK ? panel.url : nil
        }
    }

    private func importPreview(_ preview: CampaignAgencyImport.Preview) -> some View {
        GroupBox("Preview before importing") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(preview.filename) · \(preview.bytes.count) extracted UTF-8 bytes")
                if let origin = preview.origin {
                    Text("Original: \(origin.originalBytes.count) bytes · SHA-256 \(origin.originalSHA256)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    ForEach(origin.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    Text("Both the exact original file and this extracted text will be retained locally. Extraction is not proof that every meaningful part of the original was captured.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let documentID = importLifecycle.previewDocumentID {
                    Text("New revision of \(workspace?.latestRevision(documentID: documentID)?.filename ?? documentID.uuidString). Prior evidence remains saved. Existing review and citations will need reconciliation.")
                        .font(.caption).foregroundStyle(.orange)
                }
                sourceText(preview.text, height: 180)
                HStack {
                    Button("Cancel Import", action: importLifecycle.cancel)
                        .accessibilityIdentifier("campaign.agency.import.cancel")
                    Spacer()
                    Button("Import Preview Locally") {
                        if let documentID = importLifecycle.importPreview(into: session) {
                            selectedDocumentID = documentID
                        }
                    }
                    .accessibilityIdentifier("campaign.agency.import.confirm")
                }
            }.padding(6)
        }
    }

    private func sourceDetail(_ revision: CampaignAgencyRevision, workspace: CampaignAgencyWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(revision.filename) · imported \(revision.importedAt.formatted())").font(.headline)
            Text("Revision \(revision.id.uuidString)\nSHA-256 \(revision.sha256)")
                .font(.caption.monospaced()).textSelection(.enabled)
            Text("\(revision.lines.count) extracted lines. Line numbers use LF/CRLF text lines. The text hash identifies retained text, not the sender or authenticity of the original.")
                .font(.caption).foregroundStyle(.secondary)
            if let origin = revision.origin {
                Text("Original \(origin.format.uppercased()) · \(origin.originalBytes.count) bytes · \(origin.extractor)")
                    .font(.caption)
                Text("Original SHA-256 \(origin.originalSHA256)").font(.caption.monospaced()).textSelection(.enabled)
                ForEach(origin.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Button("Save Retained Original…") {
                    _ = session.exportAgencyOriginal(revision.id, lifecycle: privateExportLifecycle,
                                                    currentContext: {
                        guard selected?.id == revision.id else { return nil }
                        return currentContext()
                    })
                }
                .disabled(session.isPerformingRecoveryCommand)
                .accessibilityIdentifier("campaign.agency.exportOriginal.\(revision.id)")
            }
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
                    .accessibilityIdentifier("campaign.agency.reviewer")
                TextField("Review note / changes found", text: $reviewNote, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("campaign.agency.reviewNote")
                Button("Record Source Review") {
                    if session.reviewAgencyRevision(revision.id, reviewer: reviewer, note: reviewNote) { reviewer = ""; reviewNote = "" }
                }.disabled(reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("campaign.agency.review")
            }
            citations(revision, workspace: workspace)
        }
    }

    private func citationEditor(_ revision: CampaignAgencyRevision) -> some View {
        GroupBox("Link reviewed lines to campaign scope") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("First line", text: $firstLine).accessibilityLabel("First source line").frame(width: 90)
                        .accessibilityIdentifier("campaign.agency.citation.firstLine")
                    Text("through")
                    TextField("Last line", text: $lastLine).accessibilityLabel("Last source line").frame(width: 90)
                        .accessibilityIdentifier("campaign.agency.citation.lastLine")
                    Spacer()
                    Picker("Target type", selection: $targetKind) {
                        Text("Deliverable").tag(CampaignAgencyTargetKind.deliverable)
                        Text("Assumption").tag(CampaignAgencyTargetKind.assumption)
                    }.frame(width: 220)
                        .accessibilityIdentifier("campaign.agency.citation.targetKind")
                }
                Picker("Campaign target", selection: $targetID) {
                    Text("Choose target").tag(Optional<UUID>.none)
                    if targetKind == .deliverable {
                        ForEach(session.ledger.draft.deliverables) { item in Text(item.name).tag(Optional(item.id)) }
                    } else {
                        ForEach(session.ledger.draft.assumptions) { item in Text(item.text).tag(Optional(item.id)) }
                    }
                }
                .accessibilityIdentifier("campaign.agency.citation.target")
                if let excerpt { sourceText(excerpt, height: 90) }
                else { Text("Enter a valid inclusive line range from this source.").font(.caption).foregroundStyle(.orange) }
                TextField("Why these lines support the target", text: $citationNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .accessibilityIdentifier("campaign.agency.citation.note")
                Button("Add Reviewed Citation") {
                    guard let first = Int(firstLine), let last = Int(lastLine), let targetID else { return }
                    if session.citeAgencyRevision(revision.id, firstLine: first, lastLine: last,
                                                  targetKind: targetKind, targetID: targetID, note: citationNote) { citationNote = "" }
                }.disabled(excerpt == nil || targetID == nil || citationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("campaign.agency.citation.add")
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
                        Button("Reconcile Citation…") { beginReconciliation(citation, current: revision, workspace: workspace) }
                            .disabled(workspace.currentReview(revisionID: revision.id) == nil)
                            .accessibilityIdentifier("campaign.agency.reconcile.\(citation.id)")
                        Button("Remove Citation") { session.removeAgencyCitation(citation.id) }
                            .accessibilityIdentifier("campaign.agency.removeCitation.\(citation.id)")
                    }
                    Text("Revision \(citation.revisionID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                    if workspace.currentReview(revisionID: revision.id) == nil {
                        Text("Record a review of the current source above before reconciling this citation.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(workspace.warnings(draft: session.ledger.draft).filter { $0.sourceID == citation.id }) { warning in
                        Text(warning.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
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

    private func resetEditors() {
        reconciliation = nil
        reviewer = ""; reviewNote = ""; firstLine = "1"; lastLine = "1"
        targetID = nil; citationNote = ""
    }

    private func beginReconciliation(_ citation: CampaignAgencyCitation, current: CampaignAgencyRevision,
                                     workspace: CampaignAgencyWorkspace) {
        guard let review = workspace.currentReview(revisionID: current.id),
              let original = workspace.revisions.first(where: { $0.id == citation.revisionID }) else { return }
        importLifecycle.cancel()
        reconciliation = CampaignAgencyReconciliationContext(projectID: session.ledger.projectID,
            citation: citation, originalRevision: original, currentRevision: current, review: review)
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
