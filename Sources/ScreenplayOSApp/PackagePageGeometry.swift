import AppKit

/// Logical points shared by the continuous writing surface and US Letter output.
/// Display resizing must not change these typesetting measurements.
enum PackagePageGeometry {
    static let width: CGFloat = 612
    static let height: CGFloat = 792
    static let left: CGFloat = 108
    static let right: CGFloat = 72
    static let top: CGFloat = 72
    static let textWidth = width - left - right
    static let textHeight: CGFloat = 648
    static func paragraphStyle(for type: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 14
        style.paragraphSpacing = 12
        switch type {
        case "character": style.firstLineHeadIndent = 144; style.headIndent = 144; style.paragraphSpacing = 0
        case "dialogue": style.firstLineHeadIndent = 72; style.headIndent = 72; style.tailIndent = -108; style.paragraphSpacing = 0
        case "parenthetical": style.firstLineHeadIndent = 108; style.headIndent = 108; style.tailIndent = -144; style.paragraphSpacing = 0
        case "transition": style.alignment = .right
        default: break
        }
        return style
    }
}
