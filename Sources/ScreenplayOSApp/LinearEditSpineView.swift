import SwiftUI

/// One duration-scaled editorial timeline, with untimed scenes available separately.
struct LinearEditSpineView: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var zoom = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label("Timeline", systemImage: "timeline.selection").font(.headline)
                Text("\(model.editorialBeats.count) scenes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Scene Script", isOn: $model.showEditScript)
                    .toggleStyle(StudioToggleStyle())
                    .help("Show or hide the script beside the Edit viewer")
                Toggle("Estimates", isOn: $model.showEditEstimates).toggleStyle(StudioToggleStyle())
                Button("Fit") { zoom = 1 }.help("Fit the full edit in the timeline")
                Slider(value: $zoom, in: 1...32).frame(width: 100).accessibilityLabel("Edit timeline zoom")
            }.padding(12)
            Divider()
            EditTimeLane(model: model, zoom: zoom)
            HStack {
                Text("SCENE SPINE").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("24 fps · Drag ruler to scrub · Right-click a clip to reorder its scene").font(.caption)
                Spacer()
                if model.untimedEditSceneCount > 0 {
                    Menu("\(model.untimedEditSceneCount) untimed") {
                        ForEach(model.editorialBeats.filter { beat in !model.editTimeline.contains { $0.sceneSpineID == beat.sceneSpineID } }) { beat in
                            Button(beat.title) { model.selectEditorialBeat(beat) }
                        }
                    }
                }
            }.foregroundStyle(.secondary).padding(12)
        }.background(ScreenplayOSTokens.Palette.panelBackground)
    }
}
