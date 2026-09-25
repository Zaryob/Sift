import Foundation

public enum FeedParserError: Error, LocalizedError, Equatable {
    case invalidXML
    case unsupportedFormat
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "The feed XML is invalid or malformed."
        case .unsupportedFormat:
            return "The feed format is not supported (must be RSS 2.0 or Atom)."
        case .emptyData:
            return "The feed response contained no data."
        }
    }
}

public final class FeedParser: NSObject, XMLParserDelegate {
    private enum FeedType {
        case unknown
        case rss
        case atom
    }

    private var feedType: FeedType = .unknown
    private var currentElement: String = ""
    private var currentAttributes: [String: String] = [:]
    private var accumulatedText: String = ""

    // Feed metadata
    private var feedTitle: String = ""
    private var feedLink: String?
    private var feedDescription: String?
    private var feedIconURL: String?

    // Items accumulation
    private var items: [ParsedItem] = []

    // State tracking for RSS items
    private var inItem: Bool = false
    private var currentItemGuid: String?
    private var currentItemTitle: String = ""
    private var currentItemLink: String?
    private var currentItemAuthor: String?
    private var currentItemSummary: String?
    private var currentItemContent: String?
    private var currentItemImageURL: String?
    private var currentItemPubDateString: String?

    // State tracking for Atom entries
    private var inEntry: Bool = false
    private var currentEntryID: String?
    private var currentEntryTitle: String = ""
    private var currentEntryLink: String?
    private var currentEntryAuthor: String?
    private var currentEntrySummary: String?
    private var currentEntryContent: String?
    private var currentEntryImageURL: String?
    private var currentEntryUpdatedString: String?
    private var currentEntryPublishedString: String?
    private var inAuthorElement: Bool = false

