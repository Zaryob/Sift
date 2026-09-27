import Foundation
import Combine
import CryptoKit
import SwiftData
#if canImport(FoundationModels)
import FoundationModels

@Generable
private struct GeneratedArticleDigest {
    @Guide(description: "A factual two-to-three sentence summary written for listening.")
    let summary: String

    @Guide(description: "The most important factual takeaways.", .maximumCount(3))
    let keyPoints: [String]

    @Guide(description: "Short topic labels for the article.", .maximumCount(4))
    let topics: [String]
}
#endif

/// Generates and persistently caches Apple Intelligence summaries and spoken briefings.
@MainActor
public final class ArticleIntelligenceService: ObservableObject {
    public static let shared = ArticleIntelligenceService()

    @Published public private(set) var isGenerating: Bool = false
    @Published public private(set) var activeModelKind: IntelligenceModelKind?
    @Published public private(set) var latestBriefing: String?

    private static let articlePromptVersion = 2
    private static let briefingPromptVersion = 1

    private init() {}

    public func summarize(article: FeedItem, context: ModelContext) async -> IntelligenceOutput {
        let content = preferredContent(for: article)
        let contentHash = Self.contentHash(title: article.title, content: content)

        // A persisted result is authoritative for this prompt version. Full-text extraction
        // or feed refreshes must not trigger another model request for the same article.
        if let cached = article.intelligenceResults
            .filter({ $0.promptVersion == Self.articlePromptVersion })
            .max(by: { $0.generatedAt < $1.generatedAt }) {
            return IntelligenceOutput(
                text: cached.summary,
                keyPoints: cached.keyPoints ?? [],
                topics: cached.topics ?? [],
                modelKind: cached.modelKind,
                isCached: true
            )
        }

        let generated = await generateSummary(title: article.title, content: content)
        let result = ArticleIntelligenceResult(
            summary: generated.text,
            keyPoints: generated.keyPoints,
            topics: generated.topics,
            modelKind: generated.modelKind,
            sourceContentHash: contentHash,
            promptVersion: Self.articlePromptVersion,
            article: article
        )
        context.insert(result)
        try? context.save()
        return generated
    }

    /// Compatibility path for callers that don't have a persisted article.
    public func summarize(title: String, content: String) async -> String {
        await generateSummary(title: title, content: content).text
    }

    public func generateBriefing(
        from items: [FeedItem],
        context: ModelContext,
        forceRefresh: Bool = false
    ) async -> IntelligenceOutput {
        guard !items.isEmpty else {
            return IntelligenceOutput(
                text: String(localized: "You are all caught up. There are no unread articles in Sift."),
                modelKind: .extractiveFallback,
                isCached: false
            )
        }

        isGenerating = true
        defer { isGenerating = false }

        let topItems = Array(items.prefix(5))

        // Pre-fetch missing content for any unread article that only has an excerpt
        await downloadMissingContentIfNeeded(for: topItems, context: context)

        let briefingHash = Self.briefingHash(for: topItems)
        let promptVersion = Self.briefingPromptVersion
        var descriptor = FetchDescriptor<SavedBriefing>(
            predicate: #Predicate {
                $0.sourceContentHash == briefingHash &&
                $0.promptVersion == promptVersion
            },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let cachedBriefing = (try? context.fetch(descriptor))?.first
        if let cachedBriefing, !forceRefresh {
            latestBriefing = cachedBriefing.text
            return IntelligenceOutput(
                text: cachedBriefing.text,
                modelKind: cachedBriefing.modelKind,
                isCached: true
            )
        }

        var contextText = ""
        for (index, item) in topItems.enumerated() {
            let feedTitle = item.feed?.title ?? "Unknown source"
            let source = preferredContent(for: item)
            contextText += """
            
            Story \(index + 1) from \(feedTitle):
            Title: \(item.title)
            Excerpt: \(source.prefix(1000))
            """
        }

        let prompt = """
        Create a 60-to-90 second spoken news briefing covering the following top stories.
        Begin with a warm greeting like "Here is your Sift briefing for today."
        Smoothly transition between stories like a professional radio anchor.
        Use only facts present in the supplied stories and preserve source attribution.
        Conclude with a brief closing sentence.

        Stories:
        \(contextText)
        """

        let generated: IntelligenceOutput
        #if canImport(FoundationModels)
        if let modelOutput = await generateModelResponse(to: prompt) {
            generated = modelOutput
        } else {
            generated = IntelligenceOutput(
                text: fallbackBriefing(topItems: topItems),
                modelKind: .extractiveFallback,
                isCached: false
            )
        }
        #else
        generated = IntelligenceOutput(
            text: fallbackBriefing(topItems: topItems),
            modelKind: .extractiveFallback,
            isCached: false
        )
        #endif

        if let cachedBriefing {
            cachedBriefing.text = generated.text
            cachedBriefing.articleIDs = topItems.map(\.id)
            cachedBriefing.modelKindRawValue = generated.modelKind.rawValue
            cachedBriefing.generatedAt = Date()
        } else {
            let saved = SavedBriefing(
                text: generated.text,
                articleIDs: topItems.map(\.id),
                sourceContentHash: briefingHash,
                modelKind: generated.modelKind,
                promptVersion: Self.briefingPromptVersion
            )
            context.insert(saved)
        }
        try? context.save()
        latestBriefing = generated.text
        return generated
    }

