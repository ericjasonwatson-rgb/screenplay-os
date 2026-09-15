import AppKit
import ScreenplayDomain

/// One native font/style adapter is shared by screen and PDF rendering.
@MainActor
enum PackageTypography {
    static func font(_ settings: DocumentTypography, style: StyledText.Style = .init(), displayScale: CGFloat = 1) -> NSFont {
        let size = settings.fontSize * displayScale
        let base = NSFont(name: settings.fontFamily, size: size) ?? StudioAppearance.courier(size: size)
        var traits: NSFontTraitMask = []
        if style.bold == true { traits.insert(.boldFontMask) }
        if style.italic == true { traits.insert(.italicFontMask) }
        return traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)
    }
    static func substitution(_ settings: DocumentTypography) -> String? {
        NSFont(name: settings.fontFamily, size: settings.fontSize) == nil ? "Font unavailable: \(settings.fontFamily). Display and PDF use Courier instead." : nil
    }
    static func apply(_ value: StyledText, settings: DocumentTypography, to text: NSMutableAttributedString, offset: Int,
                      displayScale: CGFloat = 1) {
        for run in value.resolvedRuns {
            let scalars = value.text.unicodeScalars
            let start = scalars.index(scalars.startIndex, offsetBy: run.start)
            let end = scalars.index(start, offsetBy: run.length)
            let local = NSRange(start..<end, in: value.text)
            let range = NSRange(location: offset + local.location, length: local.length)
            text.addAttributes([.font: font(settings, style: run.style, displayScale: displayScale),
                                .underlineStyle: run.style.underline == true ? NSUnderlineStyle.single.rawValue : 0,
                                .strikethroughStyle: run.style.strikethrough == true ? NSUnderlineStyle.single.rawValue : 0], range: range)
        }
    }
}
