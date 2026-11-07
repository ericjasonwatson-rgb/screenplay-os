import AppKit
import Combine
import Foundation
import ScreenplayDomain
import SwiftUI
import UniformTypeIdentifiers

/// Original first-party assembly interface, separate from the legacy planning
/// lane and from FilmCraft. Its edits persist in a project-bound sidecar.
struct NativeAssemblyWorkspaceView: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var assembly: NativeAssemblyProject?
    @State private var undoStack: [NativeAssemblyProject] = []
    @State private var selection: UUID?
    @State private var playheadFrame = 0
    @State private var playing = false
    @State private var playbackStartedAt: Date?
    @State private var playbackBaseFrame = 0
    @State private var message: String?
    @State private var exportInProgress = false
    @State private var videoImportInProgress = false
    @State private var rebuildConfirmation = false
    @State private var cachedPreview: NSImage?
    @State private var previewRequestID = UUID()
    @State private var previewProblem: String?
    @State private var previewLoading = false
    @State private var previewTask: Task<Void, Never>?
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var sceneID: String? {
        model.selectedSceneBreakdown?.editSpineID ?? model.editorialBeats.first?.sceneSpineID
    }
    private var sourceBoards: [BoardFrame] {
        guard let sceneID else { return [] }
        return model.boardFrames.filter { $0.sceneSpineID == sceneID }
    }
    private var screenplayURL: URL? { model.saveURL ?? model.sourceURL }
    private var containsVideo: Bool {
        assembly?.clips.contains(where: { $0.mediaKind == .video }) ?? false
    }
    private var isStale: Bool {
        guard let assembly else { return false }
        return !assembly.isCurrent(with: sourceBoards)
    }
    private var currentClip: NativeAssemblyClip? {
        guard let assembly else { return nil }
        return assembly.clip(at: min(playheadFrame, max(0, assembly.totalFrames - 1)))
    }
    private func refreshPreview() {
        // Cancellation also stops expensive SHA hashing when a scrub moves on.
        previewTask?.cancel()
        previewTask = nil
        // Distinguish each clip/frame request so a slow decoder cannot place
        // an old image over a newly selected shot.
        let requestID = UUID()
        previewRequestID = requestID
        previewProblem = nil
        previewLoading = false
        guard let currentClip, let screenplayURL else {
            cachedPreview = nil
            return
        }
        switch currentClip.mediaKind {
        case .stillImage:
            guard let file = try? NativeAssemblyMovieExporter.verifiedStill(
                currentClip, documentURL: screenplayURL) else {
                cachedPreview = nil
                previewProblem = "Selected still image is missing or has changed."
                return
            }
            cachedPreview = NSImage(contentsOf: file)
        case .video:
            cachedPreview = nil
            previewLoading = true
            let localFrame = max(0, min(currentClip.frameCount - 1,
                                        playheadFrame - startFrame(for: currentClip.id)))
            previewTask = Task {
                do {
                    let decoded = try await NativeVideoFramePreview.preview(
                        currentClip, localFrame: localFrame, screenplayURL: screenplayURL)
                    guard previewRequestID == requestID else { return }
                    cachedPreview = NSImage(data: decoded.pngData)
                    previewProblem = cachedPreview == nil ? "The decoded frame could not be displayed." : nil
                    previewLoading = false
                } catch {
                    guard previewRequestID == requestID else { return }
                    cachedPreview = nil
                    previewProblem = error.localizedDescription
                    previewLoading = false
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Native Assembly", systemImage: "film.stack").font(.headline)
                Text(sceneID ?? "Select a scene").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if let assembly {
                    Text("\(assembly.clips.count) clips · \(timecode(assembly.totalFrames))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(assembly == nil ? "Assemble Selected Boards" : "Rebuild From Boards") {
                    if assembly == nil { rebuild() } else { rebuildConfirmation = true }
                }
                .disabled(sceneID == nil || model.document == nil)
                Button("Import MOV/MP4 Take") { importVideo() }
                    .disabled(assembly == nil || selection == nil || isStale ||
                              videoImportInProgress || screenplayURL == nil)
                Button("Export Stills MP4") { exportVideo() }
                    .disabled(assembly == nil || containsVideo || isStale ||
                              exportInProgress || screenplayURL == nil)
                    .help(containsVideo ? "Video Takes require a tested decode/conform export path." :
                          "Export a silent still-image boardomatic.")
            }
            .padding(12)

            if let assembly {
                if isStale {
                    Label("Source boards changed after assembly. Rebuild intentionally before exporting.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption).padding(.horizontal, 12)
                }
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle().fill(Color.black)
                        if let cachedPreview {
                            Image(nsImage: cachedPreview)
                                .resizable().scaledToFit().padding(6)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark").font(.system(size: 30))
                                Text(previewLoading ? "Decoding selected video frame..." :
                                     (previewProblem ?? "No verified media frame to display"))
                                    .font(.caption).multilineTextAlignment(.center)
                            }.foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("OCCURRENCE").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Text(currentClip?.label ?? "No clip").font(.headline).lineLimit(2)
                        if let clip = currentClip {
                            Text("Take \(clip.takeID.uuidString.prefix(8))")
                            Text("Edit \(clip.id.uuidString.prefix(8))")
                            Text("\(clip.frameCount) frames · \(clip.mediaKind == .video ? "video Take" : "still image")")
                            if clip.mediaKind == .video {
                                Text("Source in \(clip.sourceInFrame)f / \(clip.sourceFrameLimit ?? 0)f")
                            }
                        }
                        Spacer()
                        Text("All changes are local. No AI requests or external editor sync.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption.monospaced())
                    .frame(width: 200, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 150, idealHeight: 260)
                Divider()

                HStack(spacing: 12) {
                    Button {
                        if playing { playing = false } else {
                            if playheadFrame >= assembly.totalFrames { playheadFrame = 0 }
                            playing = true
                            playbackBaseFrame = playheadFrame
                            playbackStartedAt = Date()
                        }
                    } label: {
                        Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                    }
                    .disabled(containsVideo)
                    .help(containsVideo ? "Mixed video/still playback awaits a verified decoder." :
                          "Play the still-image boardomatic.")
                    Slider(value: Binding(
                        get: { Double(playheadFrame) },
                        set: { playing = false; playheadFrame = Int($0) }
                    ), in: 0...Double(max(1, assembly.totalFrames)), step: 1)
                    Text("\(timecode(playheadFrame)) / \(timecode(assembly.totalFrames))")
                        .font(.caption.monospacedDigit())
                }
                .padding(12)

                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(assembly.clips) { clip in
                            Button {
                                selection = clip.id
                                playheadFrame = startFrame(for: clip.id)
                                playing = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(clip.label).font(.caption.weight(.semibold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Text("\(clip.frameCount)f").font(.caption2.monospacedDigit())
                                }
                                .padding(9)
                                .frame(width: max(95, min(260, CGFloat(clip.frameCount) * 2)), height: 82,
                                       alignment: .leading)
                                .foregroundStyle(.white)
                                .background(clip.id == selection ? Color.blue.opacity(0.85) : Color.gray.opacity(0.50))
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .stroke(clip.id == currentClip?.id ? Color.orange : .clear, lineWidth: 2))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(12)
                }.frame(height: 108)

                HStack(spacing: 8) {
                    Button("−1 Frame") { if let selection {
                        perform { try $0.trimming(selection, toFrames: length(for: selection) - 1) }
                    }}
                    Button("+1 Frame") { if let selection {
                        perform { try $0.trimming(selection, toFrames: length(for: selection) + 1) }
                    }}
                    Button("Trim Head +1") { if let selection {
                        perform { try $0.trimmingHead(selection, byFrames: 1) }
                    }}
                    Button("Split at Playhead") { if let selection {
                        let local = playheadFrame - startFrame(for: selection)
                        perform { try $0.splitting(selection, afterFrames: local) }
                    }}
                    Button("Duplicate") { if let selection {
                        perform { try $0.duplicating(selection) }
                    }}
                    Button("Move Left") { if let selection {
                        perform { try $0.moving(selection, by: -1) }
                    }}
                    Button("Move Right") { if let selection {
                        perform { try $0.moving(selection, by: 1) }
                    }}
                    Spacer()
                    Button("Undo") { undo() }.disabled(undoStack.isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack").font(.system(size: 36))
                    Text("Build a local assembly from selected board images.")
                        .font(.headline)
                    Text("The Script, Shot and Boards workspaces remain authoritative. This independent cut is stored beside your project in local application support.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .background(Color.black.opacity(0.15))
        .onAppear { load() }
        .onChange(of: model.document?.screenplay.id) { _ in load() }
        .onChange(of: sceneID) { _ in load() }
        .onChange(of: currentClip?.id) { _ in refreshPreview() }
        .onChange(of: playheadFrame) { _ in
            if currentClip?.mediaKind == .video { refreshPreview() }
        }
        .onReceive(timer) { now in
            guard playing, let assembly, let playbackStartedAt else { return }
            let elapsed = max(0, now.timeIntervalSince(playbackStartedAt))
            playheadFrame = NativeAssemblyProject.playbackFrame(
                from: playbackBaseFrame, after: elapsed, totalFrames: assembly.totalFrames)
            if playheadFrame >= assembly.totalFrames { playing = false }
        }
        .onDisappear {
            playing = false
            previewTask?.cancel()
            previewTask = nil
            previewRequestID = UUID()
        }
        .confirmationDialog("Rebuild this assembly from current selected boards?",
                            isPresented: $rebuildConfirmation) {
            Button("Rebuild Assembly") { rebuild() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the separate local assembly cut; the original screenplay and boards are not changed.")
        }
    }

    private func timecode(_ frames: Int) -> String {
        let fps = NativeAssemblyProject.framesPerSecond
        let seconds = max(0, frames) / fps
        return String(format: "%02d:%02d:%02d:%02d", seconds / 3600,
                      (seconds / 60) % 60, seconds % 60, max(0, frames) % fps)
    }

    private func path() throws -> URL {
        guard let projectID = model.document?.screenplay.id, let sceneID else {
            throw NativeAssemblyError.wrongProject
        }
        return try NativeAssemblyFileStore.url(projectID: projectID, sceneSpineID: sceneID)
    }

    private func load() {
        previewTask?.cancel()
        previewTask = nil
        playing = false
        undoStack = []
        selection = nil
        playheadFrame = 0
        assembly = nil
        cachedPreview = nil
        previewRequestID = UUID()
        previewProblem = nil
        previewLoading = false
        message = nil
        guard let projectID = model.document?.screenplay.id, let sceneID else { return }
        do {
            let file = try path()
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            assembly = try NativeAssemblyFileStore.load(from: file,
                        projectID: projectID, sceneSpineID: sceneID)
            selection = assembly?.clips.first?.id
            if isStale { message = "Boards have changed. The saved assembly is retained for review." }
            refreshPreview()
        } catch {
            message = "The saved local assembly could not be opened. Nothing was overwritten. \(error)"
        }
    }

    private func rebuild() {
        guard let projectID = model.document?.screenplay.id, let sceneID else { return }
        do {
            let next = try NativeAssemblyProject.assemble(
                projectID: projectID, sceneSpineID: sceneID, boards: sourceBoards)
            try NativeAssemblyFileStore.save(next, to: path())
            if let assembly { undoStack.append(assembly) }
            assembly = next
            selection = next.clips.first?.id
            playheadFrame = 0
            playing = false
            refreshPreview()
            message = "Local assembly saved. The source boards were not modified."
        } catch {
            message = "Assembly was not changed: \(error)"
        }
    }

    private func startFrame(for id: UUID) -> Int {
        guard let assembly else { return 0 }
        var position = 0
        for clip in assembly.clips {
            if clip.id == id { return position }
            position += clip.frameCount
        }
        return 0
    }

    private func length(for id: UUID) -> Int {
        assembly?.clips.first(where: { $0.id == id })?.frameCount ?? 0
    }

    private func perform(_ change: (NativeAssemblyProject) throws -> NativeAssemblyProject) {
        guard let current = assembly else { return }
        do {
            let next = try change(current)
            try NativeAssemblyFileStore.save(next, to: path())
            undoStack.append(current)
            if undoStack.count > 100 { undoStack.removeFirst() }
            assembly = next
            playheadFrame = min(playheadFrame, next.totalFrames)
            playing = false
            refreshPreview()
            message = "Edit saved locally."
        } catch {
            message = "Edit refused: \(error)"
        }
    }

    private func undo() {
        guard let prior = undoStack.last else { return }
        do {
            try NativeAssemblyFileStore.save(prior, to: path())
            undoStack.removeLast()
            assembly = prior
            selection = prior.clips.first?.id
            playheadFrame = min(playheadFrame, prior.totalFrames)
            playing = false
            refreshPreview()
            message = "Previous assembly restored."
        } catch {
            message = "Undo could not be saved: \(error)"
        }
    }

    private func importVideo() {
        guard let current = assembly, let selection,
              let parent = current.clips.first(where: { $0.id == selection }),
              let screenplayURL, !isStale else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        videoImportInProgress = true
        playing = false
        message = "Verifying and importing a local video Take..."
        Task {
            let access = source.startAccessingSecurityScopedResource()
            defer {
                if access { source.stopAccessingSecurityScopedResource() }
                videoImportInProgress = false
            }
            do {
                let imported = try await NativeVideoTakeImporter.importLocalVideo(
                    source, screenplayURL: screenplayURL, after: parent)
                // Do not adopt a late result if the timeline was edited while
                // video was being validated or copied.
                guard assembly == current else {
                    message = "The timeline changed during import; the new Take was not adopted."
                    return
                }
                let next = try current.insertingVideoTake(imported, after: selection)
                try NativeAssemblyFileStore.save(next, to: path())
                undoStack.append(current)
                if undoStack.count > 100 { undoStack.removeFirst() }
                assembly = next
                self.selection = imported.id
                playheadFrame = startFrame(for: imported.id)
                refreshPreview()
                message = "Video Take added. Paused frame scrubbing is available; realtime video playback and export remain gated."
            } catch {
                message = "Video import refused: \(error.localizedDescription)"
            }
        }
    }

    private func exportVideo() {
        guard let assembly, let screenplayURL, !isStale else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ScreenplayOS-Assembly.mp4"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        exportInProgress = true
        playing = false
        message = "Rendering a local 720p, 24 fps still-image boardomatic..."
        Task {
            do {
                try await NativeAssemblyMovieExporter.render(assembly,
                    documentURL: screenplayURL, outputURL: output)
                message = "Exported \(output.lastPathComponent)"
            } catch {
                message = "MP4 export failed: \(error.localizedDescription)"
            }
            exportInProgress = false
        }
    }
}
