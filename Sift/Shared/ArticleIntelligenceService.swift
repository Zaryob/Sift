import Foundation
import Combine
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service providing on-device Apple Intelligence summarization and spoken news briefings.
@MainActor
public final class ArticleIntelligenceService: ObservableObject {
    public static let shared = ArticleIntelligenceService()

    @Published public private(set) var isGenerating: Bool = false
    @Published public private(set) var latestBriefing: String?

    #if canImport(FoundationModels)
    private var modelSession: LanguageModelSession?

    private func getOrCreateSession() -> LanguageModelSession {
        if let modelSession {
            return modelSession
        }
        let session = LanguageModelSession(
            instructions: """
            You are the news editor and morning radio briefing host for Sift, an RSS news reader.
            Rewrite RSS articles as a concise, engaging, spoken news briefing.
            Preserve key facts, names, numbers, and dates.
            Avoid repetition, promotional text, website boilerplate, and markdown formatting.
            Write naturally for listening rather than reading.
            Keep sentences rhythmic, clear, and easy to understand aloud.
            """
        )
        self.modelSession = session
        return session
    }
    #endif

    private init() {}

    /// Summarizes an individual article into 2-3 concise spoken sentences or key takeaways.
    public func summarize(title: String, content: String) async -> String {
        isGenerating = true
        defer { isGenerating = false }

        let cleanContent = HTMLSanitizer.stripTags(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = String(cleanContent.prefix(2500))

        #if canImport(FoundationModels)
        do {
            let session = getOrCreateSession()
            let prompt = """
            Provide a 2 to 3 sentence spoken executive summary of this article for an audio listener:

            Title: \(title)
            Content: \(sample)
            """
            let response = try await session.respond(to: prompt)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty {
                return result
            }
        } catch {
            print("[ArticleIntelligenceService] FoundationModels error: \(error). Falling back to extractive summary.")
        }
        #endif

        return fallbackSummary(title: title, content: sample)
    }

    /// Compiles a spoken radio/podcast style briefing from a list of articles.
    public func generateBriefing(from items: [FeedItem]) async -> String {
        guard !items.isEmpty else {
            return String(localized: "You are all caught up. There are no unread articles in Sift.")
        }

        isGenerating = true
        defer { isGenerating = false }

        let topItems = Array(items.prefix(5))
        var contextText = ""
        for (index, item) in topItems.enumerated() {
            let feedTitle = item.feed?.title ?? "Unknown source"
            let snippet = item.snippet ?? HTMLSanitizer.stripTags(from: item.content ?? item.summary ?? "")
            contextText += "\nStory \(index + 1) from \(feedTitle):\nTitle: \(item.title)\nExcerpt: \(snippet.prefix(350))\n"
        }

        #if canImport(FoundationModels)
        do {
            let session = getOrCreateSession()
            let prompt = """
            Create a 60-to-90 second spoken news briefing covering the following top stories.
            Begin with a warm greeting like "Here is your Sift briefing for today."
            Smoothly transition between the stories like a professional NPR or BBC radio anchor.
            Conclude with a brief closing sentence.

            Stories:
            \(contextText)
            """
            let response = try await session.respond(to: prompt)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty {
                latestBriefing = result
                return result
            }
        } catch {
            print("[ArticleIntelligenceService] FoundationModels briefing error: \(error). Falling back.")
        }
        #endif

        let fallback = fallbackBriefing(topItems: topItems)
        latestBriefing = fallback
        return fallback
    }

    /// Generates a briefing from unread articles stored in SwiftData.
    public func generateBriefingForUnreadArticles() async -> String {
        let context = ModelContext(PersistenceController.shared.container)
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate<FeedItem> { !$0.isRead },
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
        )
        descriptor.fetchLimit = 5

        do {
            let items = try context.fetch(descriptor)
            return await generateBriefing(from: items)
        } catch {
            return String(localized: "Unable to retrieve unread articles from your Sift library.")
        }
    }

    /// Summarizes the single latest unread article.
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
            return await summarize(title: item.title, content: item.content ?? item.summary ?? "")
        } catch {
            return String(localized: "Unable to load article.")
        }
    }

    // MARK: - Fallbacks

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
        var parts: [String] = ["Here is your Sift briefing."]
        for item in topItems {
            let source = item.feed?.title ?? "your feeds"
            let snippet = item.snippet ?? item.title
            parts.append("From \(source): \(item.title). \(snippet.prefix(140)).")
        }
        parts.append("That concludes your latest updates.")
        return parts.joined(separator: " ")
    }
}
