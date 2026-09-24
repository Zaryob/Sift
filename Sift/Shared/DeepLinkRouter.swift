import Foundation

public enum DeepLinkDestination: Equatable {
    case all
    case feed(id: UUID)
    case article(id: UUID)
}

public struct DeepLinkRouter {
    public static func parse(url: URL) -> DeepLinkDestination? {
        guard url.scheme?.lowercased() == "rssreader" else {
            return nil
        }
        
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "all" {
            return .all
        } else if host == "feed" || host == "feeds" {
            if let idString = pathComponents.first, let uuid = UUID(uuidString: idString) {
                return .feed(id: uuid)
            }
        } else if host == "article" || host == "articles" {
            if let idString = pathComponents.first, let uuid = UUID(uuidString: idString) {
                return .article(id: uuid)
            }
        } else if let host = host, let uuid = UUID(uuidString: host) {
            return .article(id: uuid)
        }
        
        return nil
    }
}
