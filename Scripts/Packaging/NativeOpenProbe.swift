// External disposable-runner helper, never compiled into or shipped with the app.
// Sends real OS document-open events. Reads only public process/window metadata
// and the existing post-decode recent-document preference, never window titles,
// rendered content, Accessibility, screenshots, or private app diagnostics.
import AppKit
import CoreFoundation
import CoreGraphics
import Darwin
import Dispatch
import Foundation

private struct ProbeFailure: Error {
    let message: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeFailure(message: message) }
}

// Foundation may reintroduce /var after resolving /private/var. Compare actual
// existing filesystem paths on both sides, not two APIs' URL string spellings.
// Do not fall back to a filename, matching bytes, or an unresolved path.
private func filesystemPath(_ path: String) -> String? {
    guard path.hasPrefix("/"), !path.utf8.contains(0), let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}

private func sameFilesystemPath(_ lhs: URL?, _ rhs: URL) -> Bool {
    guard let lhs, lhs.isFileURL, rhs.isFileURL,
          let left = filesystemPath(lhs.path), let right = filesystemPath(rhs.path) else { return false }
    return left == right
}

private func requiredFilesystemPath(_ url: URL) throws -> String {
    guard url.isFileURL, let path = filesystemPath(url.path) else {
        throw ProbeFailure(message: "An expected synthetic path could not be resolved on disk.")
    }
    return path
}

private func recentPathIdentity(_ path: String) -> String {
    // Preserve stale entries for unchanged-list comparisons, but never let an
    // unresolved preference entry match an existing requested input.
    filesystemPath(path).map { "resolved:" + $0 } ?? "unresolved:" + path
}

@MainActor
private final class NativeOpenSession {
    private let domain = "com.screenplayos.app"
    private let recentKey = "ScreenplayOSRecentDocuments"
    private let names = ["cold.screenplayos.json", "warm.screenplayos.json",
                         "multi-a.screenplayos.json", "multi-b.screenplayos.json",
                         "unsupported.txt", "malformed.screenplayos.json"]
    private let appURL: URL
    private let executableURL: URL
    private let inputDirectory: URL
    private var owned: NSRunningApplication?
    private var ownedLaunchDate: Date?
    private var initialPIDs = Set<pid_t>()
    private var mainWindowIDs: [Int]?
    private var signalSources: [DispatchSourceSignal] = []
    private var interrupted = false
    private var coldReply: Reply?
    private var failureObservation: [String: Any]?
    private var result: [String: Any] = ["schemaVersion": 1, "status": "failed", "scenarios": [String: Any]()]

    private final class Reply {
        var received = false
        var application: NSRunningApplication?
        var failed = false
    }

    init(appURL: URL, inputDirectory: URL) {
        self.appURL = appURL.standardizedFileURL
        self.executableURL = appURL.appendingPathComponent("Contents/MacOS/ScreenplayOS").standardizedFileURL
        self.inputDirectory = inputDirectory.standardizedFileURL
    }

