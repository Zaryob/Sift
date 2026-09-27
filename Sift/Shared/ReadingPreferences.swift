import SwiftUI

/// AppStorage keys for reading behavior. Settings > Reading is the single place these are edited.
enum ReadingPreferenceKey {
    static let density = "articleDensity"
    static let markReadBehavior = "markReadBehavior"
    static let openLinksInApp = "openLinksInApp"
    static let fontSize = "readerFontSize"
    static let fontDesign = "readerFontDesign"
    static let showFeedIcons = "showFeedIcons"
    static let showArticlePreviews = "showArticlePreviews"
    static let readerTheme = "readerTheme"
    static let readerLineSpacing = "readerLineSpacing"
    static let readerContentWidth = "readerContentWidth"
}

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case paper = "Paper"
    case sepia = "Sepia"
    case night = "Night"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .paper: return String(localized: "Paper")
        case .sepia: return String(localized: "Sepia")
        case .night: return String(localized: "Night")
        }
    }

    public func backgroundColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .system:
            #if os(macOS)
            return Color(nsColor: .textBackgroundColor)
            #else
            return Color(uiColor: .systemBackground)
            #endif
        case .paper:
            return colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.96, green: 0.96, blue: 0.96)
        case .sepia:
            return colorScheme == .dark ? Color(red: 0.18, green: 0.15, blue: 0.12) : Color(red: 0.97, green: 0.95, blue: 0.89)
        case .night:
            return Color.black
        }
    }

    public func textColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .system:
            return Color.primary
        case .paper:
            return colorScheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.92) : Color(red: 0.12, green: 0.12, blue: 0.12)
        case .sepia:
            return colorScheme == .dark ? Color(red: 0.91, green: 0.86, blue: 0.80) : Color(red: 0.28, green: 0.22, blue: 0.16)
        case .night:
            return Color(red: 0.88, green: 0.88, blue: 0.88)
        }
    }

    public func secondaryTextColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .system:
            return Color.secondary
        case .paper:
            return colorScheme == .dark ? Color(red: 0.65, green: 0.65, blue: 0.65) : Color(red: 0.45, green: 0.45, blue: 0.45)
        case .sepia:
            return colorScheme == .dark ? Color(red: 0.68, green: 0.62, blue: 0.56) : Color(red: 0.52, green: 0.44, blue: 0.36)
        case .night:
            return Color(red: 0.58, green: 0.58, blue: 0.58)
        }
    }
}

public enum ReaderLineSpacing: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case normal = "Normal"
    case relaxed = "Relaxed"

    public var id: String { rawValue }

    public var multiplier: CGFloat {
        switch self {
        case .compact: return 0.22
        case .normal: return 0.35
        case .relaxed: return 0.52
        }
    }
}

public enum ReaderContentWidth: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case wide = "Wide"

    public var id: String { rawValue }

    public var maxWidth: CGFloat {
        switch self {
        case .compact: return 560
        case .standard: return 660
        case .wide: return 780
        }
    }
}

enum ArticleDensity: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case comfortable = "Comfortable"
    case spacious = "Spacious"

    var id: String { rawValue }
}

enum MarkReadBehavior: String, CaseIterable, Identifiable {
    case whenOpened = "When Opened"
    case afterDelay = "After 3 Seconds"
    case manually = "Manually"

    var id: String { rawValue }
}

enum ReaderFontDesign: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case monospaced = "Monospace"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}
