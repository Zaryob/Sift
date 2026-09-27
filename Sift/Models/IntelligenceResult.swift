import Foundation
import SwiftData

public enum IntelligenceModelKind: String, Codable, Sendable {
    case privateCloudCompute
    case onDevice
    case extractiveFallback

    public var displayName: String {
        switch self {
        case .privateCloudCompute:
            return String(localized: "Apple Intelligence Private Cloud")
        case .onDevice:
            return String(localized: "On-device Apple Intelligence")
        case .extractiveFallback:
            return String(localized: "Offline summary")
        }
    }
}

@Model
public final class ArticleIntelligenceResult {
    @Attribute(.unique) public var id: UUID
    public var summary: String
    // Optional at the persistence boundary so stores created before these
    // attributes existed can be migrated without inventing mandatory values.
    public var keyPoints: [String]?
    public var topics: [String]?
    public var modelKindRawValue: String
    public var sourceContentHash: String
    public var promptVersion: Int
    public var generatedAt: Date
    public var article: FeedItem?

    public init(
        id: UUID = UUID(),
        summary: String,
        keyPoints: [String] = [],
        topics: [String] = [],
        modelKind: IntelligenceModelKind,
        sourceContentHash: String,
        promptVersion: Int,
        generatedAt: Date = Date(),
        article: FeedItem? = nil
    ) {
        self.id = id
        self.summary = summary
        self.keyPoints = keyPoints
        self.topics = topics
        self.modelKindRawValue = modelKind.rawValue
        self.sourceContentHash = sourceContentHash
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
        self.article = article
    }

    public var modelKind: IntelligenceModelKind {
        IntelligenceModelKind(rawValue: modelKindRawValue) ?? .extractiveFallback
    }
}

@Model
public final class SavedBriefing {
    @Attribute(.unique) public var id: UUID
    @Attribute(.externalStorage) public var text: String
    public var articleIDs: [UUID]
    public var sourceContentHash: String
    public var modelKindRawValue: String
    public var promptVersion: Int
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        articleIDs: [UUID],
        sourceContentHash: String,
        modelKind: IntelligenceModelKind,
        promptVersion: Int,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.articleIDs = articleIDs
        self.sourceContentHash = sourceContentHash
        self.modelKindRawValue = modelKind.rawValue
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }

    public var modelKind: IntelligenceModelKind {
        IntelligenceModelKind(rawValue: modelKindRawValue) ?? .extractiveFallback
    }
}

public struct IntelligenceOutput: Sendable {
    public let text: String
    public let keyPoints: [String]
    public let topics: [String]
    public let modelKind: IntelligenceModelKind
    public let isCached: Bool

    public init(
        text: String,
        keyPoints: [String] = [],
        topics: [String] = [],
        modelKind: IntelligenceModelKind,
        isCached: Bool
    ) {
        self.text = text
        self.keyPoints = keyPoints
        self.topics = topics
        self.modelKind = modelKind
        self.isCached = isCached
    }
}
