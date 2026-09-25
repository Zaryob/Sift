import SwiftUI

/// Sift's visual language: one brand tint (the ember orange from the app icon, via the
/// AccentColor asset) plus a small set of semantic colors that are only used for state.
extension Color {
    static let siftStarred = Color.yellow
}

extension Font {
    /// Editorial serif used for article headlines and the Sift wordmark.
    static func siftSerif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}
