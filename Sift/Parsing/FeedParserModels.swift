import Foundation

nonisolated public struct ParsedFeed: Equatable, Sendable {
    public var title: String
    var siteURL: String?
    var feedDescription: String?
    var iconURL: String?
    var items: [ParsedItem]

    public init(
        title: String,
        siteURL: String? = nil,
        feedDescription: String? = nil,
        iconURL: String? = nil,
        items: [ParsedItem] = []
    ) {
        self.title = title
        self.siteURL = siteURL
        self.feedDescription = feedDescription
        self.iconURL = iconURL
        self.items = items
    }
}

nonisolated public struct ParsedItem: Equatable, Sendable {
    public var guid: String?
    public var title: String
    public var link: String?
    public var author: String?
    public var summary: String?
    public var content: String?
    public var imageURL: String?
    public var publicationDate: Date

    public init(
        guid: String? = nil,
        title: String,
        link: String? = nil,
        author: String? = nil,
        summary: String? = nil,
        content: String? = nil,
        imageURL: String? = nil,
        publicationDate: Date = Date()
    ) {
        self.guid = guid
        self.title = title
        self.link = link
        self.author = author
        self.summary = summary
        self.content = content
        self.imageURL = imageURL
        self.publicationDate = publicationDate
    }
}
