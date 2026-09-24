import Foundation

public struct ArticleSnapshot: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let feedTitle: String
    public let date: Date

    public init(id: UUID, title: String, feedTitle: String, date: Date) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
        self.date = date
    }
}
