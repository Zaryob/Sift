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

public enum IntelligenceAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLocale
    case unavailable

    public var message: String? {
        switch self {
        case .available:
            nil
        case .deviceNotEligible:
            String(localized: "Apple Intelligence is not supported on this device. Sift will use offline summaries.")
        case .appleIntelligenceNotEnabled:
            String(localized: "Apple Intelligence is turned off. Enable it in System Settings to generate on-device summaries.")
        case .modelNotReady:
            String(localized: "Apple Intelligence is still preparing its on-device models. Sift will retry after a future refresh.")
        case .unsupportedLocale:
            String(localized: "Apple Intelligence does not support the current language. Sift will use offline summaries.")
        case .unavailable:
            String(localized: "Apple Intelligence is currently unavailable. Sift will use offline summaries.")
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
    public var irrelevantBlockIDs: [Int]?
    public var cleanupPromptVersion: Int?
    public var modelKindRawValue: String
    public var sourceContentHash: String
    public var promptVersion: Int
    public var outputLanguageCode: String?
    public var generatedAt: Date
    public var article: FeedItem?

    public init(
        id: UUID = UUID(),
        summary: String,
        keyPoints: [String] = [],
        topics: [String] = [],
        irrelevantBlockIDs: [Int] = [],
        cleanupPromptVersion: Int? = nil,
        modelKind: IntelligenceModelKind,
        sourceContentHash: String,
        promptVersion: Int,
        outputLanguageCode: String? = nil,
        generatedAt: Date = Date(),
        article: FeedItem? = nil
    ) {
        self.id = id
        self.summary = summary
        self.keyPoints = keyPoints
        self.topics = topics
        self.irrelevantBlockIDs = irrelevantBlockIDs
        self.cleanupPromptVersion = cleanupPromptVersion
        self.modelKindRawValue = modelKind.rawValue
        self.sourceContentHash = sourceContentHash
        self.promptVersion = promptVersion
        self.outputLanguageCode = outputLanguageCode
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
    public var outputLanguageCode: String?
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        articleIDs: [UUID],
        sourceContentHash: String,
        modelKind: IntelligenceModelKind,
        promptVersion: Int,
        outputLanguageCode: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.articleIDs = articleIDs
        self.sourceContentHash = sourceContentHash
        self.modelKindRawValue = modelKind.rawValue
        self.promptVersion = promptVersion
        self.outputLanguageCode = outputLanguageCode
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
    public let irrelevantBlockIDs: [Int]
    public let modelKind: IntelligenceModelKind
    public let isCached: Bool

    public init(
        text: String,
        keyPoints: [String] = [],
        topics: [String] = [],
        irrelevantBlockIDs: [Int] = [],
        modelKind: IntelligenceModelKind,
        isCached: Bool
    ) {
        self.text = text
        self.keyPoints = keyPoints
        self.topics = topics
        self.irrelevantBlockIDs = irrelevantBlockIDs
        self.modelKind = modelKind
        self.isCached = isCached
    }
}
