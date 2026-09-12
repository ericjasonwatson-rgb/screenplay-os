import Foundation
import ScreenplayDomain

struct RecoveryRecord: Codable {
    let document: OpenScreenplayDocument
    let originalURL: URL?
    let savedAt: Date
}

struct RecoveryCopy: Identifiable {
    let url: URL
    let title: String
    let savedAt: Date
    var id: URL { url }
}