    private func installSignalHandlers() {
        // Runner sends SIGTERM before escalation. Keep the helper alive long
        // enough to stop its LaunchServices-owned app, which is not its child.
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                DispatchQueue.main.async { self?.interrupted = true }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func tick() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    private func wait(seconds: TimeInterval, ignoringInterrupt: Bool = false,
                      until predicate: () -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !predicate() {
            try require(ignoringInterrupt || !interrupted, "Native-open probe was interrupted.")
            try require(ProcessInfo.processInfo.systemUptime < deadline, "Native-open observation timed out.")
            tick()
        }
    }

    private func matches(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier > 0
            && application.bundleIdentifier == domain
            && sameFilesystemPath(application.executableURL, executableURL)
            && sameFilesystemPath(application.bundleURL, appURL)
    }

    private func currentOwnedApplication() throws -> NSRunningApplication {
        guard let owned, let current = NSRunningApplication(processIdentifier: owned.processIdentifier) else {
            throw ProbeFailure(message: "The exact owned process is no longer available.")
        }
        try require(!owned.isTerminated && !current.isTerminated && matches(current)
                    && ownedLaunchDate != nil && current.launchDate == ownedLaunchDate,
                    "The owned process exited or its executable/launch identity changed.")
        return current
    }

    private func recentPaths() throws -> [String] {
        // Explicitly refresh the other process's existing preference domain.
        // Do not write, replace, reset, or inspect any other preference key.
        try require(CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
                    "Cross-process preferences could not be synchronized.")
        guard let value = CFPreferencesCopyValue(recentKey as CFString, domain as CFString,
                                                kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return [] }
        guard let paths = value as? [String] else {
            throw ProbeFailure(message: "The recent-document preference has an unexpected type.")
        }
        return paths
    }

    private func visibleMainWindowIDs(pid: pid_t) throws -> [Int] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            throw ProbeFailure(message: "Public window metadata is unavailable.")
        }
        return windows.compactMap { window -> Int? in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber, width.doubleValue >= 900,
                  let height = bounds["Height"] as? NSNumber, height.doubleValue >= 560,
                  let number = window[kCGWindowNumber as String] as? NSNumber, number.intValue > 0 else { return nil }
            return number.intValue
        }.sorted()
    }

    private func send(_ urls: [URL], cold: Bool) throws {
        if !cold { _ = try currentOwnedApplication() }
        let reply = Reply()
        if cold { coldReply = reply }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = cold
        configuration.promptsUserIfNeeded = false
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                reply.application = application
                reply.failed = error != nil
                reply.received = true
                // Claim only the exact returned, new executable instance. This
                // also lets cleanup handle a callback arriving after interruption.
                if cold, let application, self.matches(application),
                   !self.initialPIDs.contains(application.processIdentifier), let date = application.launchDate {
                    self.owned = application
                    self.ownedLaunchDate = date
                }
            }
        }
        try wait(seconds: 30) { reply.received }
        try require(!reply.failed, "NSWorkspace rejected the native-open request.")
        guard let application = reply.application, let owned else {
            throw ProbeFailure(message: "NSWorkspace did not return a verifiable new app instance.")
        }
        try require(matches(application) && application.processIdentifier == owned.processIdentifier
                    && application.launchDate == ownedLaunchDate,
                    "NSWorkspace returned a different application instance; that unowned instance was not terminated.")
    }

    private func exercise(_ name: String, urls: [URL], expectedFirst: URL, expectedOccurrences: Int,
                          cold: Bool = false, unchangedRecents: Bool = false) throws {
        failureObservation = ["requestedURLCount": urls.count, "sampleCount": 0, "workspaceCompletionReceived": false]
        let before = try recentPaths().map(recentPathIdentity)
        let rejectedPaths = Set(try names.dropFirst(2).map { try requiredFilesystemPath(inputDirectory.appendingPathComponent($0)) })
        let requestedPaths = Set(try urls.map(requiredFilesystemPath))
        let firstExpectedPath = try requiredFilesystemPath(expectedFirst)
        try send(urls, cold: cold)
        failureObservation?["workspaceCompletionReceived"] = true
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 30
        var stableStart: TimeInterval?
        var sampleCount = 0
        var everFirstMatched = false
        var everMainWindowVisible = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            try require(!interrupted, "Native-open probe was interrupted.")
            let application = try currentOwnedApplication()
            let paths = try recentPaths()
            let resolvedPaths = paths.compactMap(filesystemPath)
            let firstResolved = paths.first.flatMap(filesystemPath)
            let firstMatches = firstResolved == firstExpectedPath
            let listUnchanged = paths.map(recentPathIdentity) == before
            let rejectedAbsent = rejectedPaths.isDisjoint(with: resolvedPaths)
            let windows = try visibleMainWindowIDs(pid: application.processIdentifier)
            let matching = resolvedPaths.filter { requestedPaths.contains($0) }.count
            let ready = application.isFinishedLaunching && windows.count == 1
                && firstMatches && matching == expectedOccurrences
            let now = ProcessInfo.processInfo.systemUptime
            sampleCount += 1
            everFirstMatched = everFirstMatched || firstMatches
            everMainWindowVisible = everMainWindowVisible || windows.count == 1
            failureObservation = ["requestedURLCount": urls.count, "sampleCount": sampleCount,
                "workspaceCompletionReceived": true, "exactOwnedProcessVerified": true,
                "finishedLaunching": application.isFinishedLaunching, "visibleMainWindowCount": windows.count,
                "sameMainWindow": mainWindowIDs.map { $0 == windows } ?? (windows.count == 1),
                "recentDocumentCount": paths.count, "resolvedRecentPathCount": resolvedPaths.count,
                "firstRecentPathResolved": firstResolved != nil, "recentFirstMatches": firstMatches,
                "recentFirstAliasMatched": firstMatches && paths.first != expectedFirst.path,
                "matchingRecentURLCount": matching, "rejectedURLsAbsent": rejectedAbsent,
                "recentListUnchanged": listUnchanged, "recentListMustRemainUnchanged": unchangedRecents,
                "everRecentFirstMatched": everFirstMatched, "everMainWindowVisible": everMainWindowVisible,
                "elapsedMilliseconds": Int((now - started) * 1000),
                "stableObservationMilliseconds": stableStart.map { Int((now - $0) * 1000) } ?? 0]
            try require(rejectedAbsent, "A rejected document entered the loaded-model recent list.")
            if unchangedRecents {
                try require(listUnchanged, "A repeated or rejected request changed the recent-document list.")
            }
            if ready {
                if let mainWindowIDs {
                    try require(windows == mainWindowIDs, "Native open replaced the visible main window.")
                }
                if stableStart == nil { stableStart = now }
                let observed = now - (stableStart ?? now)
                if observed >= 2 {
                    mainWindowIDs = windows
                    result["pid"] = Int(application.processIdentifier)
                    var scenarios = result["scenarios"] as? [String: Any] ?? [:]
                    scenarios[name] = ["status": "passed", "pid": Int(application.processIdentifier),
                        "requestedURLCount": urls.count, "workspaceCompletionReceived": true,
                        "executableMatches": true, "finishedLaunching": true, "mainWindowIDs": windows,
                        "recentFirstMatches": true, "matchingRecentURLCount": matching,
                        "rejectedURLsAbsent": true, "stableObservationSeconds": observed]
                    result["scenarios"] = scenarios
                    failureObservation = nil
                    return
                }
            } else {
                stableStart = nil
            }
            tick()
        }
        throw ProbeFailure(message: "Native open did not produce stable loaded-model and main-window evidence: \(name).")
    }

    private func cleanup() throws -> [String: Any] {
        if let coldReply, !coldReply.received {
            // A late callback may identify the instance after a timeout/signal.
            try? wait(seconds: 3, ignoringInterrupt: true) { coldReply.received }
        }
        guard let owned else {
            if coldReply == nil { return ["status": "not_run", "reason": "No native launch request was sent."] }
            throw ProbeFailure(message: "No returned PID/executable could be safely owned; launch outcome remains unverified. No unknown process was terminated.")
        }
        var forced = false
        if !owned.isTerminated {
            _ = try currentOwnedApplication() // Verify exact PID/executable/launch date before every signal.
            _ = owned.terminate()
            try? wait(seconds: 1, ignoringInterrupt: true) { owned.isTerminated }
            if !owned.isTerminated {
                _ = try currentOwnedApplication()
                forced = true
                _ = owned.forceTerminate()
                try wait(seconds: 2, ignoringInterrupt: true) { owned.isTerminated }
            }
        }
        try require(owned.isTerminated, "The exact owned application did not terminate.")
        return ["status": "passed", "pid": Int(owned.processIdentifier), "executableMatches": true,
                "terminated": true, "forceTerminationUsed": forced]
    }

    func run() -> (data: Data, succeeded: Bool) {
        installSignalHandlers()
        defer { signalSources.forEach { $0.cancel() } }
        result["appPath"] = appURL.path
        result["executablePath"] = executableURL.path
        do {
            let environment = ProcessInfo.processInfo.environment
            try require(environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_ENVIRONMENT"] == "github-hosted",
                        "Native open is restricted to explicitly opted-in disposable hosted runners.")
            try require(FileManager.default.isExecutableFile(atPath: executableURL.path), "The exact app executable is missing.")
            let inputs = names.map { inputDirectory.appendingPathComponent($0) }
            for url in inputs {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                try require(values.isRegularFile == true && values.isSymbolicLink != true, "A synthetic input is missing or unsafe.")
            }
            let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
            initialPIDs = Set(running.map(\.processIdentifier))
            try require(!running.contains { $0.bundleIdentifier == domain || sameFilesystemPath($0.executableURL, executableURL) },
                        "An existing ScreenplayOS instance is running; no existing instance was changed.")
            let before = try recentPaths()
            try require(Set(try inputs.map(requiredFilesystemPath)).isDisjoint(with: before.compactMap(filesystemPath)),
                        "Synthetic native-open inputs already appear in recents.")
            result["initialRecentInputsAbsent"] = true
            try exercise("coldOpen", urls: [inputs[0]], expectedFirst: inputs[0], expectedOccurrences: 1, cold: true)
            try exercise("warmOpen", urls: [inputs[1]], expectedFirst: inputs[1], expectedOccurrences: 1)
            try exercise("repeatSameFile", urls: [inputs[1]], expectedFirst: inputs[1], expectedOccurrences: 1, unchangedRecents: true)
            try exercise("multipleURLsRejected", urls: [inputs[2], inputs[3]], expectedFirst: inputs[1], expectedOccurrences: 0, unchangedRecents: true)
            try exercise("unsupportedRejected", urls: [inputs[4]], expectedFirst: inputs[1], expectedOccurrences: 0, unchangedRecents: true)
            try exercise("malformedRejected", urls: [inputs[5]], expectedFirst: inputs[1], expectedOccurrences: 0, unchangedRecents: true)
            result["status"] = "passed"
        } catch {
            result["error"] = (error as? ProbeFailure)?.message ?? "Native-open input or metadata read failed."
            if let failureObservation { result["failureObservation"] = failureObservation }
        }
        do {
            result["cleanup"] = try cleanup()
        } catch {
            result["status"] = "failed"
            result["cleanup"] = ["status": "failed",
                "error": (error as? ProbeFailure)?.message ?? "Owned-instance cleanup failed."]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data("{}".utf8)
        return (data, result["status"] as? String == "passed")
    }
}

@main
struct NativeOpenProbe {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let session = NativeOpenSession(appURL: URL(fileURLWithPath: CommandLine.arguments[1]),
                                        inputDirectory: URL(fileURLWithPath: CommandLine.arguments[2]))
        let result = session.run()
        FileHandle.standardOutput.write(result.data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(result.succeeded ? 0 : 1)
    }
}
