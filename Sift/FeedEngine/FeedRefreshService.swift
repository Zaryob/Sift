import Foundation
import SwiftData
import WidgetKit

public actor FeedRefreshService {
    private let httpClient: FeedHTTPClientProtocol
    private let modelContainer: ModelContainer
    private var refreshingFeedIDs: Set<UUID> = []

    public init(
        httpClient: FeedHTTPClientProtocol = FeedHTTPClient(),
        modelContainer: ModelContainer? = nil
    ) {
        self.httpClient = httpClient
        self.modelContainer = modelContainer ?? PersistenceController.shared.container
    }

    /// Refresh a single feed by ID
    public func refreshFeed(id feedID: UUID) async throws {
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
            let result = try await httpClient.fetchFeed(
                from: feedURL,
                etag: feed.etag,
                lastModified: feed.lastModified
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
                if let desc = parsedFeed.feedDescription, !desc.isEmpty {
                    feed.feedDescription = desc
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
                let (newCount, latestTitle, latestID) = merge(parsedItems: parsedFeed.items, into: feed, context: context)
                try context.save()

                let faviconURL = FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)

                if newCount > 0, let title = latestTitle {
                    NotificationManager.shared.sendNewArticlesNotification(
                        count: newCount,
                        feedTitle: feed.title,
                        latestArticleTitle: title,
                        faviconURL: faviconURL,
                        articleID: latestID,
                        feedID: feed.id
                    )
                }

                // Update Widget snapshot and notify WidgetKit
                WidgetSnapshotManager.shared.updateSnapshot(context: context)
                WidgetCenter.shared.reloadAllTimelines()
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
                        try await self.refreshFeed(id: feedID)
                    } catch {
                        print("Feed refresh failed for \(feedID): \(error)")
                    }
                }
            }
        }
    }

    /// Merge parsed items into existing feed using deduplication logic
    /// Returns (insertedCount, latestInsertedArticleTitle, latestInsertedArticleID)
    private func merge(parsedItems: [ParsedItem], into feed: Feed, context: ModelContext) -> (Int, String?, UUID?) {
        let existingItems = feed.items
        
        let existingGuids = Set(existingItems.compactMap { $0.guid?.trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingLinks = Set(existingItems.compactMap { $0.link?.trimmingCharacters(in: .whitespacesAndNewlines) })
        let existingFallbackKeys = Set(existingItems.map { item in
            "\(item.title):\(item.publicationDate.timeIntervalSince1970)"
        })

        var newCount = 0
        var latestTitle: String?
        var latestID: UUID?

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
                    publicationDate: parsed.publicationDate,
                    discoveredDate: Date(),
                    isRead: false,
                    isStarred: false,
                    feed: feed
                )
                context.insert(newItem)
                newCount += 1
                if latestTitle == nil {
                    latestTitle = parsed.title
                    latestID = newItem.id
                }
            }
        }
        return (newCount, latestTitle, latestID)
    }
}
