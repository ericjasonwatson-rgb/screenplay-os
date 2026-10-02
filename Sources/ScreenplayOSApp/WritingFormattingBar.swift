import AppKit
import SwiftUI
import ScreenplayDomain

/// Both editors invoke their own undoable commands through the same controls.
struct WritingFormattingBar: View {
    let settings: DocumentTypography
    let changeFont: (String) -> Void
    let changeSize: (Double) -> Void
    let active: (KeyPath<StyledText.Style, Bool?>) -> Bool
    let toggle: (WritableKeyPath<StyledText.Style, Bool?>) -> Void
    let clear: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                typographyControls
                Divider().frame(height: 18)
                emphasisControls
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { typographyControls }
                HStack(spacing: 6) { emphasisControls }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).controlSize(.small)
    }
    @ViewBuilder private var typographyControls: some View {
        Picker("Font", selection: Binding(get: { settings.fontFamily }, set: changeFont)) {
            ForEach(Array(Set(NSFontManager.shared.availableFontFamilies + [settings.fontFamily])).sorted(), id: \.self) { Text($0).tag($0) }
        }.frame(width: 170).accessibilityLabel("Document font")
            .help("Font family for the screenplay and printed script.")
        Picker("Size", selection: Binding(get: { settings.fontSize }, set: changeSize)) {
            ForEach(Array(Set([8.0, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72] + [settings.fontSize])).sorted(), id: \.self) {
                Text(String(format: "%g pt", $0)).tag($0)
            }
        }.frame(width: 90).accessibilityLabel("Document font size")
            .help("Point size for screenplay text. Zoom changes only the view.")
    }
    @ViewBuilder private var emphasisControls: some View {
        emphasis("Bold", symbol: "bold", key: \.bold)
        emphasis("Italic", symbol: "italic", key: \.italic)
        emphasis("Underline", symbol: "underline", key: \.underline)
        Menu("Format") {
            Toggle("Bold", isOn: binding(\.bold)).keyboardShortcut("b", modifiers: .command)
            Toggle("Italic", isOn: binding(\.italic)).keyboardShortcut("i", modifiers: .command)
            Toggle("Underline", isOn: binding(\.underline)).keyboardShortcut("u", modifiers: .command)
            Toggle("Strikethrough", isOn: binding(\.strikethrough))
            Button("Clear Emphasis", action: clear)
        }.fixedSize()
    }
    private func binding(_ key: WritableKeyPath<StyledText.Style, Bool?>) -> Binding<Bool> {
        Binding(get: { active(key) }, set: { _ in toggle(key) })
    }
    private func emphasis(_ title: String, symbol: String, key: WritableKeyPath<StyledText.Style, Bool?>) -> some View {
        Toggle(isOn: binding(key)) { Image(systemName: symbol).frame(width: 18) }
            .toggleStyle(StudioToggleStyle()).accessibilityLabel(title).help(title + " for selected text or subsequent typing")
    }
}
