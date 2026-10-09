import AppKit
import SwiftUI

/// Branding stays in the Mac shell; it does not read or change project content.
@MainActor
enum AppBranding {
    static let logo: NSImage = {
        // Packaged macOS apps use Contents/Resources; swift run uses Bundle.module.
        let url = Bundle.main.url(forResource: "ScreenplayOSLogo", withExtension: "png")
            ?? Bundle.module.url(forResource: "ScreenplayOSLogo", withExtension: "png")
        guard let url,
              let image = NSImage(contentsOf: url) else {
            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        return image
    }()

    private static var aboutWindow: NSWindow?

    static func showAbout() {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About ScreenplayOS"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutScreenplayOSView())
        window.center()
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutScreenplayOSView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: AppBranding.logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 280, height: 280)
                .accessibilityLabel("screenplayOS — Concept to Screen")
            Text("ScreenplayOS")
                .font(.headline)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Local") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"))")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let revision = Bundle.main.object(forInfoDictionaryKey: "ScreenplayOSRevision") as? String {
                Text("Source \(revision)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
