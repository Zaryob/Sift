import XCTest
@testable import Sift

@MainActor
final class FaviconManagerTests: XCTestCase {

    override func setUp() async throws {
        FaviconManager.shared.clearCache()
    }

    override func tearDown() async throws {
        FaviconManager.shared.clearCache()
    }

    func testFaviconURLGeneration() {
        // Test with explicit icon URL
        let url1 = FaviconFetcher.faviconURL(for: "https://example.com", feedURLString: "https://example.com/rss", iconURLString: "https://example.com/custom-icon.png")
        XCTAssertEqual(url1?.absoluteString, "https://example.com/custom-icon.png")

        // Test with site URL falling back to Google Favicon Service
        let url2 = FaviconFetcher.faviconURL(for: "https://news.ycombinator.com", feedURLString: "https://news.ycombinator.com/rss", iconURLString: nil)
        XCTAssertNotNil(url2)
        XCTAssertTrue(url2?.absoluteString.contains("news.ycombinator.com") == true)

        // Test with feed URL when site URL is nil
        let url3 = FaviconFetcher.faviconURL(for: nil, feedURLString: "https://daringfireball.net/feeds/main", iconURLString: nil)
        XCTAssertNotNil(url3)
        XCTAssertTrue(url3?.absoluteString.contains("daringfireball.net") == true)
    }

    func testCachedImageReturnsNilInitially() {
        let feed = Feed(title: "Test Feed", url: "https://example.org/feed.xml")
        let cached = FaviconManager.shared.memoryCachedImage(for: feed)
        XCTAssertNil(cached, "Favicon should not be cached before any fetch occurred.")
    }

    func testClearCache() {
        let feed = Feed(title: "Test Feed", url: "https://example.org/feed.xml")
        FaviconManager.shared.clearCache()
        let cached = FaviconManager.shared.memoryCachedImage(for: feed)
        XCTAssertNil(cached)
    }
}
