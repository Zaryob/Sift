import AppIntents
import Foundation
import SwiftData

public struct ArticleEntity: AppEntity, Identifiable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Article")
    public static var defaultQuery = ArticleEntityQuery()

    public let id: UUID
    public let title: String
    public let feedTitle: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(feedTitle)"
        )
    }

    public init(id: UUID, title: String, feedTitle: String) {
        self.id = id
        self.title = title
        self.feedTitle = feedTitle
    }

    @MainActor
    public init(article: FeedItem) {
        self.init(
            id: article.id,
            title: article.title,
            feedTitle: article.feed?.title ?? String(localized: "Unknown source")
        )
    }
}

public struct ArticleEntityQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [UUID]) async throws -> [ArticleEntity] {
        let context = ModelContext(PersistenceController.shared.container)
        let descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate { identifiers.contains($0.id) }
        )
        return try context.fetch(descriptor).map(ArticleEntity.init(article:))
    }

    @MainActor
    public func suggestedEntities() async throws -> [ArticleEntity] {
        let context = ModelContext(PersistenceController.shared.container)
        var descriptor = FetchDescriptor<FeedItem>(
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        return try context.fetch(descriptor).map(ArticleEntity.init(article:))
    }
}
