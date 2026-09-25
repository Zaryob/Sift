import SwiftUI

/// AppStorage keys for reading behavior. Settings > Reading is the single place these are edited.
enum ReadingPreferenceKey {
    static let density = "articleDensity"
    static let markReadOnOpen = "markReadOnOpen"
    static let openLinksInApp = "openLinksInApp"
    static let fontSize = "readerFontSize"
    static let fontDesign = "readerFontDesign"
}

enum ArticleDensity: String, CaseIterable, Identifiable {
    case comfortable = "Comfortable"
    case compact = "Compact"

    var id: String { rawValue }
}

enum ReaderFontDesign: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        }
    }
}
