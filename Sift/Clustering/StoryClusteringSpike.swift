import Foundation
import NaturalLanguage
import Translation

/// Input and output types for the M0 feasibility spike. This deliberately does not
/// mutate SwiftData or change the shipped article-list experience.
public struct StoryClusteringArticle: Codable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let summary: String?
    public let fullText: String?
    public let publisherKey: String
    public let publishedAt: Date

    public init(
        id: UUID,
        title: String,
        summary: String? = nil,
        fullText: String? = nil,
        publisherKey: String,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.fullText = fullText
        self.publisherKey = publisherKey
        self.publishedAt = publishedAt
    }
}

public enum StoryClusteringReadiness: String, Codable, Sendable {
    case ready
    case insufficientText
    case unsupportedLanguage
    case translationNotInstalled
    case embeddingUnavailable
    case processingFailed
}

public struct StoryClusteringAssignment: Codable, Identifiable, Sendable {
    public let id: UUID
    public let predictedClusterID: String?
    public let detectedLanguage: String?
    public let translationReadiness: String
    public let readiness: StoryClusteringReadiness
    public let similarity: Double?
    public let publisherCount: Int
    public let processingMilliseconds: Double
}

public struct StoryClusteringSpikeResult: Codable, Sendable {
    public let analysisPipelineVersion: String
    public let analysisLocale: String
    public let embeddingModelIdentifier: String
    public let embeddingModelRevision: Int
    public let translationStrategy: String
    public let candidateWindowHours: Double
    public let similarityThreshold: Double
    public let assignments: [StoryClusteringAssignment]
}

