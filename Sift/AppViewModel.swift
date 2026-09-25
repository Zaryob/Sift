import Foundation
import SwiftUI
import SwiftData
import Observation
import WidgetKit

public enum SidebarItem: Hashable, Identifiable {
    case all
    case unread
    case starred
    case feed(UUID)

    public var id: String {
        switch self {
        case .all: return "all"
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
    
    public var isShowingSettings: Bool = false

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
        if index > 0 {
            selectedArticle = articles[index - 1]
        }
    }

    public func markAllAsRead(in articles: [FeedItem], context: ModelContext) {
        for article in articles where !article.isRead {
            article.isRead = true
        }
        do {
            try context.save()
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to save read state: \(error)")
        }
    }

    public func refreshAllFeeds(context: ModelContext? = nil) {
        Task {
            await refreshAll(context: context)
        }
    }

    public func refreshAll(context: ModelContext? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await refreshService.refreshAllFeeds()
        isRefreshing = false
        WidgetSnapshotManager.shared.updateSnapshot(context: context ?? PersistenceController.shared.container.mainContext)
        WidgetCenter.shared.reloadAllTimelines()
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
            var latestTitle: String?
            var latestID: UUID?
            for parsedItem in parsedFeed.items {
                let newItem = FeedItem(
                    guid: parsedItem.guid,
                    title: parsedItem.title,
                    link: parsedItem.link,
                    author: parsedItem.author,
                    summary: parsedItem.summary,
                    content: parsedItem.content,
                    imageURL: parsedItem.imageURL,
                    publicationDate: parsedItem.publicationDate,
                    discoveredDate: Date(),
                    isRead: false,
                    isStarred: false,
                    feed: newFeed
                )
                context.insert(newItem)
                if latestTitle == nil {
                    latestTitle = parsedItem.title
                    latestID = newItem.id
                }
            }

            try context.save()
            
            // Update widget snapshot & timelines
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()

            // Post an individual notification for the latest article of the newly added feed
            // (Old articles do not trigger separate notifications, and no batched "(X new articles)" banner)
            if let title = latestTitle, let articleID = latestID {
                let faviconURL = FaviconFetcher.faviconURL(for: newFeed.siteURL, feedURLString: newFeed.url, iconURLString: newFeed.iconURL)
                NotificationManager.shared.sendArticleNotification(
                    articleTitle: title,
                    feedTitle: newFeed.title,
                    articleID: articleID,
                    feedID: newFeed.id,
                    faviconURL: faviconURL
                )
            }

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
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to delete feed: \(error)")
        }
    }

    public func openArticleExternally(_ article: FeedItem) {
        guard let linkStr = article.link, let url = URL(string: linkStr) else { return }
        Platform.openURL(url)
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
                item.isRead = true
                try? context.save()

                // Re-affirm selectedArticle on next main tick to avoid list synchronization reset
                DispatchQueue.main.async { [weak self] in
                    self?.selectedArticle = item
                }
            }
        }
    }

    /// Imports subscriptions from an OPML file opened externally (Files app, Mail, AirDrop, "Open With").
    public func importOPMLFile(at url: URL, context: ModelContext) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            showError("Could not read the OPML file.")
            return
        }

        guard let items = try? OPMLService().parse(data: data), !items.isEmpty else {
            showError("The file doesn't contain any recognizable feed subscriptions.")
            return
        }

        for item in items {
            let targetURL = item.xmlURL
            let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == targetURL })
            if (try? context.fetch(descriptor).first) == nil {
                let newFeed = Feed(title: item.title, url: item.xmlURL, siteURL: item.htmlURL, category: item.category, dateAdded: Date())
                context.insert(newFeed)
            }
        }
        try? context.save()
        await refreshService.refreshAllFeeds()
        await MainActor.run {
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
