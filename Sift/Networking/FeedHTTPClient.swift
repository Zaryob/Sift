import Foundation

public enum FeedFetchResult {
    case success(data: Data, etag: String?, lastModified: String?, responseURL: URL)
    case notModified
}

public protocol FeedHTTPClientProtocol {
    func fetchFeed(
        from url: URL,
        etag: String?,
        lastModified: String?
    ) async throws -> FeedFetchResult
}

public final class FeedHTTPClient: FeedHTTPClientProtocol {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 SiftReader/1.0",
                "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    public func fetchFeed(
        from url: URL,
        etag: String?,
        lastModified: String?
    ) async throws -> FeedFetchResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let etag = etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        if let lastModified = lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.cannotParseResponse)
        }

        if httpResponse.statusCode == 304 {
            return .notModified
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }

        let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let newLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        let finalURL = httpResponse.url ?? url

        return .success(data: data, etag: newEtag, lastModified: newLastModified, responseURL: finalURL)
    }
}
