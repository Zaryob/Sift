import Foundation

public struct DiscoveredFeed: Hashable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public final class FeedDiscoveryService {
    private let httpClient: FeedHTTPClientProtocol

    public init(httpClient: FeedHTTPClientProtocol = FeedHTTPClient()) {
        self.httpClient = httpClient
    }

    /// Attempts to discover valid RSS/Atom feed URLs from a web page URL or direct feed URL
    public func discoverFeeds(from pageURL: URL) async throws -> [DiscoveredFeed] {
        let result = try await httpClient.fetchFeed(from: pageURL, etag: nil, lastModified: nil)
        
        guard case .success(let data, _, _, let responseURL) = result else {
            return []
        }

        // 1. Try parsing directly as RSS/Atom
        let parser = FeedParser()
        if let parsed = try? parser.parse(data: data) {
            return [DiscoveredFeed(title: parsed.title, url: responseURL)]
        }

        // 2. Parse HTML for <link rel="alternate" type="application/rss+xml" href="...">
        guard let htmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        var discovered: [DiscoveredFeed] = []
        let linkPattern = "(?i)<link[^>]+?rel=[\"']?alternate[\"']?[^>]*?>"
        let regex = try? NSRegularExpression(pattern: linkPattern, options: [])
        let matches = regex?.matches(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.utf16.count)) ?? []

        for match in matches {
            guard let range = Range(match.range, in: htmlString) else { continue }
            let tag = String(htmlString[range])
            
            let isRSS = tag.contains("application/rss+xml") || tag.contains("application/atom+xml") || tag.contains("application/xml")
            guard isRSS else { continue }

            if let href = extractAttribute("href", from: tag) {
                if let resolvedURL = URL(string: href, relativeTo: responseURL)?.absoluteURL {
                    let title = extractAttribute("title", from: tag) ?? "RSS Feed"
                    discovered.append(DiscoveredFeed(title: title, url: resolvedURL))
                }
            }
        }

        // 3. Fallback common feed paths if no link tag found
        if discovered.isEmpty {
            let commonPaths = ["/rss", "/feed", "/atom.xml", "/rss.xml", "/feed.xml", "/index.xml"]
            for path in commonPaths {
                if let candidate = URL(string: path, relativeTo: responseURL)?.absoluteURL {
                    if candidate != responseURL, let candidateResult = try? await httpClient.fetchFeed(from: candidate, etag: nil, lastModified: nil) {
                        if case .success(let candidateData, _, _, let candidateResponseURL) = candidateResult {
                            if let candidateParsed = try? FeedParser().parse(data: candidateData) {
                                discovered.append(DiscoveredFeed(title: candidateParsed.title, url: candidateResponseURL))
                                break
                            }
                        }
                    }
                }
            }
        }

        return discovered
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = "(?i)\(name)=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: tag.utf16.count)),
              let range = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[range])
    }
}
