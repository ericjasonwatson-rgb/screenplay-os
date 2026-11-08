// Read only window metadata, not screenshots, titles, or Accessibility contents.
// CGWindowListCopyWindowInfo's owner PID/layer/bounds do not need Screen Recording.
import AppKit
import CoreGraphics
import Foundation

@main
struct WindowProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[1]) else {
            exit(2)
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let expectedExecutable = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.resolvingSymlinksInPath()
        let executableMatches = app?.executableURL?.standardizedFileURL.resolvingSymlinksInPath() == expectedExecutable
        let finishedLaunching = app?.isFinishedLaunching == true
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let count = windows.filter { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber else { return false }
            return width.doubleValue >= 900 && height.doubleValue >= 560
        }.count
        let data = try JSONSerialization.data(withJSONObject: ["pid": Int(pid), "visibleWindowCount": count,
            "finishedLaunching": finishedLaunching, "executableMatches": executableMatches], options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
