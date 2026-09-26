import Foundation

public struct ArticleSnapshot: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let feedTitle: String
    public let date: Date
    public let summary: String?
    public let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, feedTitle, date, summary, isRead
    }

    public init(
        id: UUID,
        title: String,
        feedTitle: String,
        date: Date,
        summary: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
        self.date = date
        self.summary = summary
        self.isRead = isRead
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.feedTitle = try container.decode(String.self, forKey: .feedTitle)
        self.date = try container.decode(Date.self, forKey: .date)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }
}
