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

public enum ArticleScope: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case starred = "Starred"
    case today = "Today"

    public var id: String { rawValue }
}

/// A feed that has been fetched and parsed but not yet saved.
public struct FeedPreview {
    public let url: URL
    public let parsed: ParsedFeed
    public let etag: String?
    public let lastModified: String?

    public var host: String {
        URL(string: parsed.siteURL ?? "")?.host() ?? url.host() ?? url.absoluteString
    }

    public var latestDate: Date? {
        parsed.items.map(\.publicationDate).max()
    }
}

public enum FeedLookupResult {
    case preview(FeedPreview)
    case choices([DiscoveredFeed])
}

public enum FeedLookupError: LocalizedError {
    case invalidAddress
    case noFeedFound
    case alreadySubscribed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return String(localized: "That doesn’t look like a web address.")
        case .noFeedFound:
            return String(localized: "No RSS or Atom feed found at this address.")
        case .alreadySubscribed(let title):
            return String(localized: "You’re already subscribed to \(title).")
        }
    }
}

@MainActor
@Observable
public final class AppViewModel {
    public var selectedSidebarItem: SidebarItem? = .all
    public var selectedArticle: FeedItem?
    
    public var isAddingFeed: Bool = false
    public var isShowingSettings: Bool = false

    public var lastRefreshedAt: Date? = Date()
    public var lastMarkedReadArticles: [FeedItem] = []
    public var toastMessage: String?

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
        var changed: [FeedItem] = []
        for article in articles where !article.isRead {
            article.isRead = true
            changed.append(article)
        }
        lastMarkedReadArticles = changed
        if !changed.isEmpty {
            toastMessage = "\(changed.count) articles marked as read"
        }
        do {
            try context.save()
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to save read state: \(error)")
        }
    }

    public func undoMarkAllAsRead(context: ModelContext) {
        guard !lastMarkedReadArticles.isEmpty else { return }
        for article in lastMarkedReadArticles {
            article.isRead = false
        }
        lastMarkedReadArticles = []
        toastMessage = nil
        do {
            try context.save()
            WidgetSnapshotManager.shared.updateSnapshot(context: context)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to undo mark as read: \(error)")
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
        lastRefreshedAt = Date()
        isRefreshing = false
        WidgetSnapshotManager.shared.updateSnapshot(context: context ?? PersistenceController.shared.container.mainContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Adding feeds

    /// Turns whatever the user typed ("evrimagaci.org", a page URL, a feed URL) into either a single
    /// feed preview or, when a site advertises several feeds, the list to choose from.
    public func lookUpFeed(_ input: String, existingFeedURLs: Set<String>) async throws -> FeedLookupResult {
        guard let url = Self.normalizedURL(from: input) else {
            throw FeedLookupError.invalidAddress
        }
        let discovered = try await discoveryService.discoverFeeds(from: url)
        let candidates = Array(Set(discovered)).sorted { $0.title < $1.title }
        switch candidates.count {
        case 0:
            throw FeedLookupError.noFeedFound
        case 1:
            return .preview(try await loadPreview(for: candidates[0].url, existingFeedURLs: existingFeedURLs))
        default:
            return .choices(candidates)
        }
    }

    public func loadPreview(for feedURL: URL, existingFeedURLs: Set<String>) async throws -> FeedPreview {
        let result = try await httpClient.fetchFeed(from: feedURL, etag: nil, lastModified: nil)
        guard case .success(let data, let etag, let lastModified, let responseURL) = result else {
            throw FeedLookupError.noFeedFound
        }
        guard let parsed = try? FeedParser().parse(data: data) else {
            throw FeedLookupError.noFeedFound
        }
        let preview = FeedPreview(url: responseURL, parsed: parsed, etag: etag, lastModified: lastModified)
        if existingFeedURLs.contains(responseURL.absoluteString) || existingFeedURLs.contains(feedURL.absoluteString) {
            throw FeedLookupError.alreadySubscribed(parsed.title)
        }
        return preview
    }

    /// Saves the feed and articles already fetched for the preview; nothing is downloaded again.
    public func subscribe(to preview: FeedPreview, folder: String?, context: ModelContext) throws {
        let parsed = preview.parsed
        let newFeed = Feed(
            title: parsed.title,
            url: preview.url.absoluteString,
            siteURL: parsed.siteURL,
            feedDescription: parsed.feedDescription,
            iconURL: parsed.iconURL,
            category: folder,
            dateAdded: Date(),
            lastSuccessfulRefresh: Date(),
            etag: preview.etag,
            lastModified: preview.lastModified
        )
        context.insert(newFeed)

        for item in parsed.items {
            context.insert(FeedItem(
                guid: item.guid,
                title: item.title,
                link: item.link,
                author: item.author,
                summary: item.summary,
                content: item.content,
                imageURL: item.imageURL,
                publicationDate: item.publicationDate,
                discoveredDate: Date(),
                isRead: false,
                isStarred: false,
                feed: newFeed
            ))
        }

        try context.save()
        WidgetSnapshotManager.shared.updateSnapshot(context: context)
        WidgetCenter.shared.reloadAllTimelines()

        isAddingFeed = false
        selectedSidebarItem = .feed(newFeed.id)
    }

    public static func normalizedURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" "), !text.contains("\n") else { return nil }
        if text.lowercased().hasPrefix("feed:") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host(), host.contains(".") else {
            return nil
        }
        return url
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

    /// Fetches and caches the article's full text. Failures are remembered for a day so a page
    /// that can't be extracted isn't re-downloaded every time it's opened.
    public func loadFullTextIfNeeded(for article: FeedItem, context: ModelContext) async {
        guard article.extractedArticleData == nil,
              let link = article.link, let url = URL(string: link) else { return }
        if let attempted = article.extractionAttemptedAt, Date().timeIntervalSince(attempted) < 86_400 {
            return
        }

        let result = try? await ArticleExtractor.fetch(url: url, summary: article.summary ?? article.content)
        article.extractionAttemptedAt = Date()
        if let result, let data = try? JSONEncoder().encode(result) {
            article.extractedArticleData = data
            if article.imageURL == nil {
                article.imageURL = result.leadImageURL
            }
        }
        try? context.save()
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
