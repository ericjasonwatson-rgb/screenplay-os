import SwiftUI
import Combine

struct EditPlaybackBar: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var lastTick = Date()
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack {
            Button {
                lastTick = Date()
                model.toggleEditPlayback()
            } label: { Label(model.editIsPlaying ? "Pause Edit" : "Play Edit", systemImage: model.editIsPlaying ? "pause.fill" : "play.fill") }
            .disabled(model.editDuration == 0)
            Slider(value: Binding(get: { model.editPlayheadSeconds }, set: { model.seekEdit(to: $0) }),
                   in: 0...max(0.01, model.editDuration))
                .disabled(model.editDuration == 0)
                .accessibilityLabel("Whole edit playhead")
            Text((model.editTimelineHasEstimates ? "Est. " : "") + String(format: "%.1f / %.1fs", model.editPlayheadSeconds, model.editDuration)
                + (model.untimedEditSceneCount > 0 ? " · \(model.untimedEditSceneCount) untimed" : ""))
                .font(.caption.monospacedDigit())
        }
        .padding(12)
        .onReceive(timer) { now in
            let elapsed = now.timeIntervalSince(lastTick)
            lastTick = now
            model.advanceEditPlayback(by: elapsed)
        }
        .onDisappear { model.pauseEditPlayback() }
    }
}

struct EditTimeLane: View {
    @ObservedObject var model: ScreenplayViewModel
    var zoom: Double
    private var scale: Double { 24 * zoom }
    var body: some View {
        if model.editDuration > 0 {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    Canvas { context, size in
                        let step = max(5.0, ceil(model.editDuration / 200 / 5) * 5)
                        for time in stride(from: 0.0, through: model.editDuration, by: step) {
                            let x = time * scale
                            var path = Path(); path.move(to: CGPoint(x: x, y: 18)); path.addLine(to: CGPoint(x: x, y: 24))
                            context.stroke(path, with: .color(.secondary), lineWidth: 1)
                            context.draw(Text(String(format: "%.0fs", time)).font(.system(size: 10)).foregroundColor(.secondary),
                                         at: CGPoint(x: x + 2, y: 7), anchor: .leading)
                        }
                    }
                    .frame(height: 24)
                    HStack(spacing: 0) {
                        ForEach(model.editTimeline) { entry in
                            Button { model.seekEdit(to: entry.start) } label: {
                                Text((entry.estimate != nil ? "Est. · " : "") + entry.label).font(.caption2).lineLimit(1)
                                    .frame(width: entry.duration * scale, height: 30)
                                    .clipped()
                                    .background(Color.accentColor.opacity(0.2))
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(String(format: "%@ · %@%.1fs", entry.label, entry.estimate == nil ? "" : "Estimated ", entry.duration))
                        }
                    }
                }
                .frame(width: model.editDuration * scale, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(Color.orange).frame(width: 2, height: 56)
                        .offset(x: model.editPlayheadSeconds * scale).allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 76)
        } else {
            Text("Enable Estimates or add timed boards to populate the timeline. Untimed scenes remain below.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
        }
    }
}
