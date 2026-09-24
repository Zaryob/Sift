import Foundation
import SwiftData

@Model
public final class Feed {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var url: String
    public var siteURL: String?
    public var feedDescription: String?
    public var iconURL: String?
    public var dateAdded: Date
    public var lastSuccessfulRefresh: Date?
    public var lastRefreshAttempt: Date?
    public var refreshError: String?
    public var etag: String?
    public var lastModified: String?
    public var enabled: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \FeedItem.feed)
    public var items: [FeedItem]

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        siteURL: String? = nil,
        feedDescription: String? = nil,
        iconURL: String? = nil,
        dateAdded: Date = Date(),
        lastSuccessfulRefresh: Date? = nil,
        lastRefreshAttempt: Date? = nil,
        refreshError: String? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        enabled: Bool = true,
        items: [FeedItem] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteURL = siteURL
        self.feedDescription = feedDescription
        self.iconURL = iconURL
        self.dateAdded = dateAdded
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastRefreshAttempt = lastRefreshAttempt
        self.refreshError = refreshError
        self.etag = etag
        self.lastModified = lastModified
        self.enabled = enabled
        self.items = items
    }
    
    public var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }
}
