import AVFoundation
import AppKit
import CryptoKit
import Foundation
import ScreenplayDomain
import UniformTypeIdentifiers

enum EditAudioWorkflow {
    static var applicationSupportRoot: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
    }

    static func storageURL(projectID: UUID, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("ScreenplayOS/Audio/\(projectID.uuidString)/audio-v1.json")
    }

    static func storedMediaURL(source: URL, beside documentURL: URL) throws -> (url: URL, sha256: String) {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 250_000_000 else { throw EditAudioError.invalidMedia }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let ext = source.pathExtension.lowercased()
        guard ["wav", "aif", "aiff", "m4a", "mp3", "caf"].contains(ext) else { throw EditAudioError.invalidMedia }
        let directory = documentURL.deletingLastPathComponent().appendingPathComponent("Audio Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(digest).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard existing.isRegularFile == true, existing.isSymbolicLink != true,
                  SHA256.hash(data: try Data(contentsOf: destination)).map({ String(format: "%02x", $0) }).joined() == digest else {
                throw EditAudioError.invalidMedia
            }
        } else {
            try data.write(to: destination, options: [.atomic, .withoutOverwriting])
        }
        return (destination, digest)
    }
}

@MainActor
final class EditAudioPlayer {
    private var players: [UUID: AVAudioPlayer] = [:]

    func stop() {
        players.values.forEach { $0.stop() }
        players.removeAll()
    }

    func synchronize(ledger: EditAudioLedger?, playhead: Double, playing: Bool) {
        guard playing, let ledger else { stop(); return }
        let active = ledger.activeSlices(at: playhead)
        let activeIDs = Set(active.map(\.clip.id))
        for (id, player) in players where !activeIDs.contains(id) {
            player.stop(); players[id] = nil
        }
        for slice in active {
            if let current = players[slice.clip.id], current.isPlaying { continue }
            guard let player = try? AVAudioPlayer(contentsOf: slice.clip.mediaURL) else { continue }
            player.currentTime = min(player.duration, slice.sourceOffsetSeconds)
            player.prepareToPlay()
            player.play()
            players[slice.clip.id] = player
        }
    }
}

extension ScreenplayViewModel {
    func loadEditAudio() {
        editAudioPlayer.stop()
        guard let projectID = document?.screenplay.id else {
            editAudioLedger = nil; editAudioStatus = nil; return
        }
        do {
            let url = try EditAudioWorkflow.storageURL(projectID: projectID, root: editAudioRoot)
            editAudioLedger = FileManager.default.fileExists(atPath: url.path)
                ? try EditAudioFileStore.read(from: url)
                : EditAudioLedger(projectID: projectID)
            editAudioStatus = nil
        } catch {
            editAudioLedger = EditAudioLedger(projectID: projectID)
            editAudioStatus = "The local audio lanes could not be read. The screenplay was not changed."
        }
    }

    func showImportAudioClipPanel(lane: EditAudioLane) {
        guard requireEntitlement(.animaticAudio) else { return }
        guard saveURL != nil else {
            editAudioStatus = "Save the screenplay before importing audio."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import \(lane.rawValue.capitalized) Audio"
        panel.message = "The clip starts at the current Edit playhead. Existing clips and source files are retained."
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do { try importAudioClip(source, lane: lane, start: editPlayheadSeconds) }
        catch { editAudioStatus = "Could not import that audio clip. Use WAV, AIFF, M4A, MP3, or CAF under 250 MB." }
    }

    func importAudioClip(_ source: URL, lane: EditAudioLane, start: Double) throws {
        guard requireEntitlement(.animaticAudio) else { return }
        guard let documentURL = saveURL, var ledger = editAudioLedger,
              ledger.projectID == document?.screenplay.id else { throw EditAudioError.projectMismatch }
        let stored = try EditAudioWorkflow.storedMediaURL(source: source, beside: documentURL)
        let player = try AVAudioPlayer(contentsOf: stored.url)
        guard player.duration.isFinite, player.duration > 0 else { throw EditAudioError.invalidTiming }
        let clip = EditAudioClip(
            lane: lane, name: source.deletingPathExtension().lastPathComponent,
            mediaURL: stored.url, sha256: stored.sha256,
            timelineStartSeconds: max(0, start), durationSeconds: player.duration
        )
        ledger.clips.append(clip)
        try persistEditAudio(ledger)
        editAudioStatus = "Imported \(clip.name) into the \(lane.rawValue) lane."
    }

    func removeAudioClip(_ id: UUID) {
        guard requireEntitlement(.animaticAudio) else { return }
        guard var ledger = editAudioLedger else { return }
        ledger.clips.removeAll { $0.id == id }
        do {
            try persistEditAudio(ledger)
            editAudioStatus = "Removed the clip from the timeline. Its media file was retained."
        } catch {
            editAudioStatus = "The audio-lane change could not be saved."
        }
    }

    private func persistEditAudio(_ ledger: EditAudioLedger) throws {
        let url = try EditAudioWorkflow.storageURL(projectID: ledger.projectID, root: editAudioRoot)
        try EditAudioFileStore.write(ledger, to: url)
        editAudioLedger = ledger
    }
}
