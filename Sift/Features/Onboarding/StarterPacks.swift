import Foundation

/// Represents a single curated RSS/Atom feed recommended to new users.
public struct StarterFeedItem: Identifiable, Hashable, Sendable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let category: String

    public init(title: String, url: String, category: String) {
        self.title = title
        self.url = url
        self.category = category
    }
}

/// Represents a thematic collection of feeds for quick onboarding.
public struct StarterPack: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let feeds: [StarterFeedItem]

    public static let allPacks: [StarterPack] = [
        StarterPack(
            title: "Tech & Engineering",
            subtitle: "Hacker News, Ars Technica, Daring Fireball, The Verge",
            iconName: "cpu",
            feeds: [
                StarterFeedItem(title: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Technology"),
                StarterFeedItem(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main", category: "Technology"),
                StarterFeedItem(title: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: "Technology"),
                StarterFeedItem(title: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "Technology")
            ]
        ),
        StarterPack(
            title: "Apple & Swift",
            subtitle: "Official Swift blog, Swift by Sundell, 9to5Mac",
            iconName: "applelogo",
            feeds: [
                StarterFeedItem(title: "Swift.org Blog", url: "https://www.swift.org/atom.xml", category: "Development"),
                StarterFeedItem(title: "Swift by Sundell", url: "https://www.swiftbysundell.com/rss", category: "Development"),
                StarterFeedItem(title: "9to5Mac", url: "https://9to5mac.com/feed/", category: "Apple")
            ]
        ),
        StarterPack(
            title: "Design & UX",
            subtitle: "Sidebar.io, Smashing Magazine, UX Collective",
            iconName: "paintbrush",
            feeds: [
                StarterFeedItem(title: "Sidebar.io", url: "https://sidebar.io/feed.xml", category: "Design"),
                StarterFeedItem(title: "Smashing Magazine", url: "https://www.smashingmagazine.com/feed/", category: "Design"),
                StarterFeedItem(title: "UX Collective", url: "https://uxdesign.cc/feed", category: "Design")
            ]
        ),
        StarterPack(
            title: "Science & Space",
            subtitle: "Nature News, NASA, MIT Technology Review",
            iconName: "atom",
            feeds: [
                StarterFeedItem(title: "Nature News", url: "https://www.nature.com/nature.rss", category: "Science"),
                StarterFeedItem(title: "NASA Breaking News", url: "https://www.nasa.gov/news-release/feed/", category: "Science"),
                StarterFeedItem(title: "MIT Tech Review", url: "https://www.technologyreview.com/feed/", category: "Science")
            ]
        )
    ]
}
