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

    private var ledger: ContinuityBibleLedger? { model.continuityBible }
    private var proposals: [ContinuityProposal] { ledger?.proposals ?? [] }
    private var selected: ContinuityProposal? { proposals.first { $0.id == selection } }
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
        }
    }

    private var proposalList: some View {
        List(selection: $selection) {
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
        if let proposal = selected {
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
        } else {
            VStack(spacing: 8) {
                Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                Text("No proposal selected").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if !proposals.contains(where: { $0.id == selection }) { selection = proposals.first?.id }
        adoptedName = selected?.name ?? ""
        mergeTarget = mergeChoices.first?.id
    }
}
