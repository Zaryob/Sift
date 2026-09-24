import XCTest
@testable import Sift

final class FeedParserTests: XCTestCase {

    func testParseRSS20() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <rss version="2.0">
        <channel>
            <title>Test RSS Feed</title>
            <link>https://example.com</link>
            <description>A test description</description>
            <item>
                <title>Article 1</title>
                <link>https://example.com/article1</link>
                <guid>guid-12345</guid>
                <pubDate>Mon, 23 Sep 2026 12:00:00 GMT</pubDate>
                <description>Article 1 summary</description>
                <author>John Doe</author>
            </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = FeedParser()
        let feed = try parser.parse(data: xml)

        XCTAssertEqual(feed.title, "Test RSS Feed")
        XCTAssertEqual(feed.siteURL, "https://example.com")
        XCTAssertEqual(feed.feedDescription, "A test description")
        XCTAssertEqual(feed.items.count, 1)

        let item = feed.items[0]
        XCTAssertEqual(item.title, "Article 1")
        XCTAssertEqual(item.link, "https://example.com/article1")
        XCTAssertEqual(item.guid, "guid-12345")
        XCTAssertEqual(item.author, "John Doe")
        XCTAssertEqual(item.summary, "Article 1 summary")
    }

    func testParseAtom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Test Atom Feed</title>
            <link rel="alternate" href="https://example.org"/>
            <subtitle>Atom Subtitle</subtitle>
            <entry>
                <title>Atom Entry 1</title>
                <id>urn:uuid:12345</id>
                <link rel="alternate" href="https://example.org/entry1"/>
                <updated>2026-09-23T14:30:00Z</updated>
                <summary>Atom summary content</summary>
                <author><name>Jane Smith</name></author>
            </entry>
        </feed>
        """.data(using: .utf8)!

        let parser = FeedParser()
        let feed = try parser.parse(data: xml)

        XCTAssertEqual(feed.title, "Test Atom Feed")
        XCTAssertEqual(feed.siteURL, "https://example.org")
        XCTAssertEqual(feed.feedDescription, "Atom Subtitle")
        XCTAssertEqual(feed.items.count, 1)

        let entry = feed.items[0]
        XCTAssertEqual(entry.title, "Atom Entry 1")
        XCTAssertEqual(entry.guid, "urn:uuid:12345")
        XCTAssertEqual(entry.link, "https://example.org/entry1")
        XCTAssertEqual(entry.summary, "Atom summary content")
        XCTAssertEqual(entry.author, "Jane Smith")
    }

    func testMissingOptionalFields() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <rss version="2.0">
        <channel>
            <title>Minimal Feed</title>
            <item>
                <title>Minimal Article</title>
            </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = FeedParser()
        let feed = try parser.parse(data: xml)

        XCTAssertEqual(feed.title, "Minimal Feed")
        XCTAssertNil(feed.siteURL)
        XCTAssertEqual(feed.items.count, 1)

        let item = feed.items[0]
        XCTAssertEqual(item.title, "Minimal Article")
        XCTAssertNil(item.guid)
        XCTAssertNil(item.link)
        XCTAssertNil(item.author)
        XCTAssertNil(item.summary)
    }

    func testMalformedItemHandling() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <rss version="2.0">
        <channel>
            <title>Partial Feed</title>
            <item>
                <title>Good Article</title>
                <guid>good-1</guid>
            </item>
            <item>
                <title>Second Article</title>
                <guid>good-2</guid>
            </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = FeedParser()
        let feed = try parser.parse(data: xml)

        XCTAssertGreaterThanOrEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].title, "Good Article")
    }
}
