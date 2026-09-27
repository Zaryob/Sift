import CryptoKit
import Foundation
import NaturalLanguage

private struct FeedManifest: Decodable {
    let feeds: [FeedDefinition]
}

private struct FeedDefinition: Decodable, Sendable {
    let name: String
    let url: URL
    let category: String?
    let source: String?
}

private struct RawFeedItem: Sendable {
    var title = ""
    var summary = ""
    var link = ""
    var guid = ""
    var publishedAt = ""
    var sourceURL = ""
}

private struct CollectedArticle: Encodable, Sendable {
    let id: UUID
    let title: String
    let summary: String?
    let publisherKey: String
    let publishedAt: String
    let url: String
    let language: String
    let feedName: String
    let feedCategory: String?
}

private struct FeedFetchResult: Sendable {
    let feed: FeedDefinition
    let articles: [CollectedArticle]
    let error: String?
}

private struct Options: Sendable {
    var manifest = URL(fileURLWithPath: "tools/local/sift-feed-sample.json")
    var sinceHours = 168.0
    var limit = 500
    var perPublisher = 30
    var perFeed = 100

    init(arguments: [String]) throws {
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else {
                throw CollectorError.usage("Missing value for \(flag)")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--manifest": manifest = URL(fileURLWithPath: value)
            case "--since-hours":
                guard let parsed = Double(value), parsed > 0 else {
                    throw CollectorError.usage("--since-hours must be greater than 0")
                }
                sinceHours = parsed
            case "--limit":
                guard let parsed = Int(value), parsed > 0 else {
                    throw CollectorError.usage("--limit must be greater than 0")
                }
                limit = parsed
            case "--per-publisher":
                guard let parsed = Int(value), parsed > 0 else {
                    throw CollectorError.usage("--per-publisher must be greater than 0")
                }
                perPublisher = parsed
            case "--per-feed":
                guard let parsed = Int(value), parsed > 0 else {
                    throw CollectorError.usage("--per-feed must be greater than 0")
                }
                perFeed = parsed
            default: throw CollectorError.usage("Unknown option: \(flag)")
            }
            index += 2
        }
    }
}

private enum CollectorError: Error, CustomStringConvertible {
    case usage(String)
    case invalidManifest(String)

    var description: String {
        switch self {
        case .usage(let message), .invalidManifest(let message): message
        }
    }

    static let help = """
    Usage:
      CollectM0FeedSnapshot [--manifest path] [--since-hours 168] \
        [--limit 500] [--per-publisher 30] [--per-feed 100]

    Reads a local JSON manifest, fetches RSS/Atom feeds, and writes article JSONL to
    stdout. Feed/article counts and fetch failures go to stderr. It never saves feed
    content. Redirect stdout to a local, git-ignored path only when a reviewer needs
    a persistent snapshot.
    """
}

private final class RSSItemParser: NSObject, XMLParserDelegate {
    private(set) var items: [RawFeedItem] = []
    private var current: RawFeedItem?
    private var capture: String?
    private var capturedText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = Self.localName(elementName, qName: qName)
        if name == "item" || name == "entry" {
            current = RawFeedItem()
            return
        }
        guard current != nil else { return }
        if name == "link", let href = attributes["href"], !href.isEmpty {
            current?.link = href
        }
        if name == "source", let url = attributes["url"], !url.isEmpty {
            current?.sourceURL = url
        }
        guard ["title", "description", "summary", "encoded", "content", "link", "guid", "id", "pubdate", "published", "updated", "date"].contains(name) else { return }
        capture = name
        capturedText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else { return }
        capturedText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard capture != nil else { return }
        capturedText += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.localName(elementName, qName: qName)
        if name == capture {
            let value = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title": if current?.title.isEmpty == true { current?.title = value }
            case "description", "summary", "encoded", "content": if current?.summary.isEmpty == true { current?.summary = value }
            case "link": if current?.link.isEmpty == true { current?.link = value }
            case "guid", "id": if current?.guid.isEmpty == true { current?.guid = value }
            case "pubdate", "published", "updated", "date": if current?.publishedAt.isEmpty == true { current?.publishedAt = value }
            default: break
            }
            capture = nil
            capturedText = ""
        }
        if name == "item" || name == "entry", let item = current {
            items.append(item)
            current = nil
            capture = nil
            capturedText = ""
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // XMLParser communicates failures through parse()'s return value.
    }

    private static func localName(_ name: String, qName: String?) -> String {
        (qName ?? name).split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }
}

