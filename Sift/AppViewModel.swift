import Foundation
import SwiftUI
import SwiftData
import Observation

public enum SidebarItem: Hashable, Identifiable {
    case all
    case today
    case thisWeek
    case unread
    case starred
    case feed(UUID)

    public var id: String {
        switch self {
        case .all: return "all"
        case .today: return "today"
        case .thisWeek: return "thisWeek"
        case .unread: return "unread"
        case .starred: return "starred"
        case .feed(let uuid): return "feed-\(uuid.uuidString)"
        }
    }
}

@MainActor
@Observable
public final class AppViewModel {
    public var selectedSidebarItem: SidebarItem? = .all
    public var selectedArticle: FeedItem?
    
    public var isAddingFeed: Bool = false
    public var addFeedURLString: String = ""
    public var addFeedCategoryString: String = ""
    public var isAddingFeedLoading: Bool = false
    
    public var errorMessage: String?
    public var showErrorAlert: Bool = false
    public var isRefreshing: Bool = false

    private let refreshService: FeedRefreshService
    private let httpClient: FeedHTTPClientProtocol
    private let discoveryService: FeedDiscoveryService

    public init(
        refreshService: FeedRefreshService = FeedRefreshService(),
        httpClient: FeedHTTPClientProtocol = FeedHTTPClient(),
        discoveryService: FeedDiscoveryService = FeedDiscoveryService()
    ) {
        self.refreshService = refreshService
        self.httpClient = httpClient
        self.discoveryService = discoveryService
    }

    public func selectNextArticle(in articles: [FeedItem]) {
        guard !articles.isEmpty else { return }
        guard let current = selectedArticle, let index = articles.firstIndex(where: { $0.id == current.id }) else {
            selectedArticle = articles.first
            return
        }
        if index + 1 < articles.count {
            selectedArticle = articles[index + 1]
        }
    }

    public func selectPreviousArticle(in articles: [FeedItem]) {
        guard !articles.isEmpty else { return }
        guard let current = selectedArticle, let index = articles.firstIndex(where: { $0.id == current.id }) else {
            selectedArticle = articles.first
            return
        }
        if index - 1 >= 0 {
            selectedArticle = articles[index - 1]
        }
    }

    public func refreshAllFeeds() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await refreshService.refreshAllFeeds()
            self.isRefreshing = false
        }
    }

    public func addFeed(context: ModelContext) async {
        var trimmedURL = addFeedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.lowercased().hasPrefix("http://") && !trimmedURL.lowercased().hasPrefix("https://") {
            trimmedURL = "https://" + trimmedURL
        }

        let trimmedCategory = addFeedCategoryString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: trimmedURL) else {
            showError("Please enter a valid URL.")
            return
        }

        isAddingFeedLoading = true
        defer { isAddingFeedLoading = false }

        do {
            // 1. Try Auto-Discovery first if web page URL passed
            let discovered = (try? await discoveryService.discoverFeeds(from: url)) ?? []
            let targetURL = discovered.first?.url ?? url

            let result = try await httpClient.fetchFeed(from: targetURL, etag: nil, lastModified: nil)
            guard case .success(let data, let etag, let lastModified, let responseURL) = result else {
                showError("Could not retrieve feed content from URL.")
                return
            }

            let parser = FeedParser()
            let parsedFeed = try parser.parse(data: data)

            // Save new Feed entity
            let newFeed = Feed(
                title: parsedFeed.title,
                url: responseURL.absoluteString,
                siteURL: parsedFeed.siteURL,
                feedDescription: parsedFeed.feedDescription,
                iconURL: parsedFeed.iconURL,
                category: trimmedCategory.isEmpty ? nil : trimmedCategory,
                dateAdded: Date(),
                lastSuccessfulRefresh: Date(),
                etag: etag,
                lastModified: lastModified
            )
            context.insert(newFeed)

            // Insert initial articles
            for parsedItem in parsedFeed.items {
                let newItem = FeedItem(
                    guid: parsedItem.guid,
                    title: parsedItem.title,
                    link: parsedItem.link,
                    author: parsedItem.author,
                    summary: parsedItem.summary,
                    content: parsedItem.content,
                    publicationDate: parsedItem.publicationDate,
                    discoveredDate: Date(),
                    isRead: false,
                    isStarred: false,
                    feed: newFeed
                )
                context.insert(newItem)
            }

            try context.save()
            
            // Reset state
            addFeedURLString = ""
            addFeedCategoryString = ""
            isAddingFeed = false
            selectedSidebarItem = .feed(newFeed.id)

        } catch {
            showError("Failed to add feed: \(error.localizedDescription)")
        }
    }

    public func updateFeedCategory(_ feed: Feed, category: String?, context: ModelContext) {
        feed.category = category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : category
        try? context.save()
    }

    public func deleteFeed(_ feed: Feed, context: ModelContext) {
        if case .feed(let id) = selectedSidebarItem, id == feed.id {
            selectedSidebarItem = .all
        }
        context.delete(feed)
        do {
            try context.save()
        } catch {
            print("Failed to delete feed: \(error)")
        }
    }

    public func openArticleExternally(_ article: FeedItem) {
        guard let linkStr = article.link, let url = URL(string: linkStr) else { return }
        NSWorkspace.shared.open(url)
    }

    public func handleDeepLink(_ url: URL, context: ModelContext) {
        guard let destination = DeepLinkRouter.parse(url: url) else { return }
        switch destination {
        case .all:
            selectedSidebarItem = .all
        case .feed(let id):
            selectedSidebarItem = .feed(id)
        case .article(let id):
            let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == id })
            if let item = try? context.fetch(descriptor).first {
                if let feed = item.feed {
                    selectedSidebarItem = .feed(feed.id)
                } else {
                    selectedSidebarItem = .all
                }
                selectedArticle = item
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
