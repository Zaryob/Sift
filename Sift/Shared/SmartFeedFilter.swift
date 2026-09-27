import Foundation

/// A high-performance, deterministic ranking and diversity filter for the default Smart Feed.
/// Curates large article archives into a high-signal digest of fresh, relevant stories,
/// while leaving all raw articles untouched in "All Articles".
public enum SmartFeedFilter {

    private struct ScoredCandidate {
        let item: FeedItem
        let score: Int
        let canonicalURL: String?
        let normalizedTitle: String
        let titleTokens: Set<String>
        let sourceKey: String
    }

    public static func filteredArticles(from articles: [FeedItem]) -> [FeedItem] {
        guard !articles.isEmpty else { return [] }

        let now = Date()

        // 1. Separate starred articles and collect eligible candidates in a single O(N) pass
        var candidates: [ScoredCandidate] = []
        candidates.reserveCapacity(min(articles.count, 256))

        var starredIDs = Set<UUID>()

        for article in articles {
            let ageHours = max(0, now.timeIntervalSince(article.publicationDate) / 3_600)

            if article.isStarred {
                starredIDs.insert(article.id)
                // Recent or unread starred items also participate in candidate scoring for ranking
                if ageHours <= 720 || !article.isRead {
                    let scoreVal = computeScore(for: article, ageHours: ageHours, isStarred: true)
                    let urlKey = canonicalURLKey(article.link)
                    let normTitle = normalizeFullTitle(article.title)
                    let tokens = extractSubstantiveTokens(article.title)
                    let srcKey = extractSourceKey(article)
                    candidates.append(ScoredCandidate(
                        item: article,
                        score: scoreVal,
                        canonicalURL: urlKey,
                        normalizedTitle: normTitle,
                        titleTokens: tokens,
                        sourceKey: srcKey
                    ))
                }
                continue
            }

            // Exclude high-confidence advertising/promotional noise
            guard !isHighConfidenceNoise(article.title) else { continue }

            // Stale threshold:
            // - Read articles older than 48 hours do not belong in a fresh Smart Feed
            // - Unread articles older than 14 days are considered stale backlog (accessible in All Articles)
            if article.isRead {
                guard ageHours <= 48 else { continue }
            } else {
                guard ageHours <= 336 else { continue } // 14 days
            }

            let scoreVal = computeScore(for: article, ageHours: ageHours, isStarred: false)
            let urlKey = canonicalURLKey(article.link)
            let normTitle = normalizeFullTitle(article.title)
            let tokens = extractSubstantiveTokens(article.title)
            let srcKey = extractSourceKey(article)

            candidates.append(ScoredCandidate(
                item: article,
                score: scoreVal,
                canonicalURL: urlKey,
                normalizedTitle: normTitle,
                titleTokens: tokens,
                sourceKey: srcKey
            ))
        }

        // 2. Determine budget: dynamically scale with library size to curate signal over noise
        let budget = selectionBudget(for: articles.count, candidateCount: candidates.count)

        // 3. Sort candidates by score descending (fast O(N log N) on lightweight struct with precomputed Int scores)
        candidates.sort {
            if $0.score == $1.score {
                return $0.item.publicationDate > $1.item.publicationDate
            }
            return $0.score > $1.score
        }

        // 4. Source diversity: cap maximum articles per feed so a single firehose feed cannot dominate
        let uniqueSources = Set(candidates.map(\.sourceKey)).count
        let maxPerSource: Int
        if uniqueSources <= 2 {
            maxPerSource = budget
        } else {
            maxPerSource = max(4, Int(ceil(Double(budget) / Double(uniqueSources) * 2.2)))
        }

        var seenURLs = Set<String>()
        var seenNormalizedTitles = Set<String>()
        var selectedBySource: [(sourceKey: String, date: Date, tokens: Set<String>)] = []
        var sourceCounts: [String: Int] = [:]
        var selectedIDs = Set<UUID>()

        for candidate in candidates {
            guard selectedIDs.count < budget else { break }

            // URL deduplication
            if let url = candidate.canonicalURL {
                if seenURLs.contains(url) {
                    continue
                }
            }

            // Exact normalized title deduplication across all sources
            if !candidate.normalizedTitle.isEmpty {
                if seenNormalizedTitles.contains(candidate.normalizedTitle) {
                    continue
                }
            }

            // Diversity limit per feed/source
            let currentSourceCount = sourceCounts[candidate.sourceKey, default: 0]
            if currentSourceCount >= maxPerSource {
                continue
            }

            // Cross-source syndication / near-duplicate check (only across DIFFERENT feeds within 48h window)
            if candidate.titleTokens.count >= 5 {
                let candidateDate = candidate.item.publicationDate
                let isCrossSourceDuplicate = selectedBySource.contains { existing in
                    guard existing.sourceKey != candidate.sourceKey else { return false }
                    guard existing.tokens.count >= 5 else { return false }
                    guard abs(existing.date.timeIntervalSince(candidateDate)) <= 172_800 else { return false }
                    return titleSimilarity(candidate.titleTokens, existing.tokens) >= 0.82
                }
                if isCrossSourceDuplicate {
                    continue
                }
            }

            // Accepted candidate
            if let url = candidate.canonicalURL {
                seenURLs.insert(url)
            }
            if !candidate.normalizedTitle.isEmpty {
                seenNormalizedTitles.insert(candidate.normalizedTitle)
            }
            if !candidate.titleTokens.isEmpty {
                selectedBySource.append((
                    sourceKey: candidate.sourceKey,
                    date: candidate.item.publicationDate,
                    tokens: candidate.titleTokens
                ))
            }
            sourceCounts[candidate.sourceKey] = currentSourceCount + 1
            selectedIDs.insert(candidate.item.id)
        }

        // Always retain user-starred items
        selectedIDs.formUnion(starredIDs)

        // Return curated items in their original chronological order
        return articles.filter { selectedIDs.contains($0.id) }
    }

