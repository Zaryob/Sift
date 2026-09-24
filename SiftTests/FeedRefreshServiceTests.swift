import XCTest
import SwiftData
@testable import Sift

final class MockFeedHTTPClient: FeedHTTPClientProtocol {
    var resultToReturn: Result<FeedFetchResult, Error>?
    var lastRequestedETag: String?
    var lastRequestedLastModified: String?

    func fetchFeed(
        from url: URL,
        etag: String?,
        lastModified: String?
    ) async throws -> FeedFetchResult {
        self.lastRequestedETag = etag
        self.lastRequestedLastModified = lastModified

        if let result = resultToReturn {
            switch result {
            case .success(let fetchResult):
                return fetchResult
            case .failure(let error):
                throw error
            }
        }
        throw URLError(.badURL)
    }
}

final class FeedRefreshServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var mockHTTPClient: MockFeedHTTPClient!

    override func setUpWithError() throws {
        let schema = Schema([Feed.self, FeedItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        mockHTTPClient = MockFeedHTTPClient()
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        mockHTTPClient = nil
    }

    func testETagAndLastModifiedSentAndSaved() async throws {
        let feed = Feed(title: "Test Feed", url: "https://example.com/feed.xml", etag: "\"v1\"", lastModified: "Mon, 23 Sep 2026 10:00:00 GMT")
        let context = ModelContext(modelContainer)
        context.insert(feed)
        try context.save()

        let xmlData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Updated Title</title>
                <item>
                    <title>Item 1</title>
                    <guid>guid-1</guid>
                </item>
            </channel>
        </rss>
        """.data(using: .utf8)!

        mockHTTPClient.resultToReturn = .success(.success(
            data: xmlData,
            etag: "\"v2\"",
            lastModified: "Mon, 23 Sep 2026 12:00:00 GMT",
            responseURL: URL(string: "https://example.com/feed.xml")!
        ))

        let refreshService = FeedRefreshService(httpClient: mockHTTPClient, modelContainer: modelContainer)
        try await refreshService.refreshFeed(id: feed.id)

        XCTAssertEqual(mockHTTPClient.lastRequestedETag, "\"v1\"")
        XCTAssertEqual(mockHTTPClient.lastRequestedLastModified, "Mon, 23 Sep 2026 10:00:00 GMT")

        let updatedFeed = try context.fetch(FetchDescriptor<Feed>()).first!
        XCTAssertEqual(updatedFeed.etag, "\"v2\"")
        XCTAssertEqual(updatedFeed.lastModified, "Mon, 23 Sep 2026 12:00:00 GMT")
        XCTAssertEqual(updatedFeed.items.count, 1)
    }

    func testHTTP304NotModified() async throws {
        let feed = Feed(title: "Unchanged Feed", url: "https://example.com/feed.xml", etag: "\"v1\"")
        let context = ModelContext(modelContainer)
        context.insert(feed)
        try context.save()

        mockHTTPClient.resultToReturn = .success(.notModified)

        let refreshService = FeedRefreshService(httpClient: mockHTTPClient, modelContainer: modelContainer)
        try await refreshService.refreshFeed(id: feed.id)

        let updatedFeed = try context.fetch(FetchDescriptor<Feed>()).first!
        XCTAssertNotNil(updatedFeed.lastSuccessfulRefresh)
        XCTAssertNil(updatedFeed.refreshError)
        XCTAssertEqual(updatedFeed.items.count, 0)
    }

    func testDeduplicationByGUIDAndLink() async throws {
        let feed = Feed(title: "Dedup Feed", url: "https://example.com/feed.xml")
        let context = ModelContext(modelContainer)
        context.insert(feed)
        
        let existingItem = FeedItem(guid: "guid-1", title: "Existing Title", link: "https://example.com/1", feed: feed)
        context.insert(existingItem)
        try context.save()

        let xmlData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Dedup Feed</title>
                <item>
                    <title>Existing Title</title>
                    <guid>guid-1</guid>
                    <link>https://example.com/1</link>
                </item>
                <item>
                    <title>New Title</title>
                    <guid>guid-2</guid>
                    <link>https://example.com/2</link>
                </item>
            </channel>
        </rss>
        """.data(using: .utf8)!

        mockHTTPClient.resultToReturn = .success(.success(
            data: xmlData,
            etag: nil,
            lastModified: nil,
            responseURL: URL(string: "https://example.com/feed.xml")!
        ))

        let refreshService = FeedRefreshService(httpClient: mockHTTPClient, modelContainer: modelContainer)
        try await refreshService.refreshFeed(id: feed.id)

        let items = try context.fetch(FetchDescriptor<FeedItem>())
        XCTAssertEqual(items.count, 2)
        let guids = Set(items.compactMap { $0.guid })
        XCTAssertTrue(guids.contains("guid-1"))
        XCTAssertTrue(guids.contains("guid-2"))
    }

    func testFailureIsolation() async throws {
        let feed1 = Feed(title: "Failing Feed", url: "https://example.com/bad.xml")
        let feed2 = Feed(title: "Good Feed", url: "https://example.com/good.xml")
        let context = ModelContext(modelContainer)
        context.insert(feed1)
        context.insert(feed2)
        try context.save()

        let refreshService = FeedRefreshService(httpClient: mockHTTPClient, modelContainer: modelContainer)

        // Mock will throw URLError for bad URL by default
        await refreshService.refreshAllFeeds()

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        XCTAssertEqual(feeds.count, 2)
    }
}
