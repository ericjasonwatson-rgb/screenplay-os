import ScreenplayDomain
import SwiftUI

enum ContinuityBibleWorkflow {
    static func storageURL(projectID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("ScreenplayOS/Continuity/\(projectID.uuidString)/continuity-bible-v1.json")
    }
}

struct ContinuityBibleReviewSheet: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var selection: UUID?
    @State private var adoptedName = ""
    @State private var mergeTarget: UUID?
    @State private var performerName = ""
    @State private var consentNote = ""
    @State private var likenessScope = true
    @State private var voiceScope = false
    @State private var consentExpires = true
    @State private var consentExpiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    private var ledger: ContinuityBibleLedger? { model.continuityBible }
    private var proposals: [ContinuityProposal] { ledger?.proposals ?? [] }
    private var selected: ContinuityProposal? { proposals.first { $0.id == selection } }
    private var selectedEntry: ContinuityBibleEntry? { ledger?.entries.first { $0.id == selection } }
    private var mergeChoices: [ContinuityProposal] {
        guard let selected else { return [] }
        return proposals.filter { $0.id != selected.id && $0.kind == selected.kind && $0.status == .proposed }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continuity Bible Review").font(.title2.weight(.semibold))
                    Text("Local script evidence only. Nothing enters the bible until you adopt it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan Script") { model.scanContinuityBible() }
                Button("Undo") { model.undoContinuityReviewAction() }
                    .disabled(!model.canUndoContinuityReviewAction)
                Button("Done") { model.continuityBiblePresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            HSplitView {
                proposalList
                    .frame(minWidth: 270, idealWidth: 320)
                detail
                    .frame(minWidth: 500, idealWidth: 650)
            }

            if let status = model.continuityBibleStatus {
                Divider()
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: proposals.map(\.id)) { _ in selectFirstIfNeeded() }
        .onChange(of: selection) { _ in
            adoptedName = selected?.name ?? ""
            mergeTarget = mergeChoices.first?.id
            if let entry = selectedEntry, performerName.isEmpty { performerName = entry.name }
        }
    }

    private var proposalList: some View {
        List(selection: $selection) {
            if let entries = ledger?.entries, !entries.isEmpty {
                Section("Adopted Bible") {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).lineLimit(1)
                                Text(entry.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        .tag(entry.id)
                    }
                }
            }
            ForEach(ContinuityEntityKind.allCases.filter { $0 != .style }, id: \.self) { kind in
                let rows = proposals.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(kind.rawValue.capitalized) {
                        ForEach(rows) { proposal in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proposal.name).lineLimit(1)
                                    Text("\(proposal.occurrenceCount) occurrence\(proposal.occurrenceCount == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusIcon(proposal.status)
                            }
                            .tag(proposal.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var detail: some View {
        if let entry = selectedEntry {
            entryDetail(entry)
        } else if let proposal = selected {
            proposalDetail(proposal)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                Text("No proposal selected").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func proposalDetail(_ proposal: ContinuityProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(proposal.name).font(.title3.weight(.semibold))
                    Text(proposal.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(proposal.status.rawValue.capitalized).font(.caption.weight(.medium))
                }

                if proposal.status == .proposed {
                    HStack {
                        TextField("Bible entry name", text: $adoptedName)
                        Button("Adopt") { model.adoptContinuityProposal(proposal.id, name: adoptedName) }
                            .buttonStyle(.borderedProminent)
                        Button("Reject", role: .destructive) { model.rejectContinuityProposal(proposal.id) }
                    }

                    if !mergeChoices.isEmpty {
                        HStack {
                            Picker("Merge as alias of", selection: $mergeTarget) {
                                ForEach(mergeChoices) { choice in Text(choice.name).tag(Optional(choice.id)) }
                            }
                            Button("Merge") {
                                if let mergeTarget { model.mergeContinuityProposal(proposal.id, into: mergeTarget) }
                            }
                            .disabled(mergeTarget == nil)
                        }
                    }
                } else if proposal.status == .merged,
                          let target = proposals.first(where: { $0.id == proposal.mergedIntoID }) {
                    Text("Merged as an alias of \(target.name).")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Divider()
                Text("Script Evidence").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(proposal.evidence) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.sceneHeading ?? "Before first scene")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text("Line \(item.elementIndex + 1)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(item.exactText)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .background(StudioAppearance.recess, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                if let entries = ledger?.entries, !entries.isEmpty {
                    Divider()
                    Text("Adopted entries: \(entries.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
        }
        .padding(16)
    }

    private func entryDetail(_ entry: ContinuityBibleEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(entry.name).font(.title3.weight(.semibold))
                    Text(entry.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
                if !entry.aliases.isEmpty {
                    Text("Aliases: \(entry.aliases.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if entry.kind == .character {
                    Divider()
                    Text("Performer and consent").font(.headline)
                    Picker("Classification", selection: Binding(
                        get: { entry.performerClassification ?? .fictional },
                        set: { model.classifyContinuityCharacter(entry.id, as: $0) }
                    )) {
                        Text("Fictional character").tag(PerformerClassification.fictional)
                        Text("Real performer").tag(PerformerClassification.realPerformer)
                    }
                    .pickerStyle(.segmented)

                    if entry.performerClassification == .realPerformer {
                        Text("Likeness generation and voice cloning are blocked unless an applicable, unexpired consent record exists.")
                            .font(.caption).foregroundStyle(.secondary)

                        GroupBox("Record consent") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Performer or rights holder", text: $performerName)
                                Toggle("Likeness generation", isOn: $likenessScope)
                                Toggle("Voice cloning", isOn: $voiceScope)
                                Toggle("Consent expires", isOn: $consentExpires)
                                if consentExpires { DatePicker("Expiry", selection: $consentExpiry, in: Date()..., displayedComponents: .date) }
                                TextField("Scope or contract note", text: $consentNote, axis: .vertical).lineLimit(2...4)
                                Button("Record Consent") {
                                    var scopes: [PerformerConsentScope] = []
                                    if likenessScope { scopes.append(.likenessGeneration) }
                                    if voiceScope { scopes.append(.voiceCloning) }
                                    model.addPerformerConsent(
                                        entryID: entry.id, performerName: performerName,
                                        scopes: scopes, expiresAt: consentExpires ? consentExpiry : nil,
                                        note: consentNote
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(performerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!likenessScope && !voiceScope))
                            }
                            .padding(6)
                        }

                        let records = ledger?.consentRecords.filter { $0.characterEntryID == entry.id } ?? []
                        if records.isEmpty {
                            Text("No consent on file").foregroundStyle(.red)
                        } else {
                            ForEach(records) { record in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(record.performerName).font(.system(size: 13, weight: .semibold))
                                        Text(record.scopes.map(\.rawValue).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(consentStatus(record)).font(.caption)
                                            .foregroundStyle(record.revokedAt == nil ? .green : .red)
                                        if !record.note.isEmpty { Text(record.note).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if record.revokedAt == nil {
                                        Button("Revoke", role: .destructive) { model.revokePerformerConsent(record.id) }
                                    }
                                }
                                .padding(10)
                                .background(StudioAppearance.recess, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder private func statusIcon(_ status: ContinuityProposalStatus) -> some View {
        switch status {
        case .proposed: Image(systemName: "circle").foregroundStyle(.secondary)
        case .adopted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .rejected: Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .merged: Image(systemName: "arrow.triangle.merge").foregroundStyle(.blue)
        }
    }

    private func selectFirstIfNeeded() {
        let entryIDs = Set(ledger?.entries.map(\.id) ?? [])
        let entrySelected = selection.map(entryIDs.contains) ?? false
        if !proposals.contains(where: { $0.id == selection }) && !entrySelected {
            selection = ledger?.entries.first?.id ?? proposals.first?.id
        }
        adoptedName = selected?.name ?? ""
        mergeTarget = mergeChoices.first?.id
        if let entry = selectedEntry { performerName = entry.name }
    }

    private func consentStatus(_ record: PerformerConsentRecord) -> String {
        if let revoked = record.revokedAt { return "Revoked \(revoked.formatted(date: .abbreviated, time: .omitted))" }
        if let expiry = record.expiresAt { return "Expires \(expiry.formatted(date: .abbreviated, time: .omitted))" }
        return "No expiry recorded"
    }
}
