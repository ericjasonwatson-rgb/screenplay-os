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
    @State private var lastPlaybackTick: Date?
    @State private var message: String?
    @State private var exportInProgress = false
    @State private var rebuildConfirmation = false
    @State private var cachedPreview: NSImage?
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var sceneID: String? {
        model.selectedSceneBreakdown?.editSpineID ?? model.editorialBeats.first?.sceneSpineID
    }
    private var sourceBoards: [BoardFrame] {
        guard let sceneID else { return [] }
        return model.boardFrames.filter { $0.sceneSpineID == sceneID }
    }
    private var screenplayURL: URL? { model.saveURL ?? model.sourceURL }
    private var isStale: Bool {
        guard let assembly else { return false }
        return !assembly.isCurrent(with: sourceBoards)
    }
    private var currentClip: NativeAssemblyClip? {
        guard let assembly else { return nil }
        return assembly.clip(at: min(playheadFrame, max(0, assembly.totalFrames - 1)))
    }
    private func refreshPreview() {
        guard let currentClip, let screenplayURL,
              let file = try? NativeAssemblyMovieExporter.verifiedStill(currentClip, documentURL: screenplayURL)
        else { cachedPreview = nil; return }
        cachedPreview = NSImage(contentsOf: file)
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
                Button("Export MP4") { exportVideo() }
                    .disabled(assembly == nil || isStale || exportInProgress || screenplayURL == nil)
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
                                Text("Selected image unavailable or fingerprint mismatch")
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
                            Text("\(clip.frameCount) frames · still image")
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
                            lastPlaybackTick = Date()
                        }
                    } label: {
                        Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                    }
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
        .onReceive(timer) { now in
            guard playing, let assembly else { return }
            let elapsed = now.timeIntervalSince(lastPlaybackTick ?? now)
            let frames = Int((elapsed * Double(NativeAssemblyProject.framesPerSecond)).rounded(.down))
            guard frames > 0 else { return }
            playheadFrame = min(assembly.totalFrames, playheadFrame + frames)
            lastPlaybackTick = now
            if playheadFrame >= assembly.totalFrames { playing = false }
        }
        .onDisappear { playing = false }
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
        playing = false
        undoStack = []
        selection = nil
        playheadFrame = 0
        assembly = nil
        cachedPreview = nil
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
