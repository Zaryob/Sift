import Foundation

/// A high-performance, deterministic ranking and diversity filter for the default Smart Feed.
/// Curates large article archives into a high-signal digest of fresh, relevant stories,
/// while leaving all raw articles untouched in "All Articles".
public enum SmartFeedFilter {

    private struct ScoredCandidate {
        let item: FeedItem
        var score: Int
        let canonicalURL: String?
        let normalizedTitle: String
        let titleTokens: Set<String>
        let sourceKey: String
        let isVIP: Bool
        var coverageCount: Int = 1
    }

    /// Loads the user-designated VIP feed IDs stored in UserDefaults.
    public static func loadStoredVIPFeedIDs() -> Set<UUID> {
        guard let raw = UserDefaults.standard.string(forKey: "vipFeedIDs"), !raw.isEmpty else {
            return []
        }
        return Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    /// Curates a list of articles into a high-signal Smart Feed digest.
    /// - Parameters:
    ///   - articles: The complete list of feed items.
    ///   - vipFeedIDs: Optional set of VIP feed IDs. If nil, automatically loads from user settings.
    public static func filteredArticles(from articles: [FeedItem], vipFeedIDs: Set<UUID>? = nil) -> [FeedItem] {
        guard !articles.isEmpty else { return [] }

        let effectiveVIPs = vipFeedIDs ?? loadStoredVIPFeedIDs()
        let now = Date()

        // 1. Separate starred articles and collect eligible candidates in a single O(N) pass
        var candidates: [ScoredCandidate] = []
        candidates.reserveCapacity(min(articles.count, 256))

        var starredIDs = Set<UUID>()

        for article in articles {
            let isVIP = (article.feed?.id).map { effectiveVIPs.contains($0) } ?? false
            let ageHours = max(0, now.timeIntervalSince(article.publicationDate) / 3_600)

            if article.isStarred {
                starredIDs.insert(article.id)
                // Recent or unread starred items also participate in candidate scoring for ranking
                if ageHours <= 720 || !article.isRead {
                    let scoreVal = computeScore(for: article, ageHours: ageHours, isStarred: true, isVIP: isVIP)
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
                        sourceKey: srcKey,
                        isVIP: isVIP
                    ))
                }
                continue
            }

            // Exclude high-confidence advertising/promotional noise unless from a trusted VIP feed
            if !isVIP {
                guard !isHighConfidenceNoise(article.title) else { continue }
            }

            // Stale threshold:
            // - Read articles older than 48 hours (72h for VIP) do not belong in a fresh Smart Feed
            // - Unread articles older than 14 days (30 days for VIP) are considered backlog
            if article.isRead {
                let maxReadHours: Double = isVIP ? 72 : 48
                guard ageHours <= maxReadHours else { continue }
            } else {
                let maxUnreadHours: Double = isVIP ? 720 : 336
                guard ageHours <= maxUnreadHours else { continue }
            }

            let scoreVal = computeScore(for: article, ageHours: ageHours, isStarred: false, isVIP: isVIP)
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
                sourceKey: srcKey,
                isVIP: isVIP
            ))
        }

        // 2. Determine budget: dynamically scale with library size to curate signal over noise
        let budget = selectionBudget(for: articles.count, candidateCount: candidates.count)

        // 3. Sort candidates by initial score descending (fast O(N log N) on lightweight struct)
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
            maxPerSource = max(3, Int(ceil(Double(budget) / Double(uniqueSources) * 2.2)))
        }

        var seenURLs = Set<String>()
        var seenNormalizedTitles = Set<String>()
        var selectedBySource: [(sourceKey: String, date: Date, tokens: Set<String>, candidateIndex: Int)] = []
        var sourceCounts: [String: Int] = [:]
        var selectedIDs = Set<UUID>()

        for i in 0..<candidates.count {
            guard selectedIDs.count < budget else { break }

            let candidate = candidates[i]

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

            // Diversity limit per feed/source (VIP feeds get up to double the normal cap)
            let currentSourceCount = sourceCounts[candidate.sourceKey, default: 0]
            let effectiveMax = candidate.isVIP ? (maxPerSource * 2) : maxPerSource
            if currentSourceCount >= effectiveMax {
                continue
            }

            // Cross-source syndication / near-duplicate check & Story Velocity Boost
            // If another outlet covered this exact story within 48h, boost the representative story!
            if candidate.titleTokens.count >= 4 {
                let candidateDate = candidate.item.publicationDate
                var isCrossSourceDuplicate = false

                for existingIndex in 0..<selectedBySource.count {
                    let existing = selectedBySource[existingIndex]
                    guard existing.sourceKey != candidate.sourceKey else { continue }
                    guard existing.tokens.count >= 4 else { continue }
                    guard abs(existing.date.timeIntervalSince(candidateDate)) <= 172_800 else { continue }

                    let similarity = titleSimilarity(candidate.titleTokens, existing.tokens)
                    if similarity >= 0.65 {
                        isCrossSourceDuplicate = true
                        // Boost representative story that was already selected
                        let repIdx = existing.candidateIndex
                        candidates[repIdx].coverageCount += 1
                        candidates[repIdx].score += 20 // Multi-source coverage signal bonus
                        break
                    }
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
                    tokens: candidate.titleTokens,
                    candidateIndex: i
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

    /// Evaluates whether an incoming newly discovered article meets the quality bar
    /// required to appear in the Smart Feed and warrant a system alert / notification.
    public static func qualifiesForSmartFeedNotification(_ article: FeedItem, vipFeedIDs: Set<UUID>? = nil) -> Bool {
        if article.isStarred {
            return true
        }

        let effectiveVIPs = vipFeedIDs ?? loadStoredVIPFeedIDs()
        let isVIP = (article.feed?.id).map { effectiveVIPs.contains($0) } ?? false

        let cleanTitle = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 15 else {
            return false
        }

        // VIP feeds bypass generic noise checks unless explicitly clickbait
        if !isVIP {
            guard !isHighConfidenceNoise(cleanTitle) else {
                return false
            }
        }

        guard !isClickbait(cleanTitle) else {
            return false
        }

        let score = computeScore(for: article, ageHours: 0, isStarred: false, isVIP: isVIP)
        return score >= 85
    }

    /// Evaluates whether an article title alone qualifies for a Smart Feed notification.
    public static func qualifiesForSmartFeedNotification(title: String) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 15 else {
            return false
        }
        guard !isHighConfidenceNoise(cleanTitle) else {
            return false
        }
        guard !isClickbait(cleanTitle) else {
            return false
        }
        return true
    }

    private static func selectionBudget(for totalCount: Int, candidateCount: Int) -> Int {
        guard candidateCount > 0 else { return 0 }
        if candidateCount <= 30 {
            return candidateCount
        }
        // Scaled budget: curves gently between 30 and 80 articles
        let dynamicBudget = Int(sqrt(Double(totalCount)) * 2.5)
        return min(80, max(30, min(candidateCount, dynamicBudget)))
    }

    private static func computeScore(for article: FeedItem, ageHours: Double, isStarred: Bool, isVIP: Bool) -> Int {
        var score = 40

        // Recency scoring (Breaking & Freshness Curve)
        if ageHours < 3 {
            score += 45 // Breaking / Hot
        } else if ageHours < 8 {
            score += 35
        } else if ageHours < 18 {
            score += 26
        } else if ageHours < 36 {
            score += 18
        } else if ageHours < 72 {
            score += 8
        } else if ageHours < 168 { // 7 days
            score += 2
        } else {
            score -= 15
        }

        // Read status preference
        if article.isRead {
            score -= 18
        } else {
            score += 20
        }

        // Starred bonus
        if isStarred {
            score += 45
        }

        // VIP source bonus
        if isVIP {
            score += 35
        }

        // Content depth & substance
        if let minutes = article.readingMinutes, minutes >= 3 {
            score += 12
        } else if let minutes = article.readingMinutes, minutes >= 1 {
            score += 6
        } else if let snippet = article.snippet, snippet.count >= 140 {
            score += 6
        }

        // Extracted full text available
        if article.extractedArticleData != nil {
            score += 10
        }

        // Rich image thumbnail available
        if let imageURL = article.imageURL, !imageURL.isEmpty {
            score += 5
        }

        // Quality and headline penalties
        if article.title.count < 15 {
            score -= 12
        }

        if isClickbait(article.title) {
            score -= 25
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
        guard intersectionCount >= 3 else { return 0 }
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
        "discount code",
        "black friday",
        "cyber monday",
        "giveaway",
        "enter to win",
        "sweepstakes",
        "we're hiring",
        "we are hiring",
        "job opening",
        "career opportunity",
        "sponsorlu içerik",
        "sponsorlu icerik",
        "reklam içeriği",
        "reklam icerigi",
        "iş ilanı",
        "is ilani",
        "çekiliş",
        "cekilis",
        "fırsat ürünü",
        "indirim kuponu"
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
        "wait until you see",
        "blow your mind",
        "can't stop talking about",
        "inanamayacaksınız",
        "inanamayacaksiniz",
        "şoke eden",
        "soke eden",
        "herkes bunu konuşuyor",
        "herkes bunu konusuyor",
        "gözlerinize inanamayacaksınız",
        "akıllara durgunluk"
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
