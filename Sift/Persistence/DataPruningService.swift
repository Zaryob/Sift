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
    ///   - unreadCutoffDays: Days after which unread, unstarred articles from inactive feeds are purged (default 180 days). Pass 0 to disable.
    /// - Returns: A `PruningResult` with counts of deleted articles.
    @discardableResult
    public func prune(readRetentionDays: Int = 30, unreadCutoffDays: Int = 180) async throws -> PruningResult {
        let context = ModelContext(modelContainer)
        let calendar = Calendar.current
        let now = Date()

        var readDeleted = 0
        var unreadDeleted = 0

        // 1. Prune read, unstarred articles older than readRetentionDays
        if readRetentionDays > 0, let readCutoff = calendar.date(byAdding: .day, value: -readRetentionDays, to: now) {
            let descriptor = FetchDescriptor<FeedItem>(
                predicate: #Predicate<FeedItem> { item in
                    item.isRead && !item.isStarred && item.publicationDate < readCutoff
                }
            )
            if let itemsToPrune = try? context.fetch(descriptor), !itemsToPrune.isEmpty {
                readDeleted = itemsToPrune.count
                for item in itemsToPrune {
                    context.delete(item)
                }
            }
        }

        // 2. Prune ancient unread, unstarred articles older than unreadCutoffDays (safeguard against dead feeds)
        if unreadCutoffDays > 0, let unreadCutoff = calendar.date(byAdding: .day, value: -unreadCutoffDays, to: now) {
            let descriptor = FetchDescriptor<FeedItem>(
                predicate: #Predicate<FeedItem> { item in
                    !item.isRead && !item.isStarred && item.publicationDate < unreadCutoff
                }
            )
            if let itemsToPrune = try? context.fetch(descriptor), !itemsToPrune.isEmpty {
                unreadDeleted = itemsToPrune.count
                for item in itemsToPrune {
                    context.delete(item)
                }
            }
        }

        if readDeleted > 0 || unreadDeleted > 0 {
            try context.save()
            print("[DataPruningService] Pruned \(readDeleted) read articles and \(unreadDeleted) stale unread articles.")
        }

        return PruningResult(readPrunedCount: readDeleted, unreadPrunedCount: unreadDeleted)
    }
}
