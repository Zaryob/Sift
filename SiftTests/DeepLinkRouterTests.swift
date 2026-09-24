import XCTest
@testable import Sift

final class DeepLinkRouterTests: XCTestCase {

    func testParseAllArticlesURL() {
        let url = URL(string: "rssreader://all")!
        let dest = DeepLinkRouter.parse(url: url)
        XCTAssertEqual(dest, .all)
    }

    func testParseFeedURL() {
        let id = UUID()
        let url = URL(string: "rssreader://feed/\(id.uuidString)")!
        let dest = DeepLinkRouter.parse(url: url)
        XCTAssertEqual(dest, .feed(id: id))
    }

    func testParseArticleURL() {
        let id = UUID()
        let url = URL(string: "rssreader://article/\(id.uuidString)")!
        let dest = DeepLinkRouter.parse(url: url)
        XCTAssertEqual(dest, .article(id: id))
    }

    func testInvalidScheme() {
        let url = URL(string: "https://example.com")!
        let dest = DeepLinkRouter.parse(url: url)
        XCTAssertNil(dest)
    }
}
