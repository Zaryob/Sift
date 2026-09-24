import Foundation

public struct FaviconFetcher {
    /// Returns a favicon URL for the given Feed metadata or URL
    public static func faviconURL(for siteURLString: String?, feedURLString: String?, iconURLString: String?) -> URL? {
        if let iconURLString = iconURLString,
           let url = URL(string: iconURLString),
           url.scheme != nil {
            return url
        }

        let candidateURLString = siteURLString ?? feedURLString
        guard let candidateURLString = candidateURLString,
              let url = URL(string: candidateURLString),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return URL(string: "https://\(host)/favicon.ico")
    }
}
