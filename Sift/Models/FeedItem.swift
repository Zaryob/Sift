import Foundation
import SwiftData

@Model
public final class FeedItem {
    @Attribute(.unique) public var id: UUID
    public var guid: String?
    public var title: String
    public var link: String?
    public var author: String?
    public var summary: String?
    @Attribute(.externalStorage) public var content: String?
    public var imageURL: String?
    public var publicationDate: Date
    public var discoveredDate: Date
    public var isRead: Bool
    public var isStarred: Bool
    /// Precomputed plain-text snippet for instant, zero-regex list row rendering.
    public var snippet: String?
    /// Precomputed reading minutes to avoid JSON decoding during view updates.
    public var readingMinutes: Int?
    /// JSON-encoded `ExtractedArticle`: the full text pulled from the publisher's page.
    @Attribute(.externalStorage) public var extractedArticleData: Data?
    public var extractionAttemptedAt: Date?
    @Attribute(.externalStorage) public var translatedArticleData: Data?
    public var translatedTitle: String?
    public var translationSourceLanguage: String?
    public var translationTargetLanguage: String?
    public var translationVersion: Int?
    public var translationSourceContentHash: String?

    public var feed: Feed?
    @Relationship(deleteRule: .cascade, inverse: \ArticleIntelligenceResult.article)
    public var intelligenceResults: [ArticleIntelligenceResult] = []

    public init(
        id: UUID = UUID(),
        guid: String? = nil,
        title: String,
        link: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        content: String? = nil,
        snippet: String? = nil,
        readingMinutes: Int? = nil,
        imageURL: String? = nil,
        publicationDate: Date = Date(),
        discoveredDate: Date = Date(),
        isRead: Bool = false,
        isStarred: Bool = false,
        feed: Feed? = nil
    ) {
        self.id = id
        self.guid = guid
        self.title = title
        self.link = link
        self.author = author
        self.summary = summary
        self.content = content
        if let snippet {
            self.snippet = snippet
        } else {
            let raw = (summary?.isEmpty == false ? summary : content)
            if let raw {
                let stripped = HTMLSanitizer.stripTags(from: raw)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.snippet = stripped.isEmpty ? nil : String(stripped.prefix(200))
            } else {
                self.snippet = nil
            }
        }
        if let readingMinutes {
            self.readingMinutes = readingMinutes
        } else if let content {
            let words = HTMLSanitizer.stripTags(from: content).split(whereSeparator: \.isWhitespace).count
            self.readingMinutes = words >= 200 ? max(1, Int((Double(words) / 220).rounded(.up))) : nil
        } else {
            self.readingMinutes = nil
        }
        self.imageURL = imageURL
        self.publicationDate = publicationDate
        self.discoveredDate = discoveredDate
        self.isRead = isRead
        self.isStarred = isStarred
        self.feed = feed
    }
    
    public var extractedArticle: ExtractedArticle? {
        guard let extractedArticleData else { return nil }
        return try? JSONDecoder().decode(ExtractedArticle.self, from: extractedArticleData)
    }

    public var translatedArticle: ExtractedArticle? {
        guard let translatedArticleData else { return nil }
        return try? JSONDecoder().decode(ExtractedArticle.self, from: translatedArticleData)
    }

    /// Reading time only when we actually know the length of the article, never from an excerpt.
    public var knownReadingMinutes: Int? {
        if let readingMinutes {
            return readingMinutes
        }
        if let extracted = extractedArticle {
            return extracted.readingMinutes
        }
        guard let content else { return nil }
        let words = HTMLSanitizer.stripTags(from: content).split(whereSeparator: \.isWhitespace).count
        return words >= 200 ? max(1, Int((Double(words) / 220).rounded(.up))) : nil
    }

    /// Word count of whatever text came embedded in the RSS feed (content or summary).
    public var feedWordCount: Int {
        let text = content ?? summary ?? ""
        guard !text.isEmpty else { return 0 }
        let stripped = HTMLSanitizer.stripTags(from: text)
        return stripped.split(whereSeparator: \.isWhitespace).count
    }

    /// Whether the RSS feed itself provided a full article body rather than a short summary/teaser.
    public var hasSubstantialFeedContent: Bool {
        return feedWordCount >= 300
    }

    /// True if the article is only a brief snippet/excerpt and full text has not yet been extracted from the web.
    public var isExcerpt: Bool {
        if extractedArticleData != nil {
            return false
        }
        return !hasSubstantialFeedContent
    }

    public var deduplicationKey: String {
        if let guid = guid, !guid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "guid:\(guid)"
        }
        if let link = link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "link:\(link)"
        }
        let feedIdStr = feed?.id.uuidString ?? "nofeed"
        return "fallback:\(feedIdStr):\(title):\(publicationDate.timeIntervalSince1970)"
    }
}
