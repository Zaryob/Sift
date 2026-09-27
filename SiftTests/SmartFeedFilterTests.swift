import XCTest
@testable import Sift

final class SmartFeedFilterTests: XCTestCase {

    func testEmptyListReturnsEmpty() {
        let result = SmartFeedFilter.filteredArticles(from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testHighConfidenceNoiseIsFiltered() {
        let feed = Feed(title: "Tech News", url: "https://example.com/rss")
        let sponsored = FeedItem(title: "Best deals [sponsored] you must check out", feed: feed)
        let normal = FeedItem(title: "Swift 6.1 Released With Major Improvements", feed: feed)

        let result = SmartFeedFilter.filteredArticles(from: [sponsored, normal])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, normal.id)
    }

    func testStarredNoiseIsRetainedDueToExplicitUserIntent() {
        let feed = Feed(title: "Tech News", url: "https://example.com/rss")
        let sponsored = FeedItem(title: "Best deals [sponsored] you must check out", feed: feed)
        sponsored.isStarred = true

        let result = SmartFeedFilter.filteredArticles(from: [sponsored])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, sponsored.id)
    }

    func testExactAndNearDuplicateArticlesAreDeduplicated() {
        let feedA = Feed(title: "Feed A", url: "https://example.com/a")
        let feedB = Feed(title: "Feed B", url: "https://example.com/b")

        let itemA = FeedItem(title: "Apple Announces New M5 MacBook Pro Models", feed: feedA)
        itemA.link = "https://example.com/apple-m5?utm_source=twitter"

        let itemB = FeedItem(title: "Apple Announces New M5 MacBook Pro Models", feed: feedB)
        itemB.link = "https://example.com/apple-m5?utm_source=rss"

        let result = SmartFeedFilter.filteredArticles(from: [itemA, itemB])
        XCTAssertEqual(result.count, 1)
    }

    func testStaleReadArticlesAreFilteredOut() {
        let feed = Feed(title: "Feed", url: "https://example.com/rss")
        let oldRead = FeedItem(title: "Older Read Article That Should Not Clog Smart Feed", feed: feed)
        oldRead.isRead = true
        oldRead.publicationDate = Date().addingTimeInterval(-72 * 3600) // 3 days ago

        let freshUnread = FeedItem(title: "Fresh Unread Breaking News", feed: feed)
        freshUnread.isRead = false
        freshUnread.publicationDate = Date().addingTimeInterval(-2 * 3600)

        let result = SmartFeedFilter.filteredArticles(from: [oldRead, freshUnread])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, freshUnread.id)
    }

    func testScalesBudgetAndDoesNotPassAll976Articles() {
        var feeds: [Feed] = []
        for f in 1...10 {
            feeds.append(Feed(title: "Feed \(f)", url: "https://feed\(f).com/rss"))
        }

        var articles: [FeedItem] = []
        for i in 1...976 {
            let feed = feeds[i % feeds.count]
            let item = FeedItem(title: "Article \(i): Detailed story about topic alpha \(i) vs beta \(i)", feed: feed)
            item.link = "https://feed\((i % feeds.count) + 1).com/article/\(i)"
            item.isRead = (i > 300)
            let hoursAgo = Double(i) * 0.1
            item.publicationDate = Date().addingTimeInterval(-hoursAgo * 3600)
            articles.append(item)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let curated = SmartFeedFilter.filteredArticles(from: articles)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Must run rapidly in milliseconds without freezing UI or causing black screen watchdog kills
        XCTAssertLessThan(elapsedMs, 100.0, "Filter took \(elapsedMs)ms, must be < 100ms")

        // Must NOT pass all 975 articles! Budget should curate to ~74 items
        XCTAssertLessThanOrEqual(curated.count, 75)
        XCTAssertGreaterThanOrEqual(curated.count, 25)
    }

    func testFeedDiversityPreventsSingleSourceDomination() {
        let spammyFeed = Feed(title: "Spammy Feed", url: "https://spam.com/rss")
        let goodFeedA = Feed(title: "Good Feed A", url: "https://gooda.com/rss")
        let goodFeedB = Feed(title: "Good Feed B", url: "https://goodb.com/rss")

        var articles: [FeedItem] = []
        // Spammy feed has 200 items
        for i in 1...200 {
            let item = FeedItem(title: "Spam Feed Post \(i) on minor update \(i)", feed: spammyFeed)
            item.link = "https://spam.com/\(i)"
            item.publicationDate = Date().addingTimeInterval(-Double(i) * 60)
            articles.append(item)
        }

        // Good feeds have 5 fresh items each
        for i in 1...5 {
            let itemA = FeedItem(title: "Important Discovery A \(i) in astrophysics research \(i)", feed: goodFeedA)
            itemA.link = "https://gooda.com/\(i)"
            itemA.publicationDate = Date().addingTimeInterval(-Double(i) * 120)
            articles.append(itemA)

            let itemB = FeedItem(title: "Important Discovery B \(i) in quantum engineering \(i)", feed: goodFeedB)
            itemB.link = "https://goodb.com/\(i)"
            itemB.publicationDate = Date().addingTimeInterval(-Double(i) * 120)
            articles.append(itemB)
        }

        let curated = SmartFeedFilter.filteredArticles(from: articles)
        let goodACount = curated.filter { $0.feed?.id == goodFeedA.id }.count
        let goodBCount = curated.filter { $0.feed?.id == goodFeedB.id }.count

        // Both good feeds should be represented, spam feed must not crowd them out
        XCTAssertGreaterThan(goodACount, 0)
        XCTAssertGreaterThan(goodBCount, 0)
    }
}
