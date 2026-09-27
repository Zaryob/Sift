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

public enum StoryClusteringCandidateDecision: String, Codable, Sendable {
    case accepted
    case rejectedCentroidSimilarity
    case rejectedActionMismatch
    case rejectedRepresentativeSimilarity
    case rejectedRecentMemberSupport
}

/// Compact, text-free evidence for why a nearby event cluster was accepted or rejected.
public struct StoryClusteringCandidateDiagnostic: Codable, Sendable {
    public let candidateClusterID: String
    public let centroidSimilarity: Double?
    public let representativeSimilarity: Double?
    public let recentMemberSupport: Double?
    public let actionsCompatible: Bool
    public let candidateActionTerms: [String]
    public let representativeActionTerms: [String]
    public let decision: StoryClusteringCandidateDecision
    public let selected: Bool
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
    /// Up to ten nearest candidate events, including the selected one when assigned.
    public let candidateDiagnostics: [StoryClusteringCandidateDiagnostic]
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
    public static let pipelineVersion = "m0-spike-7"
    private static let assignmentPolicy = "60% article-body + 40% headline embedding; centroid threshold + representative/recent-vector support (0.055 slack) + headline-action boundary (0.985 near-identity override); top-ten candidate trace"
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

    private struct CandidateEvaluation {
        let index: Int
        let centroidSimilarity: Double
        let diagnostic: StoryClusteringCandidateDiagnostic
    }

    private enum TranslationField {
        case text
        case title
    }

    private struct TranslationWork {
        let articleID: UUID
        let field: TranslationField
        let request: TranslationSession.Request
    }

    private struct PreparedArticle {
        let article: StoryClusteringArticle
        let startedAt: ContinuousClock.Instant
        let sourceText: String
        let sourceContext: String
        let detectedLanguage: String?
        var normalizedText: String?
        var normalizedTitle: String?
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
            let sourceContext = Self.analysisContext(for: article)
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
                sourceContext: sourceContext,
                detectedLanguage: detectedLanguage,
                normalizedText: needsTranslation || failure != nil ? nil : sourceContext,
                normalizedTitle: needsTranslation || failure != nil ? nil : article.title,
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
                let work = chunk.flatMap { articleID -> [TranslationWork] in
                    guard let prepared = preparedByID[articleID] else { return [] }
                    return [
                        TranslationWork(
                            articleID: articleID,
                            field: .text,
                            request: TranslationSession.Request(
                                sourceText: prepared.sourceContext,
                                clientIdentifier: "text:\(articleID.uuidString)"
                            )
                        ),
                        TranslationWork(
                            articleID: articleID,
                            field: .title,
                            request: TranslationSession.Request(
                                sourceText: prepared.article.title,
                                clientIdentifier: "title:\(articleID.uuidString)"
                            )
                        )
                    ]
                }
                do {
                    let responses = try await session.translations(from: work.map(\.request))
                    for (request, response) in zip(work, responses) {
                        switch request.field {
                        case .text:
                            preparedByID[request.articleID]?.normalizedText = response.targetText
                        case .title:
                            preparedByID[request.articleID]?.normalizedTitle = response.targetText
                        }
                        preparedByID[request.articleID]?.translationReadiness = "installed"
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
                    startedAt: prepared.startedAt,
                    candidateDiagnostics: []
                ))
                continue
            }
            guard let normalizedContext = prepared.normalizedText,
                  let detectedLanguage = prepared.detectedLanguage else { continue }
            let normalizedTitle = prepared.normalizedTitle ?? article.title
            let eventActionTerms = Self.eventActionTerms(in: normalizedTitle)

