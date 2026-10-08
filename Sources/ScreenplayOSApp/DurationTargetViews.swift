import SwiftUI
import ScreenplayDomain

/// Derived display only. Missing estimates are never treated as zero-duration scenes.
struct PlanningDurationSummary {
    let target: Int?
    let sceneCount: Int
    let knownCount: Int
    let minimum: Double
    let maximum: Double

    init(target: Int?, sceneIDs: [String], estimates: [String: SceneDurationEstimate]) {
        self.target = target
        let ids = Set(sceneIDs)
        let known = ids.compactMap { estimates[$0] }
        sceneCount = ids.count
        knownCount = known.count
        minimum = known.reduce(0) { $0 + $1.minimumSeconds }
        maximum = known.reduce(0) { $0 + $1.maximumSeconds }
    }

    var estimateText: String {
        guard knownCount > 0 else { return "Estimate unavailable" }
        let range = "\(DurationTarget.clock(Int(minimum)))–\(DurationTarget.clock(Int(maximum)))"
        return knownCount == sceneCount ? "Estimate \(range)" : "Known estimate \(range) · \(sceneCount - knownCount) untimed"
    }

    var gapText: String? {
        guard let target, knownCount > 0, knownCount == sceneCount else { return nil }
        if Double(target) < minimum {
            return "Estimate exceeds target by at least \(DurationTarget.clock(Int(minimum) - target))"
        }
        if Double(target) > maximum {
            return "Target exceeds estimate by at least \(DurationTarget.clock(target - Int(maximum)))"
        }
        return "Target is within the estimated range"
    }
}

extension ScreenplayViewModel {
    var beatTargetTotal: Int { outlineBeats.compactMap(\.targetDurationSeconds).reduce(0, +) }
    var sceneTargetTotal: Int {
        elements.filter { $0.type == .sceneHeading }.compactMap { sceneTargetSeconds($0.id) }.reduce(0, +)
    }
}

struct DurationTargetEditor: View {
    let label: String
    let value: Int?
    let commit: (Int?) -> Bool
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption)
            HStack {
                TextField("Unset", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .frame(width: 80)
                    .accessibilityLabel(label)
                    .onSubmit(apply)
                Button("Set", action: apply).controlSize(.small)
                if value != nil {
                    Button("Clear") {
                        if commit(nil) { draft = ""; error = nil }
                    }.controlSize(.small)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .help("Optional plan in whole seconds or minutes:seconds. Set commits one undoable change; Clear removes the target. It does not retime the edit.")
        .onAppear { draft = value.map(DurationTarget.clock) ?? "" }
        .onChange(of: value) { newValue in draft = newValue.map(DurationTarget.clock) ?? ""; error = nil }
    }

    private func apply() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = DurationTarget.parse(text)
        guard text.isEmpty || parsed != nil else {
            error = "Use 1–86400 seconds or m:ss (for example, 1:30)."
            return
        }
        if commit(parsed) { draft = parsed.map(DurationTarget.clock) ?? ""; error = nil }
        else { error = "This target could not be updated." }
    }
}

struct PlanningEstimateView: View {
    let summary: PlanningDurationSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.estimateText)
            if let gap = summary.gapText { Text(gap) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(SceneTimingDisplay.assumptions)
    }
}

struct TimingPlanTotals: View {
    @ObservedObject var model: ScreenplayViewModel
    var body: some View {
        let headings = model.elements.filter { $0.type == .sceneHeading }
        VStack(alignment: .leading, spacing: 4) {
            Text("Beat targets \(DurationTarget.clock(model.beatTargetTotal)) · \(model.outlineBeats.filter { $0.targetDurationSeconds != nil }.count)/\(model.outlineBeats.count) set")
            Text("Scene targets \(DurationTarget.clock(model.sceneTargetTotal)) · \(headings.filter { model.sceneTargetSeconds($0.id) != nil }.count)/\(headings.count) set")
            PlanningEstimateView(summary: .init(target: nil, sceneIDs: headings.compactMap(\.spineID), estimates: model.scenePlanningEstimates))
        }
        .font(.caption)
        .help("Beat and scene plans are separate totals, not additive. Unset targets are excluded, not assumed to be zero. Estimates count each scene once.")
    }
}

struct SceneTargetControls: View {
    @ObservedObject var model: ScreenplayViewModel
    let scene: SceneBreakdown
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            DurationTargetEditor(label: "Scene target", value: model.sceneTargetSeconds(scene.elementID)) {
                model.setSceneTarget(scene.elementID, seconds: $0)
            }.id(scene.elementID)
            PlanningEstimateView(summary: .init(target: model.sceneTargetSeconds(scene.elementID), sceneIDs: [scene.editSpineID], estimates: model.scenePlanningEstimates))
        }
    }
}
