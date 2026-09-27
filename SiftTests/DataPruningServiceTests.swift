import XCTest
import SwiftData
@testable import Sift

final class DataPruningServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var pruningService: DataPruningService!

    override func setUpWithError() throws {
        let schema = Schema([Feed.self, FeedItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        pruningService = DataPruningService(modelContainer: modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        pruningService = nil
    }

    func testPruneDeletesOldReadUnstarredArticles() async throws {
        let context = ModelContext(modelContainer)
        let feed = Feed(title: "Test Feed", url: "https://example.com/rss")
        context.insert(feed)

        let calendar = Calendar.current
        let fortyDaysAgo = calendar.date(byAdding: .day, value: -40, to: Date())!
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: Date())!

        // 1. Old read, unstarred -> Should be deleted
        let oldReadItem = FeedItem(guid: "old-read", title: "Old Read", feed: feed)
        oldReadItem.isRead = true
        oldReadItem.isStarred = false
        oldReadItem.publicationDate = fortyDaysAgo
        context.insert(oldReadItem)

        // 2. Recent read, unstarred -> Should be kept
        let recentReadItem = FeedItem(guid: "recent-read", title: "Recent Read", feed: feed)
        recentReadItem.isRead = true
        recentReadItem.isStarred = false
        recentReadItem.publicationDate = tenDaysAgo
        context.insert(recentReadItem)

        // 3. Old read BUT starred -> Must be kept forever!
        let oldStarredItem = FeedItem(guid: "old-starred", title: "Old Starred", feed: feed)
        oldStarredItem.isRead = true
        oldStarredItem.isStarred = true
        oldStarredItem.publicationDate = fortyDaysAgo
        context.insert(oldStarredItem)

        // 4. Old unread, unstarred (recent enough) -> Kept
        let unreadItem = FeedItem(guid: "unread", title: "Unread", feed: feed)
        unreadItem.isRead = false
        unreadItem.isStarred = false
        unreadItem.publicationDate = fortyDaysAgo
        context.insert(unreadItem)

        try context.save()

        let result = try await pruningService.prune(readRetentionDays: 30, unreadCutoffDays: 180)
        XCTAssertEqual(result.readPrunedCount, 1)

        let remaining = try context.fetch(FetchDescriptor<FeedItem>())
        XCTAssertEqual(remaining.count, 3)

        let remainingGuids = Set(remaining.compactMap(\.guid))
        XCTAssertFalse(remainingGuids.contains("old-read"), "Old read item should be pruned")
        XCTAssertTrue(remainingGuids.contains("recent-read"), "Recent read item should be kept")
        XCTAssertTrue(remainingGuids.contains("old-starred"), "Starred item must be preserved")
        XCTAssertTrue(remainingGuids.contains("unread"), "Unread item within cutoff must be preserved")
    }

    func testPruneWithRetentionDisabledKeepsAll() async throws {
        let context = ModelContext(modelContainer)
        let feed = Feed(title: "Test Feed", url: "https://example.com/rss")
        context.insert(feed)

        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        let oldItem = FeedItem(guid: "ancient", title: "Ancient", feed: feed)
        oldItem.isRead = true
        oldItem.isStarred = false
        oldItem.publicationDate = oneYearAgo
        context.insert(oldItem)
        try context.save()

        // 0 days = retention disabled ("Keep All")
        let result = try await pruningService.prune(readRetentionDays: 0, unreadCutoffDays: 0)
        XCTAssertEqual(result.totalPruned, 0)

        let remaining = try context.fetch(FetchDescriptor<FeedItem>())
        XCTAssertEqual(remaining.count, 1)
    }
}
