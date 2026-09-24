import XCTest
@testable import Sift

final class OPMLServiceTests: XCTestCase {

    func testOPMLParsingAndGeneration() throws {
        let opmlXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Test Subscriptions</title>
          </head>
          <body>
            <outline text="Tech">
              <outline type="rss" text="Example Feed 1" xmlUrl="https://example.com/rss" htmlUrl="https://example.com"/>
            </outline>
            <outline type="rss" text="Example Feed 2" xmlUrl="https://example.org/feed.xml" htmlUrl="https://example.org"/>
          </body>
        </opml>
        """

        guard let data = opmlXML.data(using: .utf8) else {
            XCTFail("Failed to convert OPML string to Data")
            return
        }

        let parser = OPMLService()
        let items = try parser.parse(data: data)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Example Feed 1")
        XCTAssertEqual(items[0].xmlURL, "https://example.com/rss")
        XCTAssertEqual(items[0].category, "Tech")

        XCTAssertEqual(items[1].title, "Example Feed 2")
        XCTAssertEqual(items[1].xmlURL, "https://example.org/feed.xml")

        // Test Export
        let feed1 = Feed(title: "Example Feed 1", url: "https://example.com/rss", category: "Tech")
        let feed2 = Feed(title: "Example Feed 2", url: "https://example.org/feed.xml")

        let generatedOPML = OPMLService.generateOPML(from: [feed1, feed2])
        XCTAssertTrue(generatedOPML.contains("Example Feed 1"))
        XCTAssertTrue(generatedOPML.contains("Example Feed 2"))
        XCTAssertTrue(generatedOPML.contains("Tech"))
    }
}
