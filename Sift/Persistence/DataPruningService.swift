import Foundation
import SwiftData

/// Represents the summary result of a data pruning operation.
nonisolated public struct PruningResult: Equatable, Sendable {
    public let readPrunedCount: Int
    public let unreadPrunedCount: Int
    public var totalPruned: Int { readPrunedCount + unreadPrunedCount }

    public init(readPrunedCount: Int = 0, unreadPrunedCount: Int = 0) {
        self.readPrunedCount = readPrunedCount
        self.unreadPrunedCount = unreadPrunedCount
    }
}

/// Service responsible for enforcing the database retention policy in Sift.
/// Prevents SQLite and memory bloat by deleting old read articles while strictly preserving starred articles.
public actor DataPruningService {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer? = nil) {
        self.modelContainer = modelContainer ?? PersistenceController.shared.container
    }

    /// Prunes expired articles according to retention settings.
    ///
    /// - Parameters:
    ///   - readRetentionDays: Days after which read, unstarred articles are purged. Pass 0 or negative to keep indefinitely.
    ///   - unreadCutoffDays: Days after which unread, unstarred articles are purged. Disabled by default to preserve feed archives.
    /// - Returns: A `PruningResult` with counts of deleted articles.
    @discardableResult
    public func prune(readRetentionDays: Int = 30, unreadCutoffDays: Int = 0) async throws -> PruningResult {
        let context = ModelContext(modelContainer)
        let calendar = Calendar.current
        let now = Date()

        var readDeleted = 0
        var unreadDeleted = 0

        // 1. Prune read, unstarred articles older than readRetentionDays
        if readRetentionDays > 0, let readCutoff = calendar.date(byAdding: .day, value: -readRetentionDays, to: now) {
            let predicate = #Predicate<FeedItem> { item in
                item.isRead && !item.isStarred && item.publicationDate < readCutoff
            }
            let expiredItems = try context.fetch(FetchDescriptor<FeedItem>(predicate: predicate))
            readDeleted = expiredItems.count
            for item in expiredItems {
                context.delete(item)
            }
        }

        // 2. Prune ancient unread, unstarred articles older than unreadCutoffDays (safeguard against dead feeds)
        if unreadCutoffDays > 0, let unreadCutoff = calendar.date(byAdding: .day, value: -unreadCutoffDays, to: now) {
            let predicate = #Predicate<FeedItem> { item in
                !item.isRead && !item.isStarred && item.publicationDate < unreadCutoff
            }
            let expiredItems = try context.fetch(FetchDescriptor<FeedItem>(predicate: predicate))
            unreadDeleted = expiredItems.count
            for item in expiredItems {
                context.delete(item)
            }
        }

        if readDeleted > 0 || unreadDeleted > 0 {
            try context.save()
            print("[DataPruningService] Pruned \(readDeleted) read articles and \(unreadDeleted) stale unread articles.")
        }

        return PruningResult(readPrunedCount: readDeleted, unreadPrunedCount: unreadDeleted)
    }

    private static let legacyNoiseSweepKey = "hasPerformedLegacyPromotionalNoiseSweep"

    /// One-time sweep that removes promotional/sponsored articles stored before
    /// this cleanup existed. New articles are already filtered out at ingestion
    /// (see `FeedRefreshService.merge`), so this never needs to scan the whole
    /// library again once it has run.
    @discardableResult
    public func pruneLegacyPromotionalNoiseIfNeeded() async throws -> Int {
        guard !UserDefaults.standard.bool(forKey: Self.legacyNoiseSweepKey) else { return 0 }

        let context = ModelContext(modelContainer)
        let vipFeedIDs = SmartFeedFilter.loadStoredVIPFeedIDs()

        let predicate = #Predicate<FeedItem> { !$0.isStarred }
        let candidates = try context.fetch(FetchDescriptor<FeedItem>(predicate: predicate))

        var deleted = 0
        for item in candidates {
            if let feedID = item.feed?.id, vipFeedIDs.contains(feedID) { continue }
            guard SmartFeedFilter.isHighConfidenceNoise(item.title) else { continue }
            context.delete(item)
            deleted += 1
        }

        if deleted > 0 {
            try context.save()
            PromotionalCleanupStats.recordCleaned(deleted)
            print("[DataPruningService] Removed \(deleted) legacy promotional/sponsored articles.")
        }

        UserDefaults.standard.set(true, forKey: Self.legacyNoiseSweepKey)
        return deleted
    }
}
