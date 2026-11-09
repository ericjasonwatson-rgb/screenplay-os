// Launch the relocated bundle through LaunchServices (the Finder launch path).
// Run only on a disposable CI user; never opens a screenplay or contacts providers.
import AppKit
import CoreGraphics

let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.arguments = ["-ApplePersistenceIgnoreState", "YES"]
var launched: NSRunningApplication?
var failure: Error?
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
    launched = app
    failure = error
}
let deadline = Date().addingTimeInterval(45)
var visible = false
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    if let error = failure { fatalError("LaunchServices failed: \(error)") }
    guard let app = launched else { continue }
    if app.isTerminated { fatalError("Application exited before window verification") }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    visible = windows.contains {
        ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier &&
        ($0[kCGWindowLayer as String] as? Int) == 0
    }
    if visible && app.isFinishedLaunching { break }
}
guard let app = launched, visible, app.bundleURL?.standardizedFileURL == appURL else {
    launched?.forceTerminate()
    fatalError("No visible window from the expected relocated app within 45 seconds")
}
// Catch immediate post-launch crashes too.
let settle = Date().addingTimeInterval(5)
while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
guard !app.isTerminated else { fatalError("App crashed after showing its window") }
print("PASS: LaunchServices opened relocated app and showed a window; PID \(app.processIdentifier)")
app.terminate()