    public func generateBriefing(from items: [FeedItem]) async -> String {
        let context = ModelContext(PersistenceController.shared.container)
        return await generateBriefing(from: items, context: context).text
    }

    public func generateBriefingForUnreadArticles(
        context: ModelContext,
        forceRefresh: Bool = false
    ) async -> IntelligenceOutput {
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate<FeedItem> { !$0.isRead },
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
        )
        descriptor.fetchLimit = 5

        do {
            let items = try context.fetch(descriptor)
            return await generateBriefing(
                from: items,
                context: context,
                forceRefresh: forceRefresh
            )
        } catch {
            return IntelligenceOutput(
                text: String(localized: "Unable to retrieve unread articles from your Sift library."),
                modelKind: .extractiveFallback,
                isCached: false
            )
        }
    }

    public func generateBriefingForUnreadArticles() async -> String {
        let context = ModelContext(PersistenceController.shared.container)
        return await generateBriefingForUnreadArticles(context: context).text
    }

    public func summarizeLatestUnreadArticle() async -> String {
        let context = ModelContext(PersistenceController.shared.container)
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate<FeedItem> { !$0.isRead },
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            guard let item = try context.fetch(descriptor).first else {
                return String(localized: "You have no unread articles in Sift.")
            }
            await downloadMissingContentIfNeeded(for: [item], context: context)
            return await summarize(article: item, context: context).text
        } catch {
            return String(localized: "Unable to load article.")
        }
    }

    /// Concurrently downloads full article content from the web for unread posts that currently only have excerpts.
    private func downloadMissingContentIfNeeded(for items: [FeedItem], context: ModelContext) async {
        await withTaskGroup(of: (UUID, ExtractedArticle)?.self) { group in
            for item in items {
                if item.extractedArticleData == nil, item.feedWordCount < 400,
                   let link = item.link, let url = URL(string: link) {
                    let id = item.id
                    let summary = item.summary ?? item.content
                    group.addTask {
                        if let extracted = try? await ArticleExtractor.fetch(url: url, summary: summary) {
                            return (id, extracted)
                        }
                        return nil
                    }
                }
            }

            for await result in group {
                if let (id, extracted) = result,
                   let item = items.first(where: { $0.id == id }),
                   let data = try? JSONEncoder().encode(extracted) {
                    item.extractedArticleData = data
                    item.readingMinutes = extracted.readingMinutes
                    if item.imageURL == nil {
                        item.imageURL = extracted.leadImageURL
                    }
                }
            }
        }
        try? context.save()
    }

    private func generateSummary(title: String, content: String) async -> IntelligenceOutput {
        isGenerating = true
        defer { isGenerating = false }

        let cleanContent = HTMLSanitizer.stripTags(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = String(cleanContent.prefix(4_000))

        let prompt = """
        Provide a 2 to 3 sentence spoken executive summary of this article.
        Use only the supplied article. Preserve key facts, names, numbers, and dates.

        Title: \(title)
        Content: \(sample)
        """

        #if canImport(FoundationModels)
        if let modelOutput = await generateArticleDigest(to: prompt) {
            return modelOutput
        }
        #endif

        return IntelligenceOutput(
            text: fallbackSummary(title: title, content: sample),
            modelKind: .extractiveFallback,
            isCached: false
        )
    }

    #if canImport(FoundationModels)
    #if ENABLE_PRIVATE_CLOUD_COMPUTE
    private static let hasPrivateCloudComputeEntitlement = true
    #else
    private static let hasPrivateCloudComputeEntitlement = false
    #endif

    private var modelInstructions: String {
        """
        You are the news editor and morning radio briefing host for Sift, an RSS news reader.
        Rewrite RSS articles as concise, engaging spoken news.
        Preserve key facts, names, numbers, dates, and source attribution.
        Never add facts that aren't in the supplied material.
        Avoid repetition, promotional text, website boilerplate, and markdown formatting.
        Write naturally for listening rather than reading.
        """
    }

    private func generateArticleDigest(to prompt: String) async -> IntelligenceOutput? {
        if #available(iOS 27.0, macOS 27.0, *), Self.hasPrivateCloudComputeEntitlement {
            let cloudModel = PrivateCloudComputeLanguageModel()
            if case .available = cloudModel.availability {
                activeModelKind = .privateCloudCompute
                do {
                    let session = LanguageModelSession(
                        model: cloudModel,
                        instructions: modelInstructions
                    )
                    let response = try await session.respond(
                        to: prompt,
                        generating: GeneratedArticleDigest.self
                    )
                    return IntelligenceOutput(
                        text: response.content.summary,
                        keyPoints: response.content.keyPoints,
                        topics: response.content.topics,
                        modelKind: .privateCloudCompute,
                        isCached: false
                    )
                } catch {
                    print("[ArticleIntelligenceService] PCC digest unavailable: \(error). Retrying on device.")
                }
            }
        }

        do {
            activeModelKind = .onDevice
            let session = LanguageModelSession(instructions: modelInstructions)
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedArticleDigest.self
            )
            return IntelligenceOutput(
                text: response.content.summary,
                keyPoints: response.content.keyPoints,
                topics: response.content.topics,
                modelKind: .onDevice,
                isCached: false
            )
        } catch {
            print("[ArticleIntelligenceService] Structured digest unavailable: \(error). Using extractive fallback.")
            return nil
        }
    }

    private func generateModelResponse(to prompt: String) async -> IntelligenceOutput? {
        if #available(iOS 27.0, macOS 27.0, *), Self.hasPrivateCloudComputeEntitlement {
            let cloudModel = PrivateCloudComputeLanguageModel()
            if case .available = cloudModel.availability {
                activeModelKind = .privateCloudCompute
                do {
                    let cloudSession = LanguageModelSession(
                        model: cloudModel,
                        instructions: modelInstructions
                    )
                    let response = try await cloudSession.respond(to: prompt)
                    let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !result.isEmpty {
                        return IntelligenceOutput(
                            text: result,
                            modelKind: .privateCloudCompute,
                            isCached: false
                        )
                    }
                } catch {
                    print("[ArticleIntelligenceService] Private Cloud Compute unavailable: \(error). Retrying on device.")
                }
            }
        }

        do {
            activeModelKind = .onDevice
            let onDeviceSession = LanguageModelSession(instructions: modelInstructions)
            let response = try await onDeviceSession.respond(to: prompt)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return nil }
            return IntelligenceOutput(
                text: result,
                modelKind: .onDevice,
                isCached: false
            )
        } catch {
            print("[ArticleIntelligenceService] On-device model unavailable: \(error). Using extractive fallback.")
            return nil
        }
    }
    #endif

    private func preferredContent(for article: FeedItem) -> String {
        if let extracted = article.extractedArticle {
            let text = extracted.blocks.map(\.text).joined(separator: "\n")
            if !text.isEmpty {
                return text
            }
        }
        return article.content ?? article.summary ?? article.snippet ?? ""
    }

    private static func contentHash(title: String, content: String) -> String {
        let digest = SHA256.hash(data: Data("\(title)\n\(content)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func briefingHash(for items: [FeedItem]) -> String {
        let material = items.map {
            let content = $0.extractedArticle?.blocks.map(\.text).joined(separator: "\n")
                ?? $0.content
                ?? $0.summary
                ?? $0.snippet
                ?? ""
            return "\($0.id.uuidString)\n\($0.title)\n\(content)"
        }.joined(separator: "\n---\n")
        return contentHash(title: "briefing", content: material)
    }

    private func fallbackSummary(title: String, content: String) -> String {
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 30 }

        if let first = sentences.first {
            let second = sentences.dropFirst().first.map { " " + $0 + "." } ?? ""
            return "\(first).\(second)"
        }
        return title
    }

    private func fallbackBriefing(topItems: [FeedItem]) -> String {
        var parts: [String] = [String(localized: "Here is your Sift briefing.")]
        for item in topItems {
            let source = item.feed?.title ?? String(localized: "your feeds")
            let snippet = item.snippet ?? item.title
            parts.append("From \(source): \(item.title). \(snippet.prefix(140)).")
        }
        parts.append(String(localized: "That concludes your latest updates."))
        return parts.joined(separator: " ")
    }
}
