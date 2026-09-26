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
    public var content: String?
    public var imageURL: String?
    public var publicationDate: Date
    public var discoveredDate: Date
    public var isRead: Bool
    public var isStarred: Bool
    /// JSON-encoded `ExtractedArticle`: the full text pulled from the publisher's page.
    public var extractedArticleData: Data?
    public var extractionAttemptedAt: Date?

    public var feed: Feed?

    public init(
        id: UUID = UUID(),
        guid: String? = nil,
        title: String,
        link: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        content: String? = nil,
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

    /// Reading time only when we actually know the length of the article, never from an excerpt.
    public var knownReadingMinutes: Int? {
        if let extracted = extractedArticle {
            return extracted.readingMinutes
        }
        guard let content else { return nil }
        let words = HTMLSanitizer.stripTags(from: content).split(whereSeparator: \.isWhitespace).count
        return words >= 200 ? max(1, Int((Double(words) / 220).rounded(.up))) : nil
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
