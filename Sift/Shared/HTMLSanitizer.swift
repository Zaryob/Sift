import Foundation

public enum HTMLSanitizer {
    /// Strips HTML tags and decodes common HTML entities to safely display text in native SwiftUI controls
    public static func stripTags(from html: String) -> String {
        guard !html.isEmpty else { return "" }
        
        // Quick regex to strip HTML tags
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
        
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        
        // Clean up excessive whitespace and newline clusters
        let components = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return components.joined(separator: " ")
    }
}
