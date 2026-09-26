import Foundation

nonisolated public enum HTMLSanitizer {
    /// Single-line plain text for snippets and search (all markup collapsed to spaces).
    public static func stripTags(from html: String) -> String {
        guard !html.isEmpty else { return "" }
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return normalizeWhitespace(restoreSentenceSpacing(decodeEntities(text)))
    }

    /// Paragraphs for the reader: block-level tags become paragraph breaks instead of spaces.
    public static func paragraphs(from html: String) -> [String] {
        guard !html.isEmpty else { return [] }
        var text = html.replacingOccurrences(
            of: "<\\s*(br|/p|/div|/li|/h[1-6]|/blockquote|/tr)\\b[^>]*>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = restoreSentenceSpacing(decodeEntities(text))
        return text
            .components(separatedBy: "\n\n")
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }
    }

    public static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Some publishers join paragraphs without a space when truncating ("uyandırdı.Montana").
    /// Only restores a space after a word of 2+ lowercase letters, so abbreviations like "U.S." stay intact.
    static func restoreSentenceSpacing(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(\\p{Ll}{2,}[.!?…])(\\p{Lu})",
            with: "$1 $2",
            options: .regularExpression
        )
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "bull": "•",
        "middot": "·", "copy": "©", "reg": "®", "trade": "™", "deg": "°", "shy": ""
    ]

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let entity = ns.substring(with: match.range(at: 1))
            result += decode(entity: entity) ?? ns.substring(with: match.range)
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func decode(entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if entity.hasPrefix("#") {
            return UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[entity.lowercased()]
    }
}
