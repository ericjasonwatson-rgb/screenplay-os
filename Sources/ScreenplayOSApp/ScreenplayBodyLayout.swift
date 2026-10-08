import AppKit
import ScreenplayDomain

/// Existing legacy print geometry, shared with the continuous writing surface.
/// Page splitting and continuation placement remain owned by the print paginator.
// Internal calibration only: no preference, persisted field, or user-facing conversion.
enum ScreenplayLineLayout: Hashable {
    case legacy, twelvePointExperiment, twelvePointFlowExperiment, twelvePointPageTopExperiment
    var splitsSpeechAfterCue: Bool { self == .twelvePointFlowExperiment || self == .twelvePointPageTopExperiment }
    var removesPageTopSpacing: Bool { self == .twelvePointPageTopExperiment }
    var minimumParagraphHeight: CGFloat { self == .legacy ? 16 : 12 }
}

enum ScreenplayBodyLayout {
    static let textLeft: CGFloat = 108
    static let textWidth: CGFloat = 432

    static func spec(for type: ElementType) -> PDFLayoutSpec {
        switch type {
        case .sceneHeading:
            return PDFLayoutSpec(x: 108, width: 432, before: 24, after: 0, alignment: .left, weight: .semibold)
        case .action, .general:
            return PDFLayoutSpec(x: 108, width: 432, before: 12, after: 0, alignment: .left, weight: .regular)
        case .character:
            return PDFLayoutSpec(x: 252, width: 270, before: 12, after: 0, alignment: .left, weight: .semibold)
        case .dialogue:
            return PDFLayoutSpec(x: 180, width: 252, before: 0, after: 0, alignment: .left, weight: .regular)
        case .parenthetical:
            return PDFLayoutSpec(x: 216, width: 180, before: 0, after: 0, alignment: .left, weight: .regular)
        case .transition:
            return PDFLayoutSpec(x: 396, width: 115, before: 12, after: 0, alignment: .right, weight: .semibold)
        case .shot:
            return PDFLayoutSpec(x: 108, width: 432, before: 12, after: 0, alignment: .left, weight: .semibold)
        case .pageBreak:
            return PDFLayoutSpec(x: 108, width: 432, before: 24, after: 24, alignment: .center, weight: .regular)
        }
    }

    static func textStyle(alignment: NSTextAlignment, scale: CGFloat = 1, lineLayout: ScreenplayLineLayout = .legacy) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        if lineLayout == .legacy { style.lineSpacing = 2 * scale }
        else { style.minimumLineHeight = 12 * scale; style.maximumLineHeight = 12 * scale }
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func editorStyle(for type: ElementType, scale: CGFloat, lineLayout: ScreenplayLineLayout = .legacy) -> NSParagraphStyle {
        let layout = spec(for: type)
        let style = textStyle(alignment: layout.alignment, scale: scale, lineLayout: lineLayout)
        let leading = layout.x - textLeft
        style.firstLineHeadIndent = leading * scale
        style.headIndent = leading * scale
        style.tailIndent = -(textWidth - leading - layout.width) * scale
        style.paragraphSpacingBefore = layout.before * scale
        style.paragraphSpacing = layout.after * scale
        return style
    }
}
