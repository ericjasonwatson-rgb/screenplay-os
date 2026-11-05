import SwiftUI
import ScreenplayDomain

/// A contextual production panel, not a sixth creative workspace. The screenplay,
/// shots and boards remain the only editable source objects.
@MainActor
struct CampaignWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel
    @StateObject private var session: CampaignWorkspaceSession
    @Environment(\.dismiss) private var dismiss
    private let importLifecycle: CampaignAgencyImportLifecycle?
    @State private var baselineName = ""
    @State private var selectedBaselineID: UUID?
    @State private var selectedTab = 1
    @State private var selectedAgencyDocumentID: UUID?
    @State private var scope: CampaignApprovalScope = .creative
    @State private var approver = ""
    @State private var evidence = ""
    @State private var ceiling = ""
    @State private var currency = "USD"

    init(model: ScreenplayViewModel, projectID: UUID, root: URL? = nil,
         importLifecycle: CampaignAgencyImportLifecycle? = nil) {
        self.model = model
        self.importLifecycle = importLifecycle
        _session = StateObject(wrappedValue: CampaignWorkspaceSession(projectID: projectID, root: root))
    }

    private var document: ScreenplayOSDocument? {
        // SwiftUI can rebuild this value with a new projectID while retaining the
        // original StateObject. Never pair that session with another project's sources.
        guard model.document?.project.id == session.ledger.projectID else { return nil }
        return model.document
    }
    private var baseline: CampaignBaseline? {
        session.ledger.baselines.first { $0.id == selectedBaselineID }
    }
    private var comparison: Result<[CampaignChange], Error> {
        guard let baseline, let document else { return .success([]) }
        return Result { try session.ledger.compare(baselineID: baseline.id, document: document) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Campaign Brief & Scope").font(.title2.weight(.semibold))
                    Text(document?.project.metadata.title ?? "Project unavailable").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("campaign.close")
            }
            Text("Keep the agreed scope connected to the script, shots and boards. All changes require producer review.")
                .font(.callout).foregroundStyle(.secondary)
            TabView(selection: $selectedTab) {
                CampaignAgencySourcesView(session: session, selectedDocumentID: $selectedAgencyDocumentID,
                                          importLifecycle: importLifecycle)
                    .tabItem { Label("Agency Sources", systemImage: "doc.text.magnifyingglass") }.tag(0)
                ScrollView { briefAndDeliverables.padding(.vertical, 12) }
                    .tabItem { Label("Brief & Deliverables", systemImage: "list.bullet.rectangle") }.tag(1)
                ScrollView { assumptions.padding(.vertical, 12) }
                    .tabItem { Label("Bid Assumptions", systemImage: "text.badge.checkmark") }.tag(2)
                ScrollView { review.padding(.vertical, 12) }
                    .tabItem { Label("Baseline & Changes", systemImage: "arrow.triangle.branch") }.tag(3)
            }
            .disabled(session.isReadOnly || document == nil)
            if let problem = session.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout).textSelection(.enabled)
            }
            Divider()
            HStack {
                Button("Undo Draft Change", action: session.undoDraft).disabled(!session.canUndoDraft)
                    .accessibilityIdentifier("campaign.undo")
                Spacer()
                Button("Restore Backup…", action: session.importBackup).disabled(!session.canImport)
                Button("Private Backup…", action: session.exportBackup).disabled(session.isReadOnly)
            }
            .disabled(document == nil)
            Text(session.status).font(.caption).foregroundStyle(.secondary)
            Text("Campaign records stay on this Mac and are not included in screenplay or portable-project exports. Back them up separately. There are no dedicated working-budget or margin fields. Imported text and notes may be confidential; inspect backups and reports before sharing.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 820, maxWidth: 1000, minHeight: 540, idealHeight: 680, maxHeight: 900)
        .onAppear { selectedBaselineID = session.ledger.baselines.last?.id }
        .onChange(of: session.ledger.baselines.count) { _ in
            if selectedBaselineID == nil { selectedBaselineID = session.ledger.baselines.last?.id }
        }
        .onChange(of: model.document?.project.id) { _ in if document == nil { dismiss() } }
    }

    private var briefAndDeliverables: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Campaign brief") {
                VStack(spacing: 8) {
                    field("Brand", text: briefBinding(\.brand))
                    field("Objective", text: briefBinding(\.objective))
                    field("Audience", text: briefBinding(\.audience))
                    field("Key message", text: briefBinding(\.keyMessage))
                    field("Mandatory requirements", text: briefBinding(\.mandatoryRequirements))
                }.padding(6)
            }
            HStack {
                Text("Deliverables").font(.headline)
                Spacer()
                Button("Add Deliverable") {
                    session.updateDraft { $0.deliverables.append(CampaignDeliverable(name: "New deliverable")) }
                }
                .accessibilityIdentifier("campaign.deliverable.add")
            }
            if session.ledger.draft.deliverables.isEmpty {
                Text("Add the hero film, cutdowns, vertical versions and market variants you have agreed to deliver.")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.ledger.draft.deliverables) { item in
                deliverableEditor(item)
            }
        }
    }

    private func deliverableEditor(_ item: CampaignDeliverable) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Deliverable name", text: deliverableBinding(item, \.name))
                        .accessibilityLabel("Deliverable name")
                        .accessibilityIdentifier("campaign.deliverable.name.\(item.id)")
                    Stepper(value: deliverableBinding(item, \.durationSeconds), in: 1...86400) {
                        Text("\(item.durationSeconds) sec").monospacedDigit()
                    }.frame(width: 130)
                    Button("Remove") { session.updateDraft { $0.deliverables.removeAll { $0.id == item.id } } }
                        .accessibilityIdentifier("campaign.deliverable.remove.\(item.id)")
                }
                HStack {
                    field("Ratio", text: deliverableBinding(item, \.aspectRatio))
                    field("Market", text: deliverableBinding(item, \.market))
                    field("Language", text: deliverableBinding(item, \.language))
                }
                DisclosureGroup("Shot coverage (\(item.linkedShotIDs.count) linked)") {
                    VStack(alignment: .leading, spacing: 5) {
                        if document?.shots.isEmpty != false {
                            Text("Create shots in the Shot workspace, then link their coverage here.").foregroundStyle(.secondary)
                        }
                        ForEach(document?.shots ?? []) { shot in
                            Toggle("\(shot.label) · \(shot.sceneSpineID)", isOn: Binding(
                                get: { item.linkedShotIDs.contains(shot.id) },
                                set: { linked in
                                    session.updateDraft { draft in
                                        guard let index = draft.deliverables.firstIndex(where: { $0.id == item.id }) else { return }
                                        if linked && !draft.deliverables[index].linkedShotIDs.contains(shot.id) {
                                            draft.deliverables[index].linkedShotIDs.append(shot.id)
                                        } else if !linked { draft.deliverables[index].linkedShotIDs.removeAll { $0 == shot.id } }
                                    }
                                }
                            ))
                        }
                        ForEach(item.linkedShotIDs.filter { id in !(document?.shots.contains { $0.id == id } ?? false) }, id: \.self) { id in
                            HStack {
                                Label("Missing shot \(id.uuidString)", systemImage: "exclamationmark.triangle").font(.caption)
                                Button("Unlink") {
                                    session.updateDraft { draft in
                                        guard let index = draft.deliverables.firstIndex(where: { $0.id == item.id }) else { return }
                                        draft.deliverables[index].linkedShotIDs.removeAll { $0 == id }
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }.padding(6)
        }
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record the bid basis, not the private working budget. Include exclusions, shoot days, locations, post, talent usage and delivery requirements.")
                .foregroundStyle(.secondary)
            Text("Source references can be manual citations, such as ‘Agency script v3, page 4’. Use Agency Sources to import local text and link reviewed lines to these assumptions. Original documents and sender identities are not verified.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Add Assumption") {
                session.updateDraft { $0.assumptions.append(CampaignAssumption()) }
            }
            ForEach(session.ledger.draft.assumptions) { item in
                GroupBox {
                    VStack(spacing: 8) {
                        field("Assumption", text: assumptionBinding(item.id, \.text))
                        field("Source document / version", text: assumptionBinding(item.id, \.sourceLabel))
                        HStack {
                            field("Page / section / reference", text: assumptionBinding(item.id, \.sourceReference))
                            Button("Remove") { session.updateDraft { $0.assumptions.removeAll { $0.id == item.id } } }
                        }
                    }.padding(6)
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Freeze a named snapshot of this scope and its source objects. A snapshot is not approval; record each approval separately with evidence.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Baseline name, e.g. Awarded bid · 5 Nov", text: $baselineName)
                Button("Freeze Baseline") {
                    guard let document, let id = session.freeze(name: baselineName, document: document) else { return }
                    selectedBaselineID = id; baselineName = ""
                }.disabled(baselineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !session.ledger.baselines.isEmpty {
                Picker("Compare with", selection: $selectedBaselineID) {
                    ForEach(session.ledger.baselines) { saved in
                        Text("\(saved.name) · \(saved.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .tag(Optional(saved.id))
                    }
                }
            }
            if let baseline {
                Text("Baseline \(baseline.id.uuidString)").font(.caption).textSelection(.enabled)
                switch comparison {
                case .failure(let error):
                    Text(error.localizedDescription).foregroundStyle(.orange)
                case .success(let changes):
                    HStack {
                        Label(changes.isEmpty ? "No tracked changes" : "\(changes.count) changes / source warnings to review",
                              systemImage: changes.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                        Spacer()
                        Button("Export Change Review…") {
                            if let document { session.exportReport(baselineID: baseline.id, document: document) }
                        }
                    }
                    Text("Exact tracked changes only. Coverage, costs, schedule and original documents still need human review. No automatic repricing or spend authorization.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(changes) { change in changeRow(change) }
                    approvalEditor(baseline, current: changes.isEmpty)
                }
                decisionHistory(baseline)
            }
        }
    }

    private func changeRow(_ change: CampaignChange) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(change.title).font(.headline)
                    Spacer()
                    if canNavigate(change) { Button("Go to Source") { navigate(change) } }
                }
                Text("\(change.sourceKind.rawValue) · \(change.sourceID.uuidString)").font(.caption).textSelection(.enabled)
                Text("Affected: \(affectedNames(change).joined(separator: ", "))").font(.callout)
                DisclosureGroup("Before / after") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Baseline").fontWeight(.semibold)
                        Text(change.before).textSelection(.enabled)
                        Text("Current").fontWeight(.semibold)
                        Text(change.after).textSelection(.enabled)
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }.padding(6)
        }
    }

    private func approvalEditor(_ baseline: CampaignBaseline, current: Bool) -> some View {
        GroupBox("Record an approval already received") {
            VStack(alignment: .leading, spacing: 8) {
                Text(current ? "Records are local evidence, not verified identities or electronic signatures. Creative approval never authorizes spend." : "This baseline no longer matches current sources. Review the changes and freeze a new baseline before recording approval.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Scope", selection: $scope) {
                    Text("Creative").tag(CampaignApprovalScope.creative)
                    Text("Production approach").tag(CampaignApprovalScope.production)
                    Text("Additional spend").tag(CampaignApprovalScope.spend)
                }.pickerStyle(.segmented)
                field("Approved by", text: $approver)
                field("Evidence / message reference", text: $evidence)
                if scope == .spend {
                    HStack {
                        field("Ceiling in minor units", text: $ceiling)
                        field("Currency", text: $currency)
                    }
                    Text("For USD 125.00, enter 12500 and USD. This records the ceiling only; it cannot make a payment or authorize a provider request.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Record \(scope.rawValue.capitalized) Approval") {
                    guard let document else { return }
                    if session.record(baselineID: baseline.id, scope: scope, approver: approver, evidence: evidence,
                                      document: document, amount: ceiling, currency: currency) {
                        approver = ""; evidence = ""; ceiling = ""
                    }
                }.disabled(!current || approver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(6)
        }
    }

    private func decisionHistory(_ baseline: CampaignBaseline) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recorded decisions for this baseline").font(.headline)
            let decisions = session.ledger.decisions.filter { $0.baselineID == baseline.id }
            if decisions.isEmpty { Text("No approvals recorded.").foregroundStyle(.secondary) }
            ForEach(decisions) { decision in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(decision.scope.rawValue.capitalized) · \(decision.approver) · \(decision.createdAt.formatted())")
                    Text(decision.evidence).font(.caption).textSelection(.enabled)
                    if let amount = decision.spendCeilingMinorUnits, let code = decision.currencyCode {
                        Text("Ceiling: \(amount) minor units · \(code)").font(.caption)
                    }
                }
            }
            Text("Historical decisions stay attached to the frozen version, even after the working scope changes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                .accessibilityLabel(label)
                .accessibilityIdentifier("campaign.field.\(label)")
        }
    }
    private func briefBinding(_ path: WritableKeyPath<CampaignBrief, String>) -> Binding<String> {
        Binding(get: { session.ledger.draft.brief[keyPath: path] },
                set: { value in session.updateDraft { $0.brief[keyPath: path] = value } })
    }
    private func deliverableBinding<Value>(_ item: CampaignDeliverable, _ path: WritableKeyPath<CampaignDeliverable, Value>) -> Binding<Value> {
        Binding(get: { (session.ledger.draft.deliverables.first { $0.id == item.id } ?? item)[keyPath: path] }, set: { value in
            session.updateDraft { draft in
                guard let index = draft.deliverables.firstIndex(where: { $0.id == item.id }) else { return }
                draft.deliverables[index][keyPath: path] = value
            }
        })
    }
    private func assumptionBinding(_ id: UUID, _ path: WritableKeyPath<CampaignAssumption, String>) -> Binding<String> {
        Binding(get: { session.ledger.draft.assumptions.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in
            session.updateDraft { draft in
                guard let index = draft.assumptions.firstIndex(where: { $0.id == id }) else { return }
                draft.assumptions[index][keyPath: path] = value
            }
        })
    }
    private func affectedNames(_ change: CampaignChange) -> [String] {
        guard !change.affectedDeliverableIDs.isEmpty else { return ["No linked deliverable; assess coverage manually"] }
        let all = session.ledger.draft.deliverables + (baseline?.draft.deliverables ?? [])
        return change.affectedDeliverableIDs.map { id in all.first { $0.id == id }?.name ?? id.uuidString }
    }
    private func agencyDocumentID(for change: CampaignChange) -> UUID? {
        if change.sourceKind == .agencyDocument { return change.sourceID }
        let citations = (session.ledger.draft.agency?.citations ?? []) + (baseline?.draft.agency?.citations ?? [])
        return citations.first { $0.id == change.sourceID }?.documentID
    }
    private func canNavigate(_ change: CampaignChange) -> Bool {
        switch change.sourceKind {
        case .script: return document?.screenplay.elements.contains { $0.id == change.sourceID } ?? false
        case .shot: return document?.shots.contains { $0.id == change.sourceID } ?? false
        case .board: return document?.boardFrames.contains { $0.id == change.sourceID } ?? false
        case .agencyDocument, .agencyCitation:
            guard let id = agencyDocumentID(for: change) else { return false }
            return session.ledger.draft.agency?.latestRevision(documentID: id) != nil
        default: return false
        }
    }
    private func navigate(_ change: CampaignChange) {
        switch change.sourceKind {
        case .agencyDocument, .agencyCitation:
            selectedAgencyDocumentID = agencyDocumentID(for: change); selectedTab = 0
            return
        case .script:
            model.setWorkflowMode(.writing); model.selectElement(id: change.sourceID)
            model.scrollTargetElementID = change.sourceID
        case .shot:
            if let shot = document?.shots.first(where: { $0.id == change.sourceID }) {
                model.setWorkflowMode(.directing); model.selectShot(shot)
            }
        case .board:
            if let board = document?.boardFrames.first(where: { $0.id == change.sourceID }) {
                model.setWorkflowMode(.boards); model.selectBoardFrame(board)
            }
        default: return
        }
        dismiss()
    }
}
