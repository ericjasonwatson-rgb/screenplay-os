import AppKit
import SwiftUI
import ScreenplayDomain

extension RevisionColor {
    var displayName: String {
        switch self {
        case .blue:
            return "Blue"
        case .pink:
            return "Pink"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .goldenrod:
            return "Goldenrod"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .blue:
            return .blue
        case .pink:
            return .pink
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .goldenrod:
            return .orange
        }
    }

    var nsColor: NSColor {
        NSColor(swiftUIColor)
    }
}
