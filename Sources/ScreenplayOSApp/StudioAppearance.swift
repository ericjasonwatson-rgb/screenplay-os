import AppKit
import SwiftUI

/// Display styling only. Printed screenplay layout and authored data are unchanged.
enum StudioAppearance {
    static let panel = Color(red: 0.20, green: 0.22, blue: 0.24)
    static let raised = Color(red: 0.25, green: 0.27, blue: 0.29)
    static func paper(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white }
    static func ink(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.9, alpha: 1) : NSColor(calibratedWhite: 0.08, alpha: 1) }
    static func courier(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Courier-Bold" : "Courier", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

struct StudioSurface: View {
    var body: some View {
        LinearGradient(colors: [StudioAppearance.raised, StudioAppearance.panel], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    var lines = Path()
                    for y in stride(from: 0.0, to: size.height, by: 4) {
                        lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.white.opacity(0.012)), lineWidth: 0.5)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
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