/// Runs a reproducible, on-device clustering experiment over caller-provided articles.
/// Cross-language items are translated only when Apple's Translation framework reports
/// the exact language pair as installed. Unsupported pairs remain unassigned.
public actor StoryClusteringSpike {
    public static let pipelineVersion = "m0-spike-2"

    public enum TranslationStrategy: String, Sendable {
        case lowLatency
        case highFidelity

        fileprivate var frameworkValue: TranslationSession.Strategy {
            switch self {
            case .lowLatency: .lowLatency
            case .highFidelity: .highFidelity
            }
        }
    }

    private struct CandidateCluster {
        let id: String
        var centroid: [Double]
        var memberCount: Int
        var publisherKeys: Set<String>
        var lastUpdatedAt: Date
    }

    public init() {}

    public func cluster(
        _ articles: [StoryClusteringArticle],
        analysisLocale: String = "en",
        similarityThreshold: Double,
        candidateWindow: TimeInterval = 72 * 60 * 60,
        translationStrategy: TranslationStrategy = .highFidelity
    ) async -> StoryClusteringSpikeResult {
        let targetLanguage = Locale.Language(identifier: analysisLocale)
        let targetNaturalLanguage = NLLanguage(rawValue: analysisLocale)
        let model = NLContextualEmbedding(language: targetNaturalLanguage)
        guard let model else {
            return emptyResult(
                articles,
                locale: analysisLocale,
                modelIdentifier: "unavailable",
                revision: 0,
                threshold: similarityThreshold,
                candidateWindow: candidateWindow,
                translationStrategy: translationStrategy
            )
        }

        if !model.hasAvailableAssets {
            guard (try? await model.requestAssets()) == .available else {
                return emptyResult(
                    articles,
                    locale: analysisLocale,
                    modelIdentifier: model.modelIdentifier,
                    revision: model.revision,
                    threshold: similarityThreshold,
                    candidateWindow: candidateWindow,
                    translationStrategy: translationStrategy
                )
            }
        }

        guard (try? model.load()) != nil else {
            return emptyResult(
                articles,
                locale: analysisLocale,
                modelIdentifier: model.modelIdentifier,
                revision: model.revision,
                threshold: similarityThreshold,
                candidateWindow: candidateWindow,
                translationStrategy: translationStrategy
            )
        }
        defer { model.unload() }

        var clusters: [CandidateCluster] = []
        var assignments: [StoryClusteringAssignment] = []

        for article in articles.sorted(by: {
            if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.publishedAt < $1.publishedAt
        }) {
            let start = ContinuousClock.now
            let sourceText = Self.analysisText(for: article)
            guard sourceText.split(whereSeparator: \.isWhitespace).count >= 8 else {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: nil,
                    translationReadiness: "notAttempted",
                    readiness: .insufficientText,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: start
                ))
                continue
            }

            let detectedLanguage = Self.detectLanguage(in: sourceText)
            guard let detectedLanguage else {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: nil,
                    translationReadiness: "unsupported",
                    readiness: .unsupportedLanguage,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: start
                ))
                continue
            }

            let normalized: (text: String, readiness: String, failure: StoryClusteringReadiness?)
            if detectedLanguage == analysisLocale {
                normalized = (sourceText, "notNeeded", nil)
            } else {
                normalized = await translateIfInstalled(
                    sourceText,
                    sourceLanguage: Locale.Language(identifier: detectedLanguage),
                    targetLanguage: targetLanguage,
                    strategy: translationStrategy
                )
            }

            if let failure = normalized.failure {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: detectedLanguage,
                    translationReadiness: normalized.readiness,
                    readiness: failure,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: start
                ))
                continue
            }

            let vector: [Double]?
            if detectedLanguage == analysisLocale {
                vector = Self.articleVector(
                    for: article,
                    language: targetNaturalLanguage,
                    model: model
                )
            } else {
                vector = Self.meanPooledVector(
                    for: normalized.text,
                    language: targetNaturalLanguage,
                    model: model
                )
            }
            guard let vector else {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: detectedLanguage,
                    translationReadiness: normalized.readiness,
                    readiness: .embeddingUnavailable,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: start
                ))
                continue
            }

            // Replay the corpus as a timeline. Using wall-clock `now` here would
            // expire every historical cluster when evaluating a past corpus.
            clusters.removeAll {
                Self.isOutsideCandidateWindow(
                    articleTime: article.publishedAt,
                    clusterTime: $0.lastUpdatedAt,
                    candidateWindow: candidateWindow
                )
            }
            let best = clusters.enumerated().compactMap { index, cluster -> (Int, Double)? in
                guard let similarity = Self.cosineSimilarity(vector, cluster.centroid) else { return nil }
                return (index, similarity)
            }.max { $0.1 < $1.1 }

            let clusterID: String
            let similarity: Double?
            let clusterIndex: Int
            if let best, best.1 >= similarityThreshold {
                clusterIndex = best.0
                clusterID = clusters[clusterIndex].id
                similarity = best.1
                let old = clusters[clusterIndex]
                let nextCount = old.memberCount + 1
                clusters[clusterIndex].centroid = Self.runningMean(
                    old.centroid,
                    vector,
                    existingCount: old.memberCount
                )
                clusters[clusterIndex].memberCount = nextCount
                clusters[clusterIndex].publisherKeys.insert(article.publisherKey)
                clusters[clusterIndex].lastUpdatedAt = article.publishedAt
            } else {
                clusterID = "story-\(article.id.uuidString.lowercased())"
                clusterIndex = clusters.count
                similarity = best?.1
                clusters.append(CandidateCluster(
                    id: clusterID,
                    centroid: vector,
                    memberCount: 1,
                    publisherKeys: [article.publisherKey],
                    lastUpdatedAt: article.publishedAt
                ))
            }

            assignments.append(Self.assignment(
                article: article,
                clusterID: clusterID,
                language: detectedLanguage,
                translationReadiness: normalized.readiness,
                readiness: .ready,
                similarity: similarity,
                publisherCount: clusters[clusterIndex].publisherKeys.count,
                startedAt: start
            ))
        }

        return StoryClusteringSpikeResult(
            analysisPipelineVersion: Self.pipelineVersion,
            analysisLocale: analysisLocale,
            embeddingModelIdentifier: model.modelIdentifier,
            embeddingModelRevision: model.revision,
            translationStrategy: translationStrategy.rawValue,
            candidateWindowHours: candidateWindow / 3600,
            similarityThreshold: similarityThreshold,
            assignments: assignments
        )
    }

    public static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        let dot = zip(lhs, rhs).reduce(0.0) { $0 + $1.0 * $1.1 }
        let leftMagnitude = sqrt(lhs.reduce(0.0) { $0 + $1 * $1 })
        let rightMagnitude = sqrt(rhs.reduce(0.0) { $0 + $1 * $1 })
        guard leftMagnitude > 0, rightMagnitude > 0 else { return nil }
        return dot / (leftMagnitude * rightMagnitude)
    }

    public static func meanPooledVector(
        for text: String,
        language: NLLanguage,
        model: NLContextualEmbedding
    ) -> [Double]? {
        guard let result = try? model.embeddingResult(for: text, language: language) else { return nil }
        var sums = [Double](repeating: 0, count: model.dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) { vector, _ in
            guard vector.count == sums.count else { return true }
            for index in sums.indices {
                sums[index] += vector[index]
            }
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { return nil }
        return sums.map { $0 / Double(tokenCount) }
    }

    private static func articleVector(
        for article: StoryClusteringArticle,
        language: NLLanguage,
        model: NLContextualEmbedding
    ) -> [Double]? {
        guard let titleVector = meanPooledVector(
            for: article.title,
            language: language,
            model: model
        ) else { return nil }

        let context = [article.summary, article.fullText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let context,
              let contextVector = meanPooledVector(
                  for: String(context.prefix(2_000)),
                  language: language,
                  model: model
              ),
              let normalizedTitle = unitVector(titleVector),
              let normalizedContext = unitVector(contextVector) else {
            return titleVector
        }

        // Feed excerpts often contain generic background that drowns out the event
        // named in the headline. Give the title the larger share of the article vector.
        return zip(normalizedTitle, normalizedContext).map { ($0 * 0.7) + ($1 * 0.3) }
    }

    private static func unitVector(_ vector: [Double]) -> [Double]? {
        let magnitude = sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }

    public static func runningMean(
        _ existing: [Double],
        _ next: [Double],
        existingCount: Int
    ) -> [Double] {
        guard existing.count == next.count, existingCount > 0 else { return next }
        let denominator = Double(existingCount + 1)
        return zip(existing, next).map { ($0 * Double(existingCount) + $1) / denominator }
    }

    public static func isOutsideCandidateWindow(
        articleTime: Date,
        clusterTime: Date,
        candidateWindow: TimeInterval
    ) -> Bool {
        articleTime.timeIntervalSince(clusterTime) > candidateWindow
    }

    private func translateIfInstalled(
        _ text: String,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        strategy: TranslationStrategy
    ) async -> (text: String, readiness: String, failure: StoryClusteringReadiness?) {
        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: targetLanguage)
        guard status == .installed else {
            return (
                text,
                status == .supported ? "waitingForAsset" : "unsupported",
                status == .supported ? .translationNotInstalled : .unsupportedLanguage
            )
        }

        do {
            let session = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: strategy.frameworkValue
            )
            return (try await session.translate(text).targetText, "installed", nil)
        } catch {
            return (text, "installed", .processingFailed)
        }
    }

    private static func detectLanguage(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func analysisText(for article: StoryClusteringArticle) -> String {
        let parts = [article.title, article.summary, article.fullText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return String(parts.joined(separator: "\n\n").prefix(12_000))
    }

    private static func assignment(
        article: StoryClusteringArticle,
        clusterID: String?,
        language: String?,
        translationReadiness: String,
        readiness: StoryClusteringReadiness,
        similarity: Double?,
        publisherCount: Int,
        startedAt: ContinuousClock.Instant
    ) -> StoryClusteringAssignment {
        let elapsed = startedAt.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        return StoryClusteringAssignment(
            id: article.id,
            predictedClusterID: clusterID,
            detectedLanguage: language,
            translationReadiness: translationReadiness,
            readiness: readiness,
            similarity: similarity,
            publisherCount: publisherCount,
            processingMilliseconds: milliseconds
        )
    }

    private func emptyResult(
        _ articles: [StoryClusteringArticle],
        locale: String,
        modelIdentifier: String,
        revision: Int,
        threshold: Double,
        candidateWindow: TimeInterval,
        translationStrategy: TranslationStrategy
    ) -> StoryClusteringSpikeResult {
        StoryClusteringSpikeResult(
            analysisPipelineVersion: Self.pipelineVersion,
            analysisLocale: locale,
            embeddingModelIdentifier: modelIdentifier,
            embeddingModelRevision: revision,
            translationStrategy: translationStrategy.rawValue,
            candidateWindowHours: candidateWindow / 3600,
            similarityThreshold: threshold,
            assignments: articles.map {
                Self.assignment(
                    article: $0,
                    clusterID: nil,
                    language: nil,
                    translationReadiness: "notAvailable",
                    readiness: .embeddingUnavailable,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: .now
                )
            }
        )
    }
}