@main
private enum CollectM0FeedSnapshot {
    static func main() async {
        do {
            if CommandLine.arguments.dropFirst().contains("--help") {
                print(CollectorError.help)
                return
            }
            let options = try Options(arguments: CommandLine.arguments)
            let manifestData = try Data(contentsOf: options.manifest)
            let manifest = try JSONDecoder().decode(FeedManifest.self, from: manifestData)
            guard !manifest.feeds.isEmpty else { throw CollectorError.invalidManifest("Feed manifest is empty") }

            var results: [FeedFetchResult] = []
            for start in stride(from: 0, to: manifest.feeds.count, by: 8) {
                let batch = Array(manifest.feeds[start..<min(start + 8, manifest.feeds.count)])
                let batchResults = await withTaskGroup(of: FeedFetchResult.self) { group in
                    for feed in batch {
                        group.addTask { await fetch(feed, options: options) }
                    }
                    var gathered: [FeedFetchResult] = []
                    for await result in group { gathered.append(result) }
                    return gathered
                }
                results.append(contentsOf: batchResults)
            }

            var articles = results.flatMap(\.articles)
            articles.sort {
                if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.publishedAt > $1.publishedAt
            }
            var seen = Set<String>()
            articles = articles.filter { article in
                let key = "\(article.publisherKey)|\(Self.normalizedTitle(article.title))"
                return seen.insert(key).inserted
            }
            let balanced = Self.balancedSelection(
                articles,
                limit: options.limit,
                perPublisher: options.perPublisher
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            for article in balanced {
                let line = try encoder.encode(article)
                FileHandle.standardOutput.write(line)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            let successCount = results.filter { $0.error == nil }.count
            FileHandle.standardError.write(Data(
                "Fetched \(successCount)/\(results.count) feeds; \(articles.count) unique recent items; emitted \(balanced.count) balanced articles.\n".utf8
            ))
            for result in results where result.error != nil {
                FileHandle.standardError.write(Data("Feed unavailable: \(result.feed.name) — \(result.error!)\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func fetch(_ feed: FeedDefinition, options: Options) async -> FeedFetchResult {
        do {
            var request = URLRequest(url: feed.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
            request.setValue("Sift M0 local feed collector/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let itemParser = RSSItemParser()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldReportNamespacePrefixes = true
            parser.delegate = itemParser
            guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }

            let cutoff = Date().addingTimeInterval(-options.sinceHours * 60 * 60)
            let feedHost = feed.url.host?.lowercased() ?? "unknown.publisher"
            let articles = itemParser.items.compactMap { item -> CollectedArticle? in
                let title = Self.cleanText(item.title)
                guard !title.isEmpty, let publishedAt = Self.parseDate(item.publishedAt), publishedAt >= cutoff else { return nil }
                let link = item.link.isEmpty ? item.guid : item.link
                let sourceHost = URL(string: item.sourceURL)?.host?.lowercased()
                let publisherKey = sourceHost ?? feedHost
                let summary = Self.cleanText(item.summary)
                let identity = "\(publisherKey)|\(link.isEmpty ? title : link)"
                return CollectedArticle(
                    id: Self.stableUUID(identity),
                    title: title,
                    summary: summary.isEmpty ? nil : String(summary.prefix(4000)),
                    publisherKey: publisherKey,
                    publishedAt: ISO8601DateFormatter().string(from: publishedAt),
                    url: link,
                    language: Self.detectLanguage(title + " " + summary),
                    feedName: feed.name,
                    feedCategory: feed.category
                )
            }
            return FeedFetchResult(feed: feed, articles: Array(articles.prefix(options.perFeed)), error: nil)
        } catch {
            return FeedFetchResult(feed: feed, articles: [], error: String(describing: error))
        }
    }

    private static func balancedSelection(
        _ articles: [CollectedArticle],
        limit: Int,
        perPublisher: Int
    ) -> [CollectedArticle] {
        let grouped = Dictionary(grouping: articles, by: \.publisherKey)
            .mapValues { Array($0.prefix(perPublisher)) }
        let publishers = grouped.keys.sorted()
        var selected: [CollectedArticle] = []
        var offset = 0
        while selected.count < limit {
            var addedThisRound = false
            for publisher in publishers {
                guard let items = grouped[publisher], offset < items.count else { continue }
                selected.append(items[offset])
                addedThisRound = true
                if selected.count == limit { break }
            }
            if !addedThisRound { break }
            offset += 1
        }
        return selected.sorted {
            if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.publishedAt > $1.publishedAt
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "und"
    }

    private static func cleanText(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "<[^>]+>") else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func stableUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
