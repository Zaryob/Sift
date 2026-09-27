import Foundation
import SwiftData

public struct OPMLItem {
    public let title: String
    public let xmlURL: String
    public let htmlURL: String?
    public let category: String?

    public init(title: String, xmlURL: String, htmlURL: String? = nil, category: String? = nil) {
        self.title = title
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
        self.category = category
    }
}

public final class OPMLService: NSObject, XMLParserDelegate {
    private var items: [OPMLItem] = []
    /// Stack tracks nested folder names so we correctly restore the parent
    /// category when a nested outline closes.
    private var categoryStack: [String?] = []

    /// The innermost active category, if any.
    private var currentCategory: String? { categoryStack.last ?? nil }

    public func parse(data: Data) throws -> [OPMLItem] {
        items.removeAll()
        categoryStack.removeAll()

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw URLError(.cannotParseResponse)
        }
        return items
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let type = attributeDict["type"]?.lowercased()
        let xmlUrl = attributeDict["xmlUrl"] ?? attributeDict["xmlURL"]
        let text = attributeDict["text"] ?? attributeDict["title"] ?? "Untitled Feed"
        let htmlUrl = attributeDict["htmlUrl"] ?? attributeDict["htmlURL"]
        let inlineCategory = attributeDict["category"]

        if let xmlUrl = xmlUrl, !xmlUrl.isEmpty {
            // Feed item outline — record it, then push nil sentinel so
            // didEndElement stays balanced without affecting the category.
            let item = OPMLItem(
                title: text,
                xmlURL: xmlUrl,
                htmlURL: htmlUrl,
                category: inlineCategory ?? currentCategory
            )
            items.append(item)
            categoryStack.append(nil) // sentinel for the closing </outline>
        } else if type == nil || type == "folder" {
            // Folder/category outline — push its name so nested feeds see it.
            categoryStack.append(text)
        } else {
            // Unknown outline with no xmlUrl — push nil sentinel.
            categoryStack.append(nil)
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }
        // Restore the parent folder context.
        if !categoryStack.isEmpty {
            categoryStack.removeLast()
        }
    }

    public static func generateOPML(from feeds: [Feed]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Sift Subscriptions</title>
            <dateCreated>\(ISO8601DateFormatter().string(from: Date()))</dateCreated>
          </head>
          <body>

        """

        let categorized = Dictionary(grouping: feeds) { $0.category ?? "" }

        for (category, categoryFeeds) in categorized {
            if !category.isEmpty {
                let escapedCategory = escapeXML(category)
                xml += "    <outline text=\"\(escapedCategory)\" title=\"\(escapedCategory)\">\n"
                for feed in categoryFeeds {
                    xml += formatFeedOutline(feed, indent: "      ")
                }
                xml += "    </outline>\n"
            } else {
                for feed in categoryFeeds {
                    xml += formatFeedOutline(feed, indent: "    ")
                }
            }
        }

        xml += """
          </body>
        </opml>
        """
        return xml
    }

    private static func formatFeedOutline(_ feed: Feed, indent: String) -> String {
        let title = escapeXML(feed.title)
        let xmlUrl = escapeXML(feed.url)
        let htmlUrl = escapeXML(feed.siteURL ?? "")
        return "\(indent)<outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(xmlUrl)\" htmlUrl=\"\(htmlUrl)\"/>\n"
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
