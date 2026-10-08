import AppKit
import SwiftUI

/// Display styling only. Printed screenplay layout and authored data are unchanged.
enum StudioAppearance {
    static let panel = Color(red: 0.25, green: 0.26, blue: 0.27)
    static let raised = Color(red: 0.34, green: 0.35, blue: 0.36)
    static let recess = Color(white: 0.17)
    static let hover = Color(white: 0.43)
    static let edge = Color(white: 0.13)
    static let highlight = Color.white.opacity(0.10)
    static let accent = Color(red: 0.88, green: 0.73, blue: 0.39)
    static let aiBlue = Color(red: 0.12, green: 0.34, blue: 0.62)
    static let selection = Color(red: 0.28, green: 0.43, blue: 0.46)
    static func sceneColor(_ key: String) -> Color {
        let colors: [Color] = [Color(red: 0.48, green: 0.70, blue: 0.70), Color(red: 0.69, green: 0.64, blue: 0.79), Color(red: 0.76, green: 0.68, blue: 0.46), Color(red: 0.56, green: 0.69, blue: 0.52)]
        let index = key.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }
        return colors[index]
    }
    static func paper(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white }
    static func ink(_ dark: Bool) -> NSColor { dark ? NSColor(calibratedWhite: 0.9, alpha: 1) : NSColor(calibratedWhite: 0.08, alpha: 1) }
    static func courier(size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Courier-Bold" : "Courier", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

struct StudioSurface: View {
    var body: some View {
        StudioAppearance.recess
    }
}

struct ScriptPageWell<Content: View>: View {
    var width: CGFloat = 760
    var verticalInset: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(width: max(280, min(width, geometry.size.width - 32)))
                    .overlay { Rectangle().strokeBorder(.black.opacity(0.25), lineWidth: 1).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                Spacer(minLength: 0)
            }.padding(.vertical, verticalInset)
        }.background { StudioSurface() }
    }
}

/// Attached control surfaces, with distinct resting, hover and pressed states.
struct StudioButtonStyle: ButtonStyle {
    var selected = false
    var ai = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected, ai: ai)
    }
    private struct Surface: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        let ai: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).frame(minHeight: 24)
                .foregroundStyle(selected ? Color.black : Color(white: 0.94))
                .background(selected ? StudioAppearance.accent : (configuration.isPressed ? StudioAppearance.recess : (ai ? StudioAppearance.aiBlue.opacity(hovering ? 0.8 : 1) : (hovering ? StudioAppearance.hover : StudioAppearance.raised))))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(StudioAppearance.edge, lineWidth: 1) }
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

struct StudioToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(StudioButtonStyle(selected: configuration.isOn))
            .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension View {
    func studioStrip() -> some View {
        self.background(StudioAppearance.panel)
            .overlay(alignment: .top) { StudioAppearance.highlight.frame(height: 1).allowsHitTesting(false) }
            .overlay(alignment: .bottom) { StudioAppearance.edge.frame(height: 1).allowsHitTesting(false) }
    }
}

/// Shared blue surfaces identify suggestions without tinting authored screenplay text.
private struct AISurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark
                ? Color(red: 0.10, green: 0.19, blue: 0.30)
                : Color(red: 0.88, green: 0.94, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(StudioAppearance.aiBlue, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func aiSurface() -> some View { modifier(AISurface()) }
}