    private static let iso8601FormatterWithMillis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let rfc822Formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm zzz",
            "EEE, dd MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            return df
        }
    }()

    public func parse(data: Data) throws -> ParsedFeed {
        guard !data.isEmpty else {
            throw FeedParserError.emptyData
        }

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            if let error = parser.parserError {
                print("XML Parsing error: \(error.localizedDescription)")
            }
            throw FeedParserError.invalidXML
        }

        guard feedType != .unknown else {
            throw FeedParserError.unsupportedFormat
        }

        let cleanTitle = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "Untitled Feed" : cleanTitle

        return ParsedFeed(
            title: finalTitle,
            siteURL: feedLink,
            feedDescription: feedDescription,
            iconURL: feedIconURL,
            items: items
        )
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        currentElement = name
        currentAttributes = attributeDict
        accumulatedText = ""

        if feedType == .unknown {
            if name == "rss" || name == "rdf:rdf" || name == "channel" {
                feedType = .rss
            } else if name == "feed" {
                feedType = .atom
            }
        }

        if feedType == .rss {
            if name == "item" {
                inItem = true
                currentItemGuid = nil
                currentItemTitle = ""
                currentItemLink = nil
                currentItemAuthor = nil
                currentItemSummary = nil
                currentItemContent = nil
                currentItemImageURL = nil
                currentItemPubDateString = nil
            } else if inItem, name == "enclosure" {
                let type = attributeDict["type"] ?? ""
                if currentItemImageURL == nil, type.hasPrefix("image"), let url = attributeDict["url"], !url.isEmpty {
                    currentItemImageURL = url
                }
            } else if inItem, name == "media:thumbnail" {
                if currentItemImageURL == nil, let url = attributeDict["url"], !url.isEmpty {
                    currentItemImageURL = url
                }
            } else if inItem, name == "media:content" {
                let medium = attributeDict["medium"] ?? ""
                let type = attributeDict["type"] ?? ""
                if currentItemImageURL == nil, medium == "image" || type.hasPrefix("image"), let url = attributeDict["url"], !url.isEmpty {
                    currentItemImageURL = url
                }
            }
        } else if feedType == .atom {
            if name == "entry" {
                inEntry = true
                currentEntryID = nil
                currentEntryTitle = ""
                currentEntryLink = nil
                currentEntryAuthor = nil
                currentEntrySummary = nil
                currentEntryContent = nil
                currentEntryImageURL = nil
                currentEntryUpdatedString = nil
                currentEntryPublishedString = nil
            } else if name == "author" {
                inAuthorElement = true
            } else if name == "link" {
                let rel = attributeDict["rel"] ?? "alternate"
                let href = attributeDict["href"]
                if rel == "alternate" || rel == "" {
                    if inEntry {
                        if currentEntryLink == nil { currentEntryLink = href }
                    } else {
                        if feedLink == nil { feedLink = href }
                    }
                } else if rel == "enclosure", inEntry, currentEntryImageURL == nil {
                    let type = attributeDict["type"] ?? ""
                    if type.hasPrefix("image"), let href = href, !href.isEmpty {
                        currentEntryImageURL = href
                    }
                }
            } else if name == "icon" || name == "logo" {
                // atom icon/logo
            } else if inEntry, (name == "media:thumbnail" || name == "media:content") {
                let medium = attributeDict["medium"] ?? ""
                let type = attributeDict["type"] ?? ""
                if currentEntryImageURL == nil, medium == "image" || type.hasPrefix("image") || name == "media:thumbnail",
                   let url = attributeDict["url"], !url.isEmpty {
                    currentEntryImageURL = url
                }
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        accumulatedText += string
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let text = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if feedType == .rss {
            if inItem {
                switch name {
                case "item":
                    inItem = false
                    commitRSSItem()
                case "title":
                    if currentItemTitle.isEmpty { currentItemTitle = text }
                case "link":
                    if currentItemLink == nil, !text.isEmpty { currentItemLink = text }
                case "guid":
                    if currentItemGuid == nil, !text.isEmpty { currentItemGuid = text }
                case "pubdate", "dc:date":
                    if currentItemPubDateString == nil, !text.isEmpty { currentItemPubDateString = text }
                case "description":
                    if currentItemSummary == nil, !text.isEmpty { currentItemSummary = text }
                case "content:encoded":
                    if currentItemContent == nil, !text.isEmpty { currentItemContent = text }
                case "author", "dc:creator":
                    if currentItemAuthor == nil, !text.isEmpty { currentItemAuthor = text }
                default:
                    break
                }
            } else {
                switch name {
                case "title":
                    if feedTitle.isEmpty { feedTitle = text }
                case "link":
                    if feedLink == nil, !text.isEmpty { feedLink = text }
                case "description":
                    if feedDescription == nil, !text.isEmpty { feedDescription = text }
                default:
                    break
                }
            }
        } else if feedType == .atom {
            if inEntry {
                switch name {
                case "entry":
                    inEntry = false
                    commitAtomEntry()
                case "title":
                    if currentEntryTitle.isEmpty { currentEntryTitle = text }
                case "id":
                    if currentEntryID == nil, !text.isEmpty { currentEntryID = text }
                case "updated":
                    if currentEntryUpdatedString == nil, !text.isEmpty { currentEntryUpdatedString = text }
                case "published":
                    if currentEntryPublishedString == nil, !text.isEmpty { currentEntryPublishedString = text }
                case "summary":
                    if currentEntrySummary == nil, !text.isEmpty { currentEntrySummary = text }
                case "content":
                    if currentEntryContent == nil, !text.isEmpty { currentEntryContent = text }
                case "name":
                    if inAuthorElement, currentEntryAuthor == nil, !text.isEmpty { currentEntryAuthor = text }
                case "author":
                    inAuthorElement = false
                default:
                    break
                }
            } else {
                switch name {
                case "title":
                    if feedTitle.isEmpty { feedTitle = text }
                case "subtitle":
                    if feedDescription == nil, !text.isEmpty { feedDescription = text }
                case "icon", "logo":
                    if feedIconURL == nil, !text.isEmpty { feedIconURL = text }
                case "author":
                    inAuthorElement = false
                default:
                    break
                }
            }
        }
    }

    private func commitRSSItem() {
        let title = currentItemTitle.isEmpty ? "Untitled Article" : currentItemTitle
        let pubDate = parseDate(currentItemPubDateString) ?? Date()
        let imageURL = currentItemImageURL ?? Self.extractFirstImageURL(from: currentItemContent ?? currentItemSummary)

        let parsedItem = ParsedItem(
            guid: currentItemGuid,
            title: title,
            link: currentItemLink,
            author: currentItemAuthor,
            summary: currentItemSummary,
            content: currentItemContent,
            imageURL: imageURL,
            publicationDate: pubDate
        )
        items.append(parsedItem)
    }

    private func commitAtomEntry() {
        let title = currentEntryTitle.isEmpty ? "Untitled Article" : currentEntryTitle
        let dateString = currentEntryPublishedString ?? currentEntryUpdatedString
        let pubDate = parseDate(dateString) ?? Date()
        let imageURL = currentEntryImageURL ?? Self.extractFirstImageURL(from: currentEntryContent ?? currentEntrySummary)

        let parsedItem = ParsedItem(
            guid: currentEntryID,
            title: title,
            link: currentEntryLink,
            author: currentEntryAuthor,
            summary: currentEntrySummary,
            content: currentEntryContent,
            imageURL: imageURL,
            publicationDate: pubDate
        )
        items.append(parsedItem)
    }

    /// Falls back to the first inline `<img>` tag when the feed provides no
    /// enclosure/media:thumbnail/media:content image reference.
    private static func extractFirstImageURL(from html: String?) -> String? {
        guard let html = html, !html.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let urlRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[urlRange])
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }

        if let date = Self.iso8601FormatterWithMillis.date(from: dateString) {
            return date
        }
        if let date = Self.iso8601FormatterStandard.date(from: dateString) {
            return date
        }
        for formatter in Self.rfc822Formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}
