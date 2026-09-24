import XCTest
@testable import Sift

final class FeedDiscoveryServiceTests: XCTestCase {

    func testDiscoverFeedFromHTML() async throws {
        let htmlContent = """
        <html>
        <head>
            <title>My Tech Blog</title>
            <link rel="alternate" type="application/rss+xml" title="My RSS Feed" href="https://example.com/feed.xml" />
        </head>
        <body>Hello</body>
        </html>
        """

        let mockData = htmlContent.data(using: .utf8)!
        let mockURL = URL(string: "https://example.com")!
        let mockClient = MockHTTPClient(result: .success(data: mockData, etag: nil, lastModified: nil, responseURL: mockURL))

        let discovery = FeedDiscoveryService(httpClient: mockClient)
        let feeds = try await discovery.discoverFeeds(from: mockURL)

        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds.first?.title, "My RSS Feed")
        XCTAssertEqual(feeds.first?.url.absoluteString, "https://example.com/feed.xml")
    }
}
