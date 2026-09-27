import Foundation
import SwiftData
import WidgetKit

public actor FeedRefreshService {
    private let httpClient: FeedHTTPClientProtocol
    private let modelContainer: ModelContainer
    private let pruningService: DataPruningService
    private var refreshingFeedIDs: Set<UUID> = []

    public init(
        httpClient: FeedHTTPClientProtocol = FeedHTTPClient(),
        modelContainer: ModelContainer? = nil
    ) {
        self.httpClient = httpClient
        let container = modelContainer ?? PersistenceController.shared.container
        self.modelContainer = container
        self.pruningService = DataPruningService(modelContainer: container)
    }

    /// Refresh a single feed by ID
    public func refreshFeed(id feedID: UUID, updateWidgetAndBadge: Bool = true) async throws {
        guard !refreshingFeedIDs.contains(feedID) else {
            return
        }
        refreshingFeedIDs.insert(feedID)
        defer { refreshingFeedIDs.remove(feedID) }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedID })
        guard let feed = try context.fetch(descriptor).first else {
            return
        }

        guard feed.enabled else { return }

        guard let feedURL = URL(string: feed.url) else {
            feed.lastRefreshAttempt = Date()
            feed.refreshError = "Invalid feed URL: \(feed.url)"
            try context.save()
            return
        }

        feed.lastRefreshAttempt = Date()

        do {
            // If local items were removed, force a complete response so a previous 304
            // doesn't leave the feed permanently empty.
            let hasLocalItems = !feed.items.isEmpty
            let result = try await httpClient.fetchFeed(
                from: feedURL,
                etag: hasLocalItems ? feed.etag : nil,
                lastModified: hasLocalItems ? feed.lastModified : nil
            )

            switch result {
            case .notModified:
                feed.lastSuccessfulRefresh = Date()
                feed.refreshError = nil
                try context.save()

            case .success(let data, let newEtag, let newLastModified, let responseURL):
                let parser = FeedParser()
                let parsedFeed = try parser.parse(data: data)

                // Update Feed metadata
                if !parsedFeed.title.isEmpty {
                    feed.title = parsedFeed.title
                }
                if let siteURL = parsedFeed.siteURL, !siteURL.isEmpty {
                    feed.siteURL = siteURL
                }
                if let feedDescription = parsedFeed.feedDescription, !feedDescription.isEmpty {
                    feed.feedDescription = feedDescription
                }
                if let icon = parsedFeed.iconURL, !icon.isEmpty {
                    feed.iconURL = icon
                }
                if responseURL.absoluteString != feed.url {
                    feed.url = responseURL.absoluteString
                }

                feed.etag = newEtag ?? feed.etag
                feed.lastModified = newLastModified ?? feed.lastModified
                feed.lastSuccessfulRefresh = Date()
                feed.refreshError = nil

                // Deduplicate and insert items
                let newlyInserted = merge(parsedItems: parsedFeed.items, into: feed, context: context)
                try context.save()

                let faviconURL = FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)
                if let faviconURL {
                    Task { @MainActor in
                        _ = await FaviconManager.shared.fetchFavicon(for: faviconURL)
                    }
                }

                // Post notifications only for new articles that qualify for Smart Feed quality
                let qualifyingArticles = newlyInserted.filter { SmartFeedFilter.qualifiesForSmartFeedNotification($0) }
                for newArticle in qualifyingArticles.prefix(5) {
                    NotificationManager.shared.sendArticleNotification(
                        articleTitle: newArticle.title,
                        feedTitle: feed.title,
                        articleID: newArticle.id,
                        feedID: feed.id,
                        faviconURL: faviconURL
                    )
                }
            }

            if updateWidgetAndBadge {
                await MainActor.run {
                    ArticleEnrichmentQueue.shared.scheduleRecentItems(in: modelContainer)
                }
            }

            // Update Widget snapshot and notify WidgetKit only if requested (e.g. single feed refresh from UI)
            if updateWidgetAndBadge {
                await WidgetSnapshotManager.shared.updateSnapshot(context: context)
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                refreshBadge(context: context)
            }

        } catch {
            feed.refreshError = error.localizedDescription
            try context.save()
            throw error
        }
    }

    /// Refresh all enabled feeds with bounded concurrency (max 4 concurrent requests)
    public func refreshAllFeeds() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.enabled })
        let feedIDs: [UUID]
        do {
            feedIDs = try context.fetch(descriptor).map { $0.id }
        } catch {
            print("Failed to fetch feeds for refreshAllFeeds: \(error)")
            return
        }

        let maxConcurrent = 4
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0
            for feedID in feedIDs {
                if activeCount >= maxConcurrent {
                    await group.next()
                    activeCount -= 1
                }
                activeCount += 1
                group.addTask {
                    do {
                        try await self.refreshFeed(id: feedID, updateWidgetAndBadge: false)
                    } catch {
                        print("Feed refresh failed for \(feedID): \(error)")
                    }
                }
            }
        }

        await MainActor.run {
            ArticleEnrichmentQueue.shared.scheduleRecentItems(in: modelContainer)
        }

        // Final snapshot update after all feeds finish refreshing
        await WidgetSnapshotManager.shared.updateSnapshot(context: context)
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
        refreshBadge(context: context)

        // Automatically prune expired articles according to user retention setting (default 30 days)
        let retentionDays = UserDefaults.standard.integer(forKey: "articleRetentionDays")
        let effectiveRetention = retentionDays > 0 ? retentionDays : 30
        _ = try? await pruningService.prune(readRetentionDays: effectiveRetention)
    }

    /// Recomputes the total unread count and updates the app icon / dock badge.
    private func refreshBadge(context: ModelContext) {
        let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { !$0.isRead })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        NotificationManager.shared.updateBadgeCount(count)
    }

    /// Merge parsed items into existing feed using deduplication logic
    /// Returns array of newly inserted FeedItem instances
    private func merge(parsedItems: [ParsedItem], into feed: Feed, context: ModelContext) -> [FeedItem] {
        let existingItems = feed.items
        
        let existingGuids = Set(existingItems.compactMap { $0.guid?.trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingLinks = Set(existingItems.compactMap { $0.link?.trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingFallbackKeys = Set(existingItems.map { item in
            "\(item.title):\(item.publicationDate.timeIntervalSince1970)"
        })

        var newlyInserted: [FeedItem] = []

        for parsed in parsedItems {
            let cleanGuid = parsed.guid?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanLink = parsed.link?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackKey = "\(parsed.title):\(parsed.publicationDate.timeIntervalSince1970)"

            var isDuplicate = false
            if let guid = cleanGuid, !guid.isEmpty, existingGuids.contains(guid) {
                isDuplicate = true
            } else if let link = cleanLink, !link.isEmpty, existingLinks.contains(link) {
                isDuplicate = true
            } else if existingFallbackKeys.contains(fallbackKey) {
                isDuplicate = true
            }

            if !isDuplicate {
                let newItem = FeedItem(
                    guid: cleanGuid,
                    title: parsed.title,
                    link: cleanLink,
                    author: parsed.author,
                    summary: parsed.summary,
                    content: parsed.content,
                    imageURL: parsed.imageURL,
                    publicationDate: parsed.publicationDate,
                    discoveredDate: Date(),
                    isRead: false,
                    isStarred: false,
                    feed: feed
                )
                context.insert(newItem)
                newlyInserted.append(newItem)
            }
        }
        return newlyInserted
    }
}
