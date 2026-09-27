import Foundation
import SwiftUI
import SwiftData
import Observation
import WidgetKit

public enum SidebarItem: Hashable, Identifiable {
    case smart
    case all
    case today
    case unread
    case starred
    case feed(UUID)

    public var id: String {
        switch self {
        case .smart: return "smart"
        case .all: return "all"
        case .today: return "today"
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

public struct StoryPreviewGroup: Identifiable, Sendable {
    public let id: String
    public let articleIDs: [UUID]
    public let publisherCount: Int
}

public struct StoryPreviewCategory: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let storyGroupIDs: [String]
    public let articleIDs: [UUID]
}

/// The preview's shared local-calendar date window, used at both analysis and
/// rendering boundaries so stale preview state cannot reveal older articles.
public struct StoryPreviewDateWindow: Sendable {
    public let lowerBound: Date
    public let upperBound: Date

    public init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let startOfToday = calendar.startOfDay(for: now)
        lowerBound = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            ?? now.addingTimeInterval(-48 * 60 * 60)
        upperBound = now
    }

    public func contains(_ date: Date) -> Bool {
        date >= lowerBound && date <= upperBound
    }

    public var duration: TimeInterval {
        upperBound.timeIntervalSince(lowerBound)
    }
}

public enum StoryPreviewAnalysisState: Equatable, Sendable {
    case completed
    case modelUnavailable
    case noRecentArticles
}

public struct StoryPreviewMetrics: Sendable {
    public let analyzedArticleCount: Int
    public let readyArticleCount: Int
    public let articleBodyCount: Int
    public let enrichedArticleCount: Int
    public let dailyCategoryCount: Int
    public let waitingForTranslationCount: Int
    public let unsupportedLanguageCount: Int
    public let otherFailureCount: Int
    public let analysisState: StoryPreviewAnalysisState
}

private struct StoryPreviewExtractionRequest: Sendable {
    let url: URL
    let itemIDs: [UUID]
    let summary: String?
}

private struct DailyCategoryAccumulator {
    var labelCounts: [String: Int] = [:]
    var storyGroupIDs: Set<String> = []
    var articleIDs: Set<UUID> = []
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
    public var selectedSidebarItem: SidebarItem? = .smart
    public var selectedArticle: FeedItem?
    public var articleOpenRequestID = UUID()
    
    public var isAddingFeed: Bool = false
    public var isShowingSettings: Bool = false
    public var isShowingDailyBriefing: Bool = false

    public var lastRefreshedAt: Date? = Date()
    public var lastMarkedReadArticles: [FeedItem] = []
    public var toastMessage: String?

    public var errorMessage: String?
    public var showErrorAlert: Bool = false
    public var isRefreshing: Bool = false
    public private(set) var isBuildingStoryPreview = false
    public private(set) var storyPreviewProgress: String?
    public private(set) var storyPreviewGroups: [StoryPreviewGroup] = []
    public private(set) var storyPreviewCategories: [StoryPreviewCategory] = []
    public private(set) var storyPreviewUnassignedIDs: [UUID] = []
    public private(set) var storyPreviewMetrics: StoryPreviewMetrics?

    private let refreshService: FeedRefreshService
    private let httpClient: FeedHTTPClientProtocol
    private let discoveryService: FeedDiscoveryService
    private let storyClusteringSpike = StoryClusteringSpike()

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

