import Foundation

/// A conservative, deterministic filter for the default Smart Feed.
/// It never deletes data: every excluded item remains available in All Articles.
public enum SmartFeedFilter {
    public static func filteredArticles(from articles: [FeedItem]) -> [FeedItem] {
        var seenURLs: Set<String> = []
        var seenTitles: Set<String> = []

        return articles.filter { article in
            // Explicit user intent always wins over automatic filtering.
            if article.isStarred {
                remember(article, seenURLs: &seenURLs, seenTitles: &seenTitles)
                return true
            }

            guard !isHighConfidenceNoise(article) else { return false }

            let urlKey = canonicalURLKey(article.link)
            let titleKey = normalizedTitle(article.title)
            guard urlKey.map({ !seenURLs.contains($0) }) ?? true,
                  titleKey.isEmpty || !seenTitles.contains(titleKey) else {
                return false
            }

            if let urlKey { seenURLs.insert(urlKey) }
            if !titleKey.isEmpty { seenTitles.insert(titleKey) }
            return true
        }
    }

    private static func remember(
        _ article: FeedItem,
        seenURLs: inout Set<String>,
        seenTitles: inout Set<String>
    ) {
        if let urlKey = canonicalURLKey(article.link) { seenURLs.insert(urlKey) }
        let titleKey = normalizedTitle(article.title)
        if !titleKey.isEmpty { seenTitles.insert(titleKey) }
    }

    private static func isHighConfidenceNoise(_ article: FeedItem) -> Bool {
        let title = article.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let markers = [
            "[sponsored]",
            "sponsored post",
            "sponsored content",
            "partner content",
            "paid post",
            "advertisement:",
            "from our partners",
            "deal of the day",
            "coupon code",
            "we're hiring",
            "we are hiring",
            "job opening",
            "sponsorlu içerik",
            "reklam içeriği",
            "iş ilanı"
        ]
        return markers.contains { title.contains($0) }
    }

    private static func normalizedTitle(_ title: String) -> String {
        let simplified = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
        return simplified
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    private static func canonicalURLKey(_ rawValue: String?) -> String? {
        guard let rawValue,
              var components = URLComponents(string: rawValue) else { return nil }
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_")
                && name != "ref"
                && name != "source"
                && name != "campaign"
        }
        return components.url?.absoluteString
    }
}
