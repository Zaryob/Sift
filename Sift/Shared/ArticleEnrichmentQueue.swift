import Foundation
import Combine
import SwiftData

/// Best-effort, resumable enrichment for recent feed items. The publisher page
/// fetch is ordinary RSS-reader networking; all generated analysis uses Apple's
/// on-device Foundation Model and is skipped while that model is unavailable.
@MainActor
public final class ArticleEnrichmentQueue: ObservableObject {
    public static let shared = ArticleEnrichmentQueue()

    @Published public private(set) var isProcessing = false
    @Published public private(set) var progressMessage: String?
    @Published public private(set) var processedArticleCount = 0
    @Published public private(set) var completedPassCount = 0

    private var task: Task<Void, Never>?
    private var modelRetryTask: Task<Void, Never>?
    private var needsAnotherPass = false
    private let maximumArticlesPerPass = 25

    private init() {}

    /// Re-scans the local-calendar window each time, so interruption or OS
    /// suspension does not lose work: the next feed refresh discovers leftovers.
    public func scheduleRecentItems(in container: ModelContainer) {
        guard task == nil else {
            needsAnotherPass = true
            return
        }

        isProcessing = true
        processedArticleCount = 0
        // Lower priority than user-interactive work: this enrichment pass runs
        // automatically after every refresh and shouldn't contend with scrolling
        // or other UI-driven work for CPU time.
        task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await processRecentItems(in: container)
            task = nil
            progressMessage = nil
            isProcessing = false
            completedPassCount += 1

            if needsAnotherPass {
                needsAnotherPass = false
                scheduleRecentItems(in: container)
            }
        }
    }

    private func processRecentItems(in container: ModelContainer) async {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            ?? now.addingTimeInterval(-48 * 60 * 60)
        var descriptor = FetchDescriptor<FeedItem>(
            predicate: #Predicate {
                $0.publicationDate >= startOfYesterday && $0.publicationDate <= now
            },
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
        )
        descriptor.fetchLimit = maximumArticlesPerPass
        let context = ModelContext(container)
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return }
        await extractMissingBodies(from: items, context: context)

        let intelligence = ArticleIntelligenceService.shared
        guard intelligence.isOnDeviceModelAvailable else {
            // The RSS reader remains fully usable. A later refresh will retry once
            // Apple Intelligence is ready, without persisting a fake AI digest.
            if intelligence.availability == .modelNotReady {
                scheduleModelReadinessRetry(in: container)
            }
            return
        }

        modelRetryTask?.cancel()
        modelRetryTask = nil

        progressMessage = String(localized: "Enriching recent articles on this device…")
        for item in items {
            guard !Task.isCancelled else { return }
            if intelligence.currentOnDeviceDigest(for: item) == nil {
                _ = await intelligence.summarize(
                    article: item,
                    context: context,
                    classifyIrrelevantContent: false,
                    persistImmediately: false
                )
            }
            processedArticleCount += 1
        }
        save(context, operation: "article enrichment")
    }

    private func extractMissingBodies(from items: [FeedItem], context: ModelContext) async {
        let now = Date()
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let requests = items.compactMap { item -> ExtractionRequest? in
            let extractedWordCount = item.extractedArticle?.wordCount ?? 0
            guard extractedWordCount < 120,
                  !item.hasSubstantialFeedContent,
                  let link = item.link,
                  let url = URL(string: link),
                  url.scheme == "https" || url.scheme == "http",
                  let host = url.host(), !host.isEmpty else { return nil }
            if let lastAttempt = item.extractionAttemptedAt,
               now.timeIntervalSince(lastAttempt) < 86_400 {
                return nil
            }
            return ExtractionRequest(
                itemID: item.id,
                url: url,
                summary: item.summary ?? item.content
            )
        }

        guard !requests.isEmpty else { return }
        progressMessage = String(localized: "Preparing article text…")
        let maximumConcurrentRequests = 4

        for start in stride(from: 0, to: requests.count, by: maximumConcurrentRequests) {
            let end = min(start + maximumConcurrentRequests, requests.count)
            let batch = Array(requests[start..<end])
            await withTaskGroup(of: ExtractionResponse.self) { group in
                for request in batch {
                    group.addTask {
                        let article = try? await ArticleExtractor.fetch(url: request.url, summary: request.summary)
                        return ExtractionResponse(itemID: request.itemID, article: article)
                    }
                }

                for await response in group {
                    guard let item = itemByID[response.itemID] else { continue }
                    item.extractionAttemptedAt = Date()
                    if let article = response.article,
                       let data = try? JSONEncoder().encode(article) {
                        item.extractedArticleData = data
                        item.readingMinutes = article.readingMinutes
                        if item.imageURL == nil {
                            item.imageURL = article.leadImageURL
                        }
                    }
                }
            }
            // Persist each small batch so a background suspension resumes from the
            // remaining rows instead of repeating successful publisher downloads.
            save(context, operation: "article extraction batch")
        }
    }

    private func scheduleModelReadinessRetry(in container: ModelContainer) {
        guard modelRetryTask == nil else { return }
        modelRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15 * 60))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            modelRetryTask = nil
            scheduleRecentItems(in: container)
        }
    }

    private func save(_ context: ModelContext, operation: String) {
        do {
            try context.save()
        } catch {
            print("[ArticleEnrichmentQueue] Failed to save \(operation): \(error)")
        }
    }
}

private struct ExtractionRequest: Sendable {
    let itemID: UUID
    let url: URL
    let summary: String?
}

private struct ExtractionResponse: Sendable {
    let itemID: UUID
    let article: ExtractedArticle?
}