    public func openArticle(_ article: FeedItem) {
        selectedArticle = article
        articleOpenRequestID = UUID()
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
            Task { await WidgetSnapshotManager.shared.updateSnapshot(context: context) }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            showError(String(localized: "Failed to save read state: \(error.localizedDescription)"))
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
            Task { await WidgetSnapshotManager.shared.updateSnapshot(context: context) }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            showError(String(localized: "Failed to undo mark as read: \(error.localizedDescription)"))
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
        await WidgetSnapshotManager.shared.updateSnapshot(context: context ?? PersistenceController.shared.container.mainContext)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Runs the M0 clustering spike against recent RSS items without saving derived assignments.
    /// Extracted article text is preferred; RSS content and summary remain the fallback inputs.
    public func buildStoryPreview(from feedItems: [FeedItem], context: ModelContext) async {
        guard !isBuildingStoryPreview else { return }
        isBuildingStoryPreview = true
        storyPreviewGroups = []
        storyPreviewCategories = []
        storyPreviewUnassignedIDs = []
        storyPreviewMetrics = nil
        defer {
            isBuildingStoryPreview = false
            storyPreviewProgress = nil
        }

        let dateWindow = StoryPreviewDateWindow()
        let recentItems = feedItems
            .filter { dateWindow.contains($0.publicationDate) }
            .sorted { $0.publicationDate < $1.publicationDate }

        guard !recentItems.isEmpty else {
            storyPreviewGroups = []
            storyPreviewCategories = []
            storyPreviewUnassignedIDs = []
            storyPreviewMetrics = StoryPreviewMetrics(
                analyzedArticleCount: 0,
                readyArticleCount: 0,
                articleBodyCount: 0,
                enrichedArticleCount: 0,
                dailyCategoryCount: 0,
                waitingForTranslationCount: 0,
                unsupportedLanguageCount: 0,
                otherFailureCount: 0,
                analysisState: .noRecentArticles
            )
            return
        }

        if !ArticleEnrichmentQueue.shared.isProcessing {
            await extractMissingStoryPreviewBodies(from: recentItems, context: context)
        }

        let intelligence = ArticleIntelligenceService.shared
        let digestsByArticleID = Dictionary(uniqueKeysWithValues: recentItems.compactMap { item in
            intelligence.currentOnDeviceDigest(for: item).map { (item.id, $0) }
        })

        let bodyCount = recentItems.filter { Self.articleBodyWordCount(for: $0) >= 120 }.count
        let articles = recentItems.map { item in
            let extractedBody = item.extractedArticle?.blocks.map(\.text).joined(separator: "\n")
            let rssContent = item.content.map { HTMLSanitizer.stripTags(from: $0) }
            let summary = item.summary.map { HTMLSanitizer.stripTags(from: $0) }
            let digest = digestsByArticleID[item.id]
            let body = [
                extractedBody.flatMap { $0.split(whereSeparator: \.isWhitespace).count >= 120 ? $0 : nil },
                rssContent.flatMap { $0.split(whereSeparator: \.isWhitespace).count >= 120 ? $0 : nil },
                extractedBody,
                rssContent
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            return StoryClusteringArticle(
                id: item.id,
                title: item.title,
                summary: summary,
                fullText: body,
                digestSummary: digest?.summary,
                keyPoints: digest?.keyPoints ?? [],
                digestLanguageCode: digest?.outputLanguageCode,
                publisherKey: Self.publisherKey(for: item.feed, itemID: item.id),
                publishedAt: item.publicationDate
            )
        }

        let result = await storyClusteringSpike.cluster(
            articles,
            analysisLocale: "en",
            similarityThreshold: 0.82,
            candidateWindow: dateWindow.duration,
            translationStrategy: .lowLatency,
            eventSignaturesEnabled: false
        )

        let readyAssignments = result.assignments.filter {
            $0.readiness == .ready && $0.predictedClusterID != nil
        }
        let assignmentGroups = Dictionary(grouping: readyAssignments) { $0.predictedClusterID! }
        let publisherByArticleID = Dictionary(uniqueKeysWithValues: zip(articles.map(\.id), articles.map(\.publisherKey)))
        let dateByArticleID = Dictionary(uniqueKeysWithValues: recentItems.map { ($0.id, $0.publicationDate) })
        storyPreviewGroups = assignmentGroups.map { clusterID, assignments in
            let sortedAssignments = assignments.sorted { lhs, rhs in
                let leftDate = dateByArticleID[lhs.id] ?? .distantPast
                let rightDate = dateByArticleID[rhs.id] ?? .distantPast
                return leftDate > rightDate
            }
            let publishers = Set(sortedAssignments.compactMap { publisherByArticleID[$0.id] })
            return StoryPreviewGroup(
                id: clusterID,
                articleIDs: sortedAssignments.map(\.id),
                publisherCount: publishers.count
            )
        }
        .filter { group in
            // A story is useful only when it combines independent coverage.
            // Single-article or single-publisher clusters remain in the regular list.
            group.articleIDs.count >= 2 && group.publisherCount >= 2
        }
        .sorted { lhs, rhs in
            let leftDate = lhs.articleIDs.first.flatMap { dateByArticleID[$0] } ?? .distantPast
            let rightDate = rhs.articleIDs.first.flatMap { dateByArticleID[$0] } ?? .distantPast
            return leftDate > rightDate
        }

        let assignedIDs = Set(storyPreviewGroups.flatMap(\.articleIDs))
        storyPreviewUnassignedIDs = recentItems.map(\.id).filter { !assignedIDs.contains($0) }
        storyPreviewCategories = Self.makeDailyCategories(
            groups: storyPreviewGroups,
            unassignedIDs: storyPreviewUnassignedIDs,
            digestsByArticleID: digestsByArticleID
        )
        storyPreviewMetrics = StoryPreviewMetrics(
            analyzedArticleCount: result.assignments.count,
            readyArticleCount: readyAssignments.count,
            articleBodyCount: bodyCount,
            enrichedArticleCount: digestsByArticleID.count,
            dailyCategoryCount: storyPreviewCategories.count,
            waitingForTranslationCount: result.assignments.filter { $0.readiness == .translationNotInstalled }.count,
            unsupportedLanguageCount: result.assignments.filter { $0.readiness == .unsupportedLanguage }.count,
            otherFailureCount: result.assignments.filter {
                $0.readiness != .ready && $0.readiness != .translationNotInstalled && $0.readiness != .unsupportedLanguage
            }.count,
            analysisState: result.embeddingModelAvailable == false ? .modelUnavailable : .completed
        )
    }

    private static func makeDailyCategories(
        groups: [StoryPreviewGroup],
        unassignedIDs: [UUID],
        digestsByArticleID: [UUID: ArticleIntelligenceResult]
    ) -> [StoryPreviewCategory] {
        var buckets: [String: DailyCategoryAccumulator] = [:]

        func normalizedKey(for label: String) -> String? {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
            guard !trimmed.isEmpty else { return nil }
            let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        func record(_ label: String, groupID: String? = nil, articleID: UUID? = nil) {
            guard let key = normalizedKey(for: label) else { return }
            var bucket = buckets[key, default: DailyCategoryAccumulator()]
            let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
            bucket.labelCounts[displayLabel, default: 0] += 1
            if let groupID { bucket.storyGroupIDs.insert(groupID) }
            if let articleID { bucket.articleIDs.insert(articleID) }
            buckets[key] = bucket
        }

        for group in groups {
            for articleID in group.articleIDs {
                for topic in digestsByArticleID[articleID]?.topics ?? [] {
                    record(topic, groupID: group.id)
                }
            }
        }
        for articleID in unassignedIDs {
            for topic in digestsByArticleID[articleID]?.topics ?? [] {
                record(topic, articleID: articleID)
            }
        }

        return buckets.compactMap { key, bucket in
            guard let title = bucket.labelCounts.max(by: { left, right in
                if left.value == right.value { return left.key > right.key }
                return left.value < right.value
            })?.key else { return nil }
            return StoryPreviewCategory(
                id: key,
                title: title,
                storyGroupIDs: bucket.storyGroupIDs.sorted(),
                articleIDs: bucket.articleIDs.sorted { $0.uuidString < $1.uuidString }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func extractMissingStoryPreviewBodies(from items: [FeedItem], context: ModelContext) async {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let requests = Dictionary(grouping: items.compactMap { item -> (URL, FeedItem)? in
            guard Self.articleBodyWordCount(for: item) < 120,
                  item.extractedArticleData == nil,
                  let link = item.link,
                  let url = URL(string: link),
                  url.scheme == "https" || url.scheme == "http",
                  let host = url.host(), !host.isEmpty else { return nil }
            if let lastAttempt = item.extractionAttemptedAt,
               Date().timeIntervalSince(lastAttempt) < 86_400 {
                return nil
            }
            return (url, item)
        }, by: { $0.0 })
        .map { url, entries in
            StoryPreviewExtractionRequest(
                url: url,
                itemIDs: entries.map { $0.1.id },
                summary: entries.first?.1.summary ?? entries.first?.1.content
            )
        }
        .sorted { $0.url.absoluteString < $1.url.absoluteString }

        guard !requests.isEmpty else { return }
        let requestByURL = Dictionary(uniqueKeysWithValues: requests.map { ($0.url, $0) })
        storyPreviewProgress = String(localized: "Preparing recent coverage…")
        var completedCount = 0
        let maximumConcurrentRequests = 4

        await withTaskGroup(of: (URL, ExtractedArticle?).self) { group in
            var nextRequestIndex = 0
            for _ in 0..<min(maximumConcurrentRequests, requests.count) {
                let request = requests[nextRequestIndex]
                nextRequestIndex += 1
                group.addTask {
                    (request.url, try? await ArticleExtractor.fetch(url: request.url, summary: request.summary))
                }
            }

            while let (url, extractedArticle) = await group.next() {
                completedCount += 1
                storyPreviewProgress = String(localized: "Preparing coverage \(completedCount) of \(requests.count)…")
                let request = requestByURL[url]
                for itemID in request?.itemIDs ?? [] {
                    guard let item = itemByID[itemID] else { continue }
                    item.extractionAttemptedAt = Date()
                    if let extractedArticle,
                       let data = try? JSONEncoder().encode(extractedArticle) {
                        item.extractedArticleData = data
                        if item.imageURL == nil {
                            item.imageURL = extractedArticle.leadImageURL
                        }
                    }
                }
                if nextRequestIndex < requests.count {
                    let nextRequest = requests[nextRequestIndex]
                    nextRequestIndex += 1
                    group.addTask {
                        (nextRequest.url, try? await ArticleExtractor.fetch(url: nextRequest.url, summary: nextRequest.summary))
                    }
                }
            }
        }

        try? context.save()
    }

    private static func articleBodyWordCount(for item: FeedItem) -> Int {
        if let extracted = item.extractedArticle, extracted.wordCount >= 120 {
            return extracted.wordCount
        }
        let rssBody = HTMLSanitizer.stripTags(from: item.content ?? "")
        let rssBodyCount = rssBody.split(whereSeparator: \.isWhitespace).count
        if rssBodyCount >= 120 { return rssBodyCount }
        return item.extractedArticle?.wordCount ?? rssBodyCount
    }

    private static func publisherKey(for feed: Feed?, itemID: UUID) -> String {
        guard let feed,
              let url = URL(string: feed.siteURL ?? feed.url),
              let host = url.host()?.lowercased() else {
            return "unknown-publisher-\(itemID.uuidString)"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
    public func subscribe(to preview: FeedPreview, folder: String?, context: ModelContext) async throws {
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
        ArticleEnrichmentQueue.shared.scheduleRecentItems(in: PersistenceController.shared.container)
        await WidgetSnapshotManager.shared.updateSnapshot(context: context)
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
        do {
            try context.save()
        } catch {
            showError(String(localized: "Failed to update folder: \(error.localizedDescription)"))
        }
    }

    public func deleteFeed(_ feed: Feed, context: ModelContext) {
        if case .feed(let id) = selectedSidebarItem, id == feed.id {
            selectedSidebarItem = .all
        }
        context.delete(feed)
        do {
            try context.save()
            Task { await WidgetSnapshotManager.shared.updateSnapshot(context: context) }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            showError(String(localized: "Failed to delete feed: \(error.localizedDescription)"))
        }
    }

    /// Fetches and caches the article's full text on-demand whenever the article is opened.
    /// If the feed already contains the complete text, no external web request is made.
    @discardableResult
    public func loadFullTextIfNeeded(for article: FeedItem, force: Bool = false, context: ModelContext) async -> String? {
        guard article.extractedArticleData == nil,
              let link = article.link, let url = URL(string: link) else { return nil }

        // If the RSS feed itself already provided an extensive, complete article (>= 400 words),
        // no need to crawl the site unless forced
        if !force, article.feedWordCount >= 400 {
            return nil
        }

        article.extractionAttemptedAt = Date()
        do {
            let result = try await ArticleExtractor.fetch(url: url, summary: article.summary ?? article.content)
            let data = try JSONEncoder().encode(result)
            article.extractedArticleData = data
            article.readingMinutes = result.readingMinutes
            if article.imageURL == nil {
                article.imageURL = result.leadImageURL
            }
            try context.save()
            return nil
        } catch {
            try? context.save()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return nil
            }
            let reason = error.localizedDescription
            print("[ArticleExtractor] Failed to download \(url.absoluteString): \(reason)")
            return reason
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
        do {
            try context.save()
        } catch {
            showError(String(localized: "Failed to save imported feeds: \(error.localizedDescription)"))
            return
        }
        await refreshService.refreshAllFeeds()
        await WidgetSnapshotManager.shared.updateSnapshot(context: context)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
