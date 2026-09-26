import XCTest
import SwiftData
@testable import Sift

final class ArticleFilterConfigTests: XCTestCase {

    func testFilterMatchesUnreadAndStarred() {
        var config = ArticleFilterConfig.defaultConfig
        config.includeUnread = true
        config.includeStarred = false

        let feed = Feed(title: "Test", url: "https://example.com/rss")
        let unreadItem = FeedItem(title: "Unread", feed: feed)
        unreadItem.isRead = false
        unreadItem.isStarred = false

        let readItem = FeedItem(title: "Read", feed: feed)
        readItem.isRead = true
        readItem.isStarred = false

        let readStarredItem = FeedItem(title: "Read Starred", feed: feed)
        readStarredItem.isRead = true
        readStarredItem.isStarred = true

        // With includeUnread = true, includeStarred = false
        XCTAssertTrue(config.matches(unreadItem, vipFeedIDs: []))
        XCTAssertFalse(config.matches(readItem, vipFeedIDs: []))
        XCTAssertFalse(config.matches(readStarredItem, vipFeedIDs: []))

        // With includeStarred = true
        config.includeStarred = true
        XCTAssertTrue(config.matches(unreadItem, vipFeedIDs: []))
        XCTAssertFalse(config.matches(readItem, vipFeedIDs: []))
        XCTAssertTrue(config.matches(readStarredItem, vipFeedIDs: []))
    }

    func testFilterMatchesOnlyWithMedia() {
        var config = ArticleFilterConfig.defaultConfig
        config.onlyWithMedia = true

        let feed = Feed(title: "Test", url: "https://example.com/rss")

        let itemWithImage = FeedItem(title: "Media", feed: feed)
        itemWithImage.imageURL = "https://example.com/photo.jpg"

        let itemWithoutImage = FeedItem(title: "No Media", feed: feed)
        itemWithoutImage.imageURL = nil

        let itemWithEmptyImage = FeedItem(title: "Empty Media", feed: feed)
        itemWithEmptyImage.imageURL = "   "

        XCTAssertTrue(config.matches(itemWithImage, vipFeedIDs: []))
        XCTAssertFalse(config.matches(itemWithoutImage, vipFeedIDs: []))
        XCTAssertFalse(config.matches(itemWithEmptyImage, vipFeedIDs: []))
    }

    func testFilterExcludesFeeds() {
        var config = ArticleFilterConfig.defaultConfig
        let feed1 = Feed(title: "Feed 1", url: "https://example.com/1")
        let feed2 = Feed(title: "Feed 2", url: "https://example.com/2")

        config.excludedFeedIDs = [feed1.id]

        let item1 = FeedItem(title: "Item 1", feed: feed1)
        let item2 = FeedItem(title: "Item 2", feed: feed2)

        XCTAssertFalse(config.matches(item1, vipFeedIDs: []))
        XCTAssertTrue(config.matches(item2, vipFeedIDs: []))
    }

    func testFilterVIPFeeds() {
        var config = ArticleFilterConfig.defaultConfig
        config.onlyVIPFeeds = true

        let vipFeed = Feed(title: "VIP", url: "https://example.com/vip")
        let regularFeed = Feed(title: "Regular", url: "https://example.com/regular")

        let vipItem = FeedItem(title: "VIP Item", feed: vipFeed)
        let regularItem = FeedItem(title: "Regular Item", feed: regularFeed)

        let vipSet: Set<UUID> = [vipFeed.id]

        XCTAssertTrue(config.matches(vipItem, vipFeedIDs: vipSet))
        XCTAssertFalse(config.matches(regularItem, vipFeedIDs: vipSet))
    }
}
