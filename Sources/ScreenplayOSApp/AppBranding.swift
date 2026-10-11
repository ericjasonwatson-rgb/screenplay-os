import AppKit
import SwiftUI

/// Branding stays in the Mac shell; it does not read or change project content.
@MainActor
enum AppBranding {
    /// Transparent master for every in-app use. The ICNS remains the application
    /// icon because macOS selects its size-specific representations for the Dock.
    static let logo: NSImage = {
        // Packaged macOS apps use Contents/Resources; swift run uses Bundle.module.
        let url = Bundle.main.url(forResource: "ScreenplayOSAppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "ScreenplayOSAppIcon", withExtension: "png")
        guard let url,
              let image = NSImage(contentsOf: url) else {
            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        return image
    }()

    static let appIcon: NSImage = {
        let url = Bundle.main.url(forResource: "ScreenplayOS", withExtension: "icns")
            ?? Bundle.module.url(forResource: "ScreenplayOS", withExtension: "icns")
        return url.flatMap(NSImage.init(contentsOf:)) ?? logo
    }()

    /// Use the transparent PNG directly; loading the ICNS here can select an
    /// opaque legacy representation on some macOS versions.
    static let menuBarIcon: NSImage = {
        let image = logo.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }()

    private static var aboutWindow: NSWindow?

    static func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
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

/// Always-visible branding, including when document panels are collapsed.
struct AppLogoButton: View {
    var body: some View {
        Button(action: AppBranding.showAbout) {
            Image(nsImage: AppBranding.logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About ScreenplayOS")
        .help("About ScreenplayOS")
    }
}
