import SwiftUI
import ScreenplayDomain

/// A scene-order overview. Untimed scenes stay visible without inventing runtime.
struct LinearEditSpineView: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var zoom = 1.0

    private var selectedScene: String? { model.selectedSceneBreakdown?.editSpineID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label("Edit Spine", systemImage: "film")
                    .font(.system(size: 13, weight: .semibold))
                Text("Edit order · \(model.editorialBeats.count) scenes")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Zoom").font(.caption)
                Slider(value: $zoom, in: 0.5...2)
                    .frame(width: 100)
                    .accessibilityLabel("Edit timeline zoom")
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit()).frame(width: 38)
            }
            .padding(12)
            Divider()
            EditTimeLane(model: model, zoom: zoom)
            if model.editorialBeats.isEmpty {
                Text("Your screenplay scenes will appear here from left to right.")
                    .foregroundStyle(.secondary).padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 4) {
                            ForEach(model.editorialBeats) { beat in
                                scene(beat).id(beat.sceneSpineID)
                            }
                        }
                        .padding(12)
                    }
                    .onAppear {
                        if let selectedScene { proxy.scrollTo(selectedScene, anchor: .center) }
                    }
                    .onChange(of: selectedScene) { scene in
                        if let scene { proxy.scrollTo(scene, anchor: .center) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .background(ScreenplayOSTokens.Palette.panelBackground)
    }

    private func scene(_ beat: EditorialBeat) -> some View {
        let selected = selectedScene == beat.sceneSpineID
        let width = CGFloat(220 * zoom)
        return VStack(alignment: .leading, spacing: 6) {
            Text(beat.sceneSpineID)
                .font(.caption.monospacedDigit())
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Button {
                model.pauseEditPlayback()
                if let first = model.timedEditClips.first(where: { $0.clip.sceneSpineID == beat.sceneSpineID }) {
                    model.seekEdit(to: first.start)
                } else { model.selectEditorialBeat(beat) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(beat.title.uppercased()).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Text(beat.editClips.isEmpty ? "No timed clips" : String(format: "%.1fs · %d clips", beat.editDurationSeconds, beat.editClips.count))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(width: width, height: 80, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                .overlay(Rectangle().stroke(selected ? Color.accentColor : ScreenplayOSTokens.Palette.separator,
                                            lineWidth: selected ? 2 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Move Earlier in Edit") { model.moveEditorialBeat(beat.id, direction: -1) }
                Button("Move Later in Edit") { model.moveEditorialBeat(beat.id, direction: 1) }
            }
            .accessibilityLabel("\(beat.sceneSpineID), \(beat.title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if !beat.editClips.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(beat.editClips.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }) { clip in
                            Button {
                                if let entry = model.timedEditClips.first(where: { $0.id == clip.id }) {
                                    model.seekEdit(to: entry.start)
                                }
                            } label: {
                                Text(clip.label).font(.caption2).lineLimit(1)
                                    .padding(6)
                                    .frame(width: max(54, min(180, clip.timelineDurationSeconds * 20 * zoom)))
                                    .background(model.activeBoardFrame?.id == clip.boardFrameID && clip.boardFrameID != nil
                                                ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.1))
                            }
                            .buttonStyle(.plain)
                            .help(String(format: "%@ · %.1f seconds", clip.label, clip.timelineDurationSeconds))
                        }
                    }
                }
                .frame(width: width, height: 32)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
