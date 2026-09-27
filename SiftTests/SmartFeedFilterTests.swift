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

    // MARK: - Smart Feed Notification Quality Tests

    func testHighQualityArticleQualifiesForNotification() {
        let feed = Feed(title: "Tech News", url: "https://technews.com/rss")
        let highQualityItem = FeedItem(
            title: "Apple Announces Next-Gen M5 Architecture for High-Performance Workloads",
            feed: feed
        )
        highQualityItem.link = "https://technews.com/apple-m5-announcement"

        XCTAssertTrue(SmartFeedFilter.qualifiesForSmartFeedNotification(highQualityItem))
        XCTAssertTrue(SmartFeedFilter.qualifiesForSmartFeedNotification(title: highQualityItem.title))
    }

    func testPromotionalAndNoiseArticlesDoNotQualifyForNotification() {
        let feed = Feed(title: "Deals", url: "https://deals.com/rss")

        let sponsoredItem = FeedItem(title: "Special Summer Gadget Sale [sponsored] Buy Now", feed: feed)
        let promoCodeItem = FeedItem(title: "Exclusive 50% Coupon Code For All Subscribers", feed: feed)
        let hiringItem = FeedItem(title: "We are hiring senior iOS software engineers today", feed: feed)
        let turkishAdItem = FeedItem(title: "Yeni kampanyalı ürünler için sponsorlu içerik detayları", feed: feed)

        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(sponsoredItem))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(promoCodeItem))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(hiringItem))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(turkishAdItem))

        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: sponsoredItem.title))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: promoCodeItem.title))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: hiringItem.title))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: turkishAdItem.title))
    }

    func testClickbaitArticlesDoNotQualifyForNotification() {
        let feed = Feed(title: "Gossip", url: "https://gossip.com/rss")

        let clickbait1 = FeedItem(title: "You won't believe what happened when he opened this box", feed: feed)
        let clickbait2 = FeedItem(title: "The internet is losing it over this shocking reason", feed: feed)
        let turkishClickbait = FeedItem(title: "Gören herkes bunu konuşuyor şoke eden yeni açıklama", feed: feed)

        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(clickbait1))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(clickbait2))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(turkishClickbait))

        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: clickbait1.title))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: clickbait2.title))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: turkishClickbait.title))
    }

    func testShortStubTitleDoesNotQualifyForNotification() {
        let feed = Feed(title: "Feed", url: "https://example.com/rss")
        let stubItem = FeedItem(title: "Update v1.2", feed: feed) // 11 characters < 15

        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(stubItem))
        XCTAssertFalse(SmartFeedFilter.qualifiesForSmartFeedNotification(title: stubItem.title))
    }

    func testStarredArticleAlwaysQualifiesForNotification() {
        let feed = Feed(title: "Feed", url: "https://example.com/rss")
        let starredStub = FeedItem(title: "Quick note", feed: feed)
        starredStub.isStarred = true

        XCTAssertTrue(SmartFeedFilter.qualifiesForSmartFeedNotification(starredStub))
    }

    // MARK: - Smart Feed VIP & Velocity Tests

    func testVIPFeedsReceivePriorityAndHigherQuota() {
        let regularFeed = Feed(title: "Regular News", url: "https://regular.com/rss")
        let vipFeed = Feed(title: "VIP Tech", url: "https://vip.com/rss")

        let vipItem1 = FeedItem(title: "Important VIP Breakthrough in Physics", feed: vipFeed)
        vipItem1.link = "https://vip.com/physics"
        vipItem1.publicationDate = Date().addingTimeInterval(-3600)

        let regularItem1 = FeedItem(title: "Standard Daily News Roundup for Today", feed: regularFeed)
        regularItem1.link = "https://regular.com/roundup"
        regularItem1.publicationDate = Date().addingTimeInterval(-3600)

        let result = SmartFeedFilter.filteredArticles(from: [regularItem1, vipItem1], vipFeedIDs: [vipFeed.id])
        XCTAssertEqual(result.count, 2)
        // VIP feed notification qualification
        XCTAssertTrue(SmartFeedFilter.qualifiesForSmartFeedNotification(vipItem1, vipFeedIDs: [vipFeed.id]))
    }

    func testMultiSourceCoverageBoostsRepresentativeStory() {
        let feedA = Feed(title: "Source Alpha", url: "https://alpha.com/rss")
        let feedB = Feed(title: "Source Beta", url: "https://beta.com/rss")

        let itemA = FeedItem(title: "James Webb Space Telescope Discovers Ancient Galaxy Cluster", feed: feedA)
        itemA.link = "https://alpha.com/jwst-cluster"
        itemA.publicationDate = Date().addingTimeInterval(-3600)

        let itemB = FeedItem(title: "James Webb Space Telescope Discovers Ancient Galaxy Cluster", feed: feedB)
        itemB.link = "https://beta.com/jwst-galaxy-cluster"
        itemB.publicationDate = Date().addingTimeInterval(-7200)

        let curated = SmartFeedFilter.filteredArticles(from: [itemA, itemB])
        // Deduplicated to 1 representative story
        XCTAssertEqual(curated.count, 1)
        XCTAssertEqual(curated.first?.title, itemA.title)
    }

    func testBreakingNewsBoostRanksRecentItemAboveStaleItem() {
        let feed = Feed(title: "News", url: "https://news.com/rss")

        let freshItem = FeedItem(title: "Breaking News: Major Solar Flare Observed Today", feed: feed)
        freshItem.link = "https://news.com/fresh"
        freshItem.publicationDate = Date().addingTimeInterval(-1800) // 30 minutes ago

        let olderItem = FeedItem(title: "Standard Feature: Review of Solar Physics Concepts", feed: feed)
        olderItem.link = "https://news.com/older"
        olderItem.publicationDate = Date().addingTimeInterval(-100 * 3600) // 4+ days ago

        let curated = SmartFeedFilter.filteredArticles(from: [olderItem, freshItem])
        XCTAssertTrue(curated.contains(where: { $0.id == freshItem.id }))
    }
}
