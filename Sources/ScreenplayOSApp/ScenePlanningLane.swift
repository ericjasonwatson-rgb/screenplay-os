import SwiftUI
import ScreenplayDomain

/// Time-proportional plan; independent of the playable board/media timeline.
struct ScenePlanningLane: View {
    @ObservedObject var model: ScreenplayViewModel
    let plan: ScenePlanningTimeline
    let zoom: Double
    private var selectedScene: String? { model.selectedSceneBreakdown?.editSpineID }
    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) / 2 else { return "Out of range" }
        let seconds = Int(seconds.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private func duration(_ entry: ScenePlanningTimeline.Entry) -> String {
        guard let low = entry.minimumSeconds, let high = entry.maximumSeconds else { return "Untimed" }
        return entry.usesMedia ? "Media cut \(clock(low))" : "Est. \(clock(low))–\(clock(high))"
    }
    private var summary: String {
        guard plan.entries.count > plan.untimedCount else { return "No scene timing available" }
        let range = plan.hasEstimates ? "\(clock(plan.minimumSeconds))–\(clock(plan.maximumSeconds))" : clock(plan.minimumSeconds)
        let prefix = plan.untimedCount > 0 ? "Timed subtotal" : plan.hasEstimates ? "Estimated runtime" : "Current media cut"
        return "\(prefix): \(range)" + (plan.untimedCount > 0 ? " · \(plan.untimedCount) untimed" : "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary).font(.caption.monospacedDigit())
            Text("Scene widths use estimate midpoints or media-cut durations. This plan does not change playback.")
                .font(.caption2).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(plan.entries) { entry in
                            let width = CGFloat(entry.midpointSeconds.map { $0 * 4 * zoom } ?? 88)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.midpointStart.map { "≈\(clock($0))" } ?? "Start unknown")
                                    .font(.caption2.monospacedDigit()).lineLimit(1)
                                Button {
                                    model.pauseEditPlayback()
                                    if let beat = model.editorialBeats.first(where: { $0.id == entry.id }) {
                                        model.selectEditorialBeat(beat)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.sceneSpineID).font(.caption.monospacedDigit())
                                        Text(entry.title.uppercased()).font(.caption).lineLimit(1)
                                        Text(duration(entry)).font(.caption2.monospacedDigit()).lineLimit(1)
                                    }
                                    .padding(6)
                                    .frame(width: width, height: 68, alignment: .leading)
                                    .clipped()
                                    .background(selectedScene == entry.sceneSpineID ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08))
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help("\(entry.sceneSpineID) · \(entry.title) · \(duration(entry)). Untimed blocks have no time scale.")
                                .accessibilityLabel("\(entry.sceneSpineID), \(entry.title), \(duration(entry))")
                            }
                            .frame(width: width, alignment: .leading).clipped()
                            .id(entry.sceneSpineID)
                        }
                    }
                }
                .onAppear { if let selectedScene { proxy.scrollTo(selectedScene, anchor: .center) } }
                .onChange(of: selectedScene) { scene in
                    if let scene { proxy.scrollTo(scene, anchor: .center) }
                }
            }
        }
        .padding(12)
    }
}
