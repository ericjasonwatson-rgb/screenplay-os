import AppKit
import SwiftUI

/// Display styling only. Printed screenplay layout and authored data are unchanged.
enum StudioAppearance {
    static let panel = Color(white: 0.29)
    static let raised = Color(white: 0.35)
    static func paper(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white }
    static func ink(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.9, alpha: 1) : NSColor(calibratedWhite: 0.08, alpha: 1) }
    static func courier(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Courier-Bold" : "Courier", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

struct StudioSurface: View {
    var body: some View {
        StudioAppearance.panel
    }
}

struct ScriptPageWell<Content: View>: View {
    var width: CGFloat = 760
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(width: max(280, min(width, geometry.size.width - 32)))
                    .overlay { Rectangle().strokeBorder(.black.opacity(0.25), lineWidth: 1).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                Spacer(minLength: 0)
            }.padding(.vertical, 16)
        }.background { StudioSurface() }
    }
}