            let vector = Self.articleVector(
                title: normalizedTitle,
                context: normalizedContext,
                language: targetNaturalLanguage,
                model: model
            )
            guard let vector else {
                assignments.append(Self.assignment(
                    article: article,
                    clusterID: nil,
                    language: detectedLanguage,
                    translationReadiness: prepared.translationReadiness,
                    readiness: .embeddingUnavailable,
                    similarity: nil,
                    publisherCount: 0,
                    startedAt: prepared.startedAt,
                    candidateDiagnostics: []
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
            let candidateEvaluations = clusters.enumerated().map { index, cluster in
                Self.evaluateCandidate(
                    vector,
                    cluster: cluster,
                    threshold: similarityThreshold,
                    candidateActionTerms: eventActionTerms,
                    index: index
                )
            }
            let best = candidateEvaluations
                .filter { $0.diagnostic.decision == .accepted }
                .max { $0.centroidSimilarity < $1.centroidSimilarity }
            let candidateDiagnostics = Self.nearestCandidateDiagnostics(
                candidateEvaluations,
                selectedIndex: best?.index
            )

            let clusterID: String
            let similarity: Double?
            let clusterIndex: Int
            if let best {
                clusterIndex = best.index
                clusterID = clusters[clusterIndex].id
                similarity = best.centroidSimilarity
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
                similarity = candidateEvaluations
                    .max { ($0.diagnostic.centroidSimilarity ?? -1) < ($1.diagnostic.centroidSimilarity ?? -1) }?
                    .diagnostic.centroidSimilarity
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
                startedAt: prepared.startedAt,
                candidateDiagnostics: candidateDiagnostics
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
    private static func evaluateCandidate(
        _ vector: [Double],
        cluster: CandidateCluster,
        threshold: Double,
        candidateActionTerms: Set<String>,
        index: Int
    ) -> CandidateEvaluation {
        let centroid = cosineSimilarity(vector, cluster.centroid)
        let representative = cosineSimilarity(vector, cluster.representativeVector)
        let recent = cluster.recentMemberVectors.suffix(3).compactMap {
            cosineSimilarity(vector, $0)
        }
        let recentSupport = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        let actionMismatch = !candidateActionTerms.isEmpty
            && !cluster.representativeActionTerms.isEmpty
            && candidateActionTerms.isDisjoint(with: cluster.representativeActionTerms)
        let actionOverrideApplies = (representative ?? -1) >= actionMismatchOverrideSimilarity

        let decision: StoryClusteringCandidateDecision
        if centroid == nil || centroid! < threshold {
            decision = .rejectedCentroidSimilarity
        } else if actionMismatch && !actionOverrideApplies {
            decision = .rejectedActionMismatch
        } else if representative == nil || representative! < threshold - cohesionSlack {
            decision = .rejectedRepresentativeSimilarity
        } else if recentSupport == nil || recentSupport! < threshold - cohesionSlack {
            decision = .rejectedRecentMemberSupport
        } else {
            decision = .accepted
        }

        return CandidateEvaluation(
            index: index,
            centroidSimilarity: centroid ?? -1,
            diagnostic: StoryClusteringCandidateDiagnostic(
                candidateClusterID: cluster.id,
                centroidSimilarity: centroid,
                representativeSimilarity: representative,
                recentMemberSupport: recentSupport,
                actionsCompatible: !actionMismatch || actionOverrideApplies,
                candidateActionTerms: candidateActionTerms.sorted(),
                representativeActionTerms: cluster.representativeActionTerms.sorted(),
                decision: decision,
                selected: false
            )
        )
    }

    private static func nearestCandidateDiagnostics(
        _ evaluations: [CandidateEvaluation],
        selectedIndex: Int?
    ) -> [StoryClusteringCandidateDiagnostic] {
        let nearest = evaluations
            .sorted { $0.centroidSimilarity > $1.centroidSimilarity }
            .prefix(10)
        var result = nearest.map { evaluation in
            StoryClusteringCandidateDiagnostic(
                candidateClusterID: evaluation.diagnostic.candidateClusterID,
                centroidSimilarity: evaluation.diagnostic.centroidSimilarity,
                representativeSimilarity: evaluation.diagnostic.representativeSimilarity,
                recentMemberSupport: evaluation.diagnostic.recentMemberSupport,
                actionsCompatible: evaluation.diagnostic.actionsCompatible,
                candidateActionTerms: evaluation.diagnostic.candidateActionTerms,
                representativeActionTerms: evaluation.diagnostic.representativeActionTerms,
                decision: evaluation.diagnostic.decision,
                selected: evaluation.index == selectedIndex
            )
        }
        if let selectedIndex,
           !nearest.contains(where: { $0.index == selectedIndex }),
           let selected = evaluations.first(where: { $0.index == selectedIndex }) {
            result.append(StoryClusteringCandidateDiagnostic(
                candidateClusterID: selected.diagnostic.candidateClusterID,
                centroidSimilarity: selected.diagnostic.centroidSimilarity,
                representativeSimilarity: selected.diagnostic.representativeSimilarity,
                recentMemberSupport: selected.diagnostic.recentMemberSupport,
                actionsCompatible: selected.diagnostic.actionsCompatible,
                candidateActionTerms: selected.diagnostic.candidateActionTerms,
                representativeActionTerms: selected.diagnostic.representativeActionTerms,
                decision: selected.diagnostic.decision,
                selected: true
            ))
        }
        return result
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
        title: String,
        context: String?,
        language: NLLanguage,
        model: NLContextualEmbedding
    ) -> [Double]? {
        guard let titleVector = meanPooledVector(
            for: title,
            language: language,
            model: model
        ) else { return nil }

        guard let context,
              !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let contextVector = meanPooledVector(
                  for: String(context.prefix(4_000)),
                  language: language,
                  model: model
              ),
              let normalizedTitle = unitVector(titleVector),
              let normalizedContext = unitVector(contextVector) else {
            return titleVector
        }

        // The article body is the primary account; the headline is a useful event
        // cue, but must not drown out detail and context in the article itself.
        return zip(normalizedTitle, normalizedContext).map { ($0 * 0.4) + ($1 * 0.6) }
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

    private static func analysisContext(for article: StoryClusteringArticle) -> String {
        let parts = [article.fullText, article.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return String((parts.first ?? article.title).prefix(12_000))
    }

    private static func assignment(
        article: StoryClusteringArticle,
        clusterID: String?,
        language: String?,
        translationReadiness: String,
        readiness: StoryClusteringReadiness,
        similarity: Double?,
        publisherCount: Int,
        startedAt: ContinuousClock.Instant,
        candidateDiagnostics: [StoryClusteringCandidateDiagnostic] = []
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
            processingMilliseconds: milliseconds,
            candidateDiagnostics: candidateDiagnostics
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
                    startedAt: .now,
                    candidateDiagnostics: []
                )
            },
            assignmentPolicy: Self.assignmentPolicy
        )
    }
}