    private static func selectionBudget(for totalCount: Int, candidateCount: Int) -> Int {
        guard candidateCount > 0 else { return 0 }
        if candidateCount <= 30 {
            return candidateCount
        }
        // Scaled budget: curves gently between 30 and 75 articles
        let dynamicBudget = Int(sqrt(Double(totalCount)) * 2.4)
        return min(75, max(30, min(candidateCount, dynamicBudget)))
    }

    private static func computeScore(for article: FeedItem, ageHours: Double, isStarred: Bool) -> Int {
        var score = 40

        // Recency scoring
        if ageHours < 12 {
            score += 35
        } else if ageHours < 24 {
            score += 25
        } else if ageHours < 48 {
            score += 15
        } else if ageHours < 168 { // 7 days
            score += 5
        } else {
            score -= 15
        }

        // Read status preference
        if article.isRead {
            score -= 15
        } else {
            score += 20
        }

        // Starred bonus
        if isStarred {
            score += 40
        }

        // Content depth & substance (zero JSON decoding or HTML stripping)
        if let minutes = article.readingMinutes, minutes >= 2 {
            score += 10
        } else if let snippet = article.snippet, snippet.count >= 120 {
            score += 6
        }

        if article.extractedArticleData != nil {
            score += 8
        }

        if let imageURL = article.imageURL, !imageURL.isEmpty {
            score += 4
        }

        // Quality and headline penalties
        if article.title.count < 15 {
            score -= 10
        }

        if isClickbait(article.title) {
            score -= 20
        }

        return score
    }

    private static func extractSourceKey(_ article: FeedItem) -> String {
        if let feedID = article.feed?.id {
            return feedID.uuidString
        }
        if let link = article.link, let host = URL(string: link)?.host() {
            return host.lowercased()
        }
        return article.author?.lowercased() ?? "unknown"
    }

    private static func normalizeFullTitle(_ title: String) -> String {
        let lower = title.lowercased()
        let words = lower.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "are", "was",
        "were", "will", "have", "has", "had", "about", "into", "over",
        "after", "what", "when", "where", "which", "more", "some", "they",
        "their", "then", "them", "these", "those", "been", "being"
    ]

    private static func extractSubstantiveTokens(_ title: String) -> Set<String> {
        let lower = title.lowercased()
        var tokens = Set<String>()
        let words = lower.split { !$0.isLetter && !$0.isNumber }
        for word in words {
            let str = String(word)
            if (str.count >= 3 || str.allSatisfy(\.isNumber)) && !stopWords.contains(str) {
                tokens.insert(str)
            }
        }
        return tokens
    }

    private static func titleSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersectionCount = lhs.intersection(rhs).count
        guard intersectionCount >= 4 else { return 0 }
        let unionCount = lhs.union(rhs).count
        guard unionCount > 0 else { return 0 }
        return Double(intersectionCount) / Double(unionCount)
    }

    private static let noiseMarkers: [String] = [
        "[sponsored]",
        "sponsored post",
        "sponsored content",
        "partner content",
        "paid post",
        "advertisement:",
        "from our partners",
        "deal of the day",
        "coupon code",
        "promo code",
        "we're hiring",
        "we are hiring",
        "job opening",
        "sponsorlu içerik",
        "sponsorlu icerik",
        "reklam içeriği",
        "reklam icerigi",
        "iş ilanı",
        "is ilani"
    ]

    private static func isHighConfidenceNoise(_ title: String) -> Bool {
        let lower = title.lowercased()
        return noiseMarkers.contains { lower.contains($0) }
    }

    private static let clickbaitMarkers: [String] = [
        "you won't believe",
        "you wont believe",
        "what happened next",
        "this one trick",
        "the internet is losing it",
        "shocking reason",
        "inanamayacaksınız",
        "inanamayacaksiniz",
        "şoke eden",
        "soke eden",
        "herkes bunu konuşuyor",
        "herkes bunu konusuyor"
    ]

    private static func isClickbait(_ title: String) -> Bool {
        let lower = title.lowercased()
        return clickbaitMarkers.contains { lower.contains($0) }
    }

    private static func canonicalURLKey(_ rawValue: String?) -> String? {
        guard let rawValue,
              var components = URLComponents(string: rawValue) else { return nil }
        components.fragment = nil
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_")
                    && name != "ref"
                    && name != "source"
                    && name != "campaign"
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.url?.absoluteString ?? components.string
    }
}
