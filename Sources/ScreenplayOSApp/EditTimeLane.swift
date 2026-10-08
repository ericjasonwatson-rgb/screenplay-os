import SwiftUI
import Combine

struct EditPlaybackBar: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var lastTick = Date()
    @State private var wasPlaying = false
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
            // Leave view state untouched while paused so the Edit view stops redrawing 20×/s.
            guard model.editIsPlaying else {
                if wasPlaying { wasPlaying = false }
                return
            }
            // The first tick after any resume (button or shortcut) starts from now; later
            // ticks use real elapsed time so stalls do not slow playback.
            let elapsed = wasPlaying ? max(0, now.timeIntervalSince(lastTick)) : 0
            wasPlaying = true
            lastTick = now
            model.advanceEditPlayback(by: elapsed)
        }
        .onDisappear { model.pauseEditPlayback() }
    }
}

struct EditTimeLane: View {
    @ObservedObject var model: ScreenplayViewModel
    var zoom: Double
    var body: some View {
        GeometryReader { geometry in
            let available = max(100, geometry.size.width - 24)
            let scale = max(0.01, available / max(1, model.editDuration)) * zoom
            let width = max(available, model.editDuration * scale)
            if model.editDuration > 0 {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        Canvas { context, size in
                            let desired = 90 / scale
                            let step = [1.0, 5, 10, 30, 60, 120, 300, 600, 1800, 3600].first { $0 >= desired } ?? 7200
                            for time in stride(from: 0.0, through: model.editDuration, by: step) {
                                let x = time * scale
                                var path = Path(); path.move(to: CGPoint(x: x, y: 22)); path.addLine(to: CGPoint(x: x, y: 32))
                                context.stroke(path, with: .color(.gray), lineWidth: 1)
                                context.draw(Text(EditInterchange.timecode(Int(time * 24))).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.7)),
                                             at: CGPoint(x: x + 4, y: 10), anchor: .leading)
                            }
                        }
                        .frame(height: 34)
                        .background(Color(white: 0.18))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { model.seekEdit(to: $0.location.x / scale) })
                        .accessibilityLabel("Timeline ruler; drag to scrub")
                        ZStack(alignment: .topLeading) {
                            Color(white: 0.12)
                            HStack(spacing: 0) {
                                ForEach(model.editTimeline) { entry in
                                    let selected = model.selectedSceneBreakdown?.editSpineID == entry.sceneSpineID
                                    let clipWidth = entry.duration * scale
                                    Button { model.seekEdit(to: entry.start) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.sceneSpineID).font(.system(size: 10, weight: .bold, design: .monospaced))
                                            Text(entry.label).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                            Spacer(minLength: 0)
                                            Text((entry.estimate == nil ? "" : "Est. ") + String(format: "%.1fs", entry.duration))
                                                .font(.system(size: 10, design: .monospaced))
                                        }
                                        .padding(.horizontal, min(8, clipWidth / 4)).padding(.vertical, 8)
                                        .frame(width: clipWidth, height: 100, alignment: .leading)
                                        .foregroundStyle(.white.opacity(0.94))
                                        .background(LinearGradient(colors: entry.estimate == nil
                                            ? [Color(red: 0.25, green: 0.44, blue: 0.51), Color(red: 0.16, green: 0.29, blue: 0.34)]
                                            : [Color(red: 0.34, green: 0.39, blue: 0.51), Color(red: 0.23, green: 0.27, blue: 0.36)], startPoint: .top, endPoint: .bottom))
                                        .overlay(Rectangle().strokeBorder(selected ? Color.yellow : Color.black.opacity(0.65), lineWidth: selected ? 2 : 1))
                                        .clipped()
                                    }.buttonStyle(.plain)
                                    .accessibilityLabel("\(entry.sceneSpineID), \(entry.label), \(entry.duration) seconds")
                                    .help("\(entry.label) · \(entry.estimate == nil ? "Timed clip" : "Estimated scene")")
                                    .contextMenu {
                                        if let beat = model.editorialBeats.first(where: { $0.sceneSpineID == entry.sceneSpineID }) {
                                            Button("Move Scene Earlier in Edit") { model.moveEditorialBeat(beat.id, direction: -1) }
                                            Button("Move Scene Later in Edit") { model.moveEditorialBeat(beat.id, direction: 1) }
                                        }
                                    }
                                }
                            }.padding(.top, 30)
                        }.frame(height: 180)
                    }
                    .frame(width: width, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12))
                            Rectangle().frame(width: 1.5)
                        }.foregroundStyle(Color.orange).frame(width: 12, height: 214)
                            .offset(x: model.editPlayheadSeconds * scale - 6).allowsHitTesting(false)
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                Text("Enable Estimates or add timed boards to populate the timeline.")
                    .foregroundStyle(.secondary).padding(20)
            }
        }.frame(minHeight: 230)
    }
}
