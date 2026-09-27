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
    /// Versioned description of the event-boundary and cluster-cohesion policy.
    public let assignmentPolicy: String
}

/// Runs a reproducible, on-device clustering experiment over caller-provided articles.
/// Cross-language items are translated only when Apple's Translation framework reports
/// the exact language pair as installed. Unsupported pairs remain unassigned.
public actor StoryClusteringSpike {
    public static let pipelineVersion = "m0-spike-4"
    private static let assignmentPolicy = "centroid threshold + representative/recent-vector support (0.055 slack) + normalized-title action boundary (0.985 near-identity override); event-level clusters only"
    private static let cohesionSlack = 0.055
    private static let actionMismatchOverrideSimilarity = 0.985
    private static let maximumRetainedMemberVectors = 12

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
        var representativeVector: [Double]
        var representativeActionTerms: Set<String>
        var recentMemberVectors: [[Double]]
        var memberCount: Int
        var publisherKeys: Set<String>
        var lastUpdatedAt: Date
    }

    private struct PreparedArticle {
        let article: StoryClusteringArticle
        let startedAt: ContinuousClock.Instant
        let sourceText: String
        let detectedLanguage: String?
        var normalizedText: String?
        var translationReadiness: String
        var failure: StoryClusteringReadiness?
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

        let sortedArticles = articles.sorted(by: {
            if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.publishedAt < $1.publishedAt
        })
        var preparedByID: [UUID: PreparedArticle] = [:]
        var translationGroups: [String: [UUID]] = [:]

        for article in sortedArticles {
            let start = ContinuousClock.now
            let sourceText = Self.analysisText(for: article)
            let wordCount = sourceText.split(whereSeparator: \.isWhitespace).count
            let detectedLanguage = wordCount >= 8 ? Self.detectLanguage(in: sourceText) : nil
            let failure: StoryClusteringReadiness? = wordCount < 8
                ? .insufficientText
                : (detectedLanguage == nil ? .unsupportedLanguage : nil)
            let needsTranslation = detectedLanguage != nil && detectedLanguage != analysisLocale
            preparedByID[article.id] = PreparedArticle(
                article: article,
                startedAt: start,
                sourceText: sourceText,
                detectedLanguage: detectedLanguage,
                normalizedText: needsTranslation || failure != nil ? nil : sourceText,
                translationReadiness: needsTranslation ? "pending" : (failure == nil ? "notNeeded" : "unsupported"),
                failure: failure
            )
            if let detectedLanguage, needsTranslation {
                translationGroups[detectedLanguage, default: []].append(article.id)
            }
        }

        let availability = LanguageAvailability()
        for sourceLanguageCode in translationGroups.keys.sorted() {
            let articleIDs = translationGroups[sourceLanguageCode] ?? []
            let sourceLanguage = Locale.Language(identifier: sourceLanguageCode)
            let status = await availability.status(from: sourceLanguage, to: targetLanguage)
            guard status == .installed else {
                let readiness: StoryClusteringReadiness = status == .supported
                    ? .translationNotInstalled
                    : .unsupportedLanguage
                for articleID in articleIDs {
                    preparedByID[articleID]?.translationReadiness = status == .supported
                        ? "waitingForAsset"
                        : "unsupported"
                    preparedByID[articleID]?.failure = readiness
                }
                continue
            }

            let session = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: translationStrategy.frameworkValue
            )
            // TranslationSession can translate many same-language requests in one
            // batch. Keep chunks bounded so a large feed cannot create one huge
            // request while still amortizing session and framework overhead.
            for chunkStart in stride(from: 0, to: articleIDs.count, by: 12) {
                let chunk = Array(articleIDs[chunkStart..<min(chunkStart + 12, articleIDs.count)])
                let requests = chunk.compactMap { articleID -> TranslationSession.Request? in
                    guard let prepared = preparedByID[articleID] else { return nil }
                    return TranslationSession.Request(
                        sourceText: prepared.sourceText,
                        clientIdentifier: articleID.uuidString
                    )
                }
                do {
                    let responses = try await session.translations(from: requests)
                    for (articleID, response) in zip(chunk, responses) {
                        preparedByID[articleID]?.normalizedText = response.targetText
                        preparedByID[articleID]?.translationReadiness = "installed"
                    }
                } catch {
                    for articleID in chunk {
                        preparedByID[articleID]?.translationReadiness = "installed"
                        preparedByID[articleID]?.failure = .processingFailed
                    }
                }
            }
        }

        var clusters: [CandidateCluster] = []
        var assignments: [StoryClusteringAssignment] = []

        for article in sortedArticles {
            guard let prepared = preparedByID[article.id] else { continue }
            if let failure = prepared.failure {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: prepared.detectedLanguage,
                    translationReadiness: prepared.translationReadiness,
                    readiness: failure,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: prepared.startedAt
                ))
                continue
            }
            guard let normalizedText = prepared.normalizedText,
                  let detectedLanguage = prepared.detectedLanguage else { continue }
            let normalizedTitle = Self.normalizedTitle(from: normalizedText)
            let eventActionTerms = Self.eventActionTerms(in: normalizedTitle)

            let vector: [Double]?
            if detectedLanguage == analysisLocale {
                vector = Self.articleVector(
                    for: article,
                    language: targetNaturalLanguage,
                    model: model
                )
            } else {
                vector = Self.meanPooledVector(
                    for: normalizedText,
                    language: targetNaturalLanguage,
                    model: model
                )
            }
            guard let vector else {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: detectedLanguage,
                    translationReadiness: prepared.translationReadiness,
                    readiness: .embeddingUnavailable,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: prepared.startedAt
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
                guard let similarity = Self.clusterCohesionSimilarity(
                    vector,
                    cluster: cluster,
                    threshold: similarityThreshold,
                    candidateActionTerms: eventActionTerms
                ) else { return nil }
                return (index, similarity)
            }.max { $0.1 < $1.1 }

            let clusterID: String
            let similarity: Double?
            let clusterIndex: Int
            if let best {
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
                clusters[clusterIndex].recentMemberVectors.append(vector)
                if clusters[clusterIndex].recentMemberVectors.count > Self.maximumRetainedMemberVectors {
                    clusters[clusterIndex].recentMemberVectors.removeFirst(
                        clusters[clusterIndex].recentMemberVectors.count - Self.maximumRetainedMemberVectors
                    )
                }
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
                    representativeVector: vector,
                    representativeActionTerms: eventActionTerms,
                    recentMemberVectors: [vector],
                    memberCount: 1,
                    publisherKeys: [article.publisherKey],
                    lastUpdatedAt: article.publishedAt
                ))
            }

            assignments.append(Self.assignment(
                article: article,
                clusterID: clusterID,
                language: prepared.detectedLanguage,
                translationReadiness: prepared.translationReadiness,
                readiness: .ready,
                similarity: similarity,
                publisherCount: clusters[clusterIndex].publisherKeys.count,
                startedAt: prepared.startedAt
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
            assignments: assignments,
            assignmentPolicy: Self.assignmentPolicy
        )
    }

    /// A single centroid match is insufficient: a broad issue centroid can drift
    /// toward multiple distinct events. Require support from the original event
    /// representative and the best recent members as well as the running centroid.
    /// The reported score is the centroid cosine; the configured threshold applies
    /// to it without slack.
    private static func clusterCohesionSimilarity(
        _ vector: [Double],
        cluster: CandidateCluster,
        threshold: Double,
        candidateActionTerms: Set<String>
    ) -> Double? {
        guard let centroid = cosineSimilarity(vector, cluster.centroid),
              let representative = cosineSimilarity(vector, cluster.representativeVector),
              centroid >= threshold,
              representative >= threshold - cohesionSlack else { return nil }

        // Sharing the same people, organization, or broad subject is not enough to
        // merge distinct developments. Disjoint headline actions block a normal
        // semantic match; allow only near-identical representative matches so
        // paraphrased reports of one event do not fragment unnecessarily.
        if !candidateActionTerms.isEmpty,
           !cluster.representativeActionTerms.isEmpty,
           candidateActionTerms.isDisjoint(with: cluster.representativeActionTerms),
           representative < actionMismatchOverrideSimilarity {
            return nil
        }

        let recent = cluster.recentMemberVectors.suffix(3).compactMap {
            cosineSimilarity(vector, $0)
        }
        guard !recent.isEmpty else { return nil }
        let recentSupport = recent.reduce(0, +) / Double(recent.count)
        guard recentSupport >= threshold - cohesionSlack else { return nil }
        // Preserve the configured centroid threshold. The small cohesion tolerance
        // only allows individual paraphrases to differ slightly from the threshold.
        return centroid
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

    private static func detectLanguage(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private static func normalizedTitle(from normalizedText: String) -> String {
        String(normalizedText.split(separator: "\n", maxSplits: 1).first ?? Substring(normalizedText))
    }

    private static func eventActionTerms(in title: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = title
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var terms = Set<String>()
        tagger.enumerateTags(
            in: title.startIndex..<title.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { lexicalClass, range in
            guard lexicalClass == .verb else { return true }
            let token = String(title[range])
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? token
            terms.insert(lemma.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ))
            return true
        }
        return terms
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
            },
            assignmentPolicy: Self.assignmentPolicy
        )
    }
}
