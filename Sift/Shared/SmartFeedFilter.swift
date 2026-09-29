import Foundation

/// A high-performance, deterministic ranking and diversity filter for the SIFT Feed —
/// Sift's flagship curated feed.
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
        return decodeVIPFeedIDs(raw)
    }

    public static func decodeVIPFeedIDs(_ rawValue: String) -> Set<UUID> {
        Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    public static func encodeVIPFeedIDs(_ feedIDs: Set<UUID>) -> String {
        feedIDs.map(\.uuidString).sorted().joined(separator: ",")
    }

    /// Curates a list of articles into a high-signal SIFT Feed digest.
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
                guard !isHighConfidenceNoise(article.title, link: article.link) else { continue }
            }

            // Stale threshold:
            // - Read articles older than 48 hours (72h for VIP) do not belong in a fresh SIFT Feed
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

        // 4. Diversity: selection is driven primarily by score. The per-source cap
        // below is only an anti-monopoly guard against a single firehose feed —
        // it no longer divides the budget evenly across sources. Real diversity
        // comes from the per-topic cap, which clusters candidates by title-token
        // overlap regardless of which feed published them.
        let maxPerSource = max(6, Int(ceil(Double(budget) * 0.5)))
        let maxPerTopic = max(4, Int(ceil(Double(budget) / 6.0)))
        let topicSimilarityThreshold = 0.3
        let duplicateSimilarityThreshold = 0.65

        var seenURLs = Set<String>()
        var seenNormalizedTitles = Set<String>()
        var selected: [(sourceKey: String, date: Date, tokens: Set<String>, candidateIndex: Int)] = []
        var sourceCounts: [String: Int] = [:]
        var selectedIDs = Set<UUID>()

        for candidateIndex in candidates.indices {
            guard selectedIDs.count < budget else { break }

            let candidate = candidates[candidateIndex]

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

            // Anti-monopoly limit per feed/source (VIP feeds get up to double the normal cap)
            let currentSourceCount = sourceCounts[candidate.sourceKey, default: 0]
            let effectiveMax = candidate.isVIP ? (maxPerSource * 2) : maxPerSource
            if currentSourceCount >= effectiveMax {
                continue
            }

            // Title-token clustering: detects both exact cross-source syndication
            // (same story, different outlet -> merge & boost the representative)
            // and looser topical overlap (same subject, regardless of source ->
            // counts toward the per-topic diversity cap).
            var isDuplicateStory = false
            var topicSaturationCount = 0

            if candidate.titleTokens.count >= 3 {
                let candidateDate = candidate.item.publicationDate

                for existingIndex in 0..<selected.count {
                    let existing = selected[existingIndex]
                    guard existing.tokens.count >= 3 else { continue }
                    guard abs(existing.date.timeIntervalSince(candidateDate)) <= 172_800 else { continue }

                    let similarity = titleSimilarity(candidate.titleTokens, existing.tokens)
                    guard similarity >= topicSimilarityThreshold else { continue }

                    topicSaturationCount += 1

                    if existing.sourceKey != candidate.sourceKey,
                       candidate.titleTokens.count >= 4, existing.tokens.count >= 4,
                       similarity >= duplicateSimilarityThreshold {
                        isDuplicateStory = true
                        // Boost representative story that was already selected
                        let representativeIndex = existing.candidateIndex
                        candidates[representativeIndex].coverageCount += 1
                        candidates[representativeIndex].score += 20 // Multi-source coverage signal bonus
                        break
                    }
                }

                if isDuplicateStory {
                    continue
                }
            }

            // Per-topic diversity cap: keeps a single subject from crowding out the
            // feed even when many different sources are covering it (VIP exempt).
            if !candidate.isVIP, topicSaturationCount >= maxPerTopic {
                continue
            }

            // Accepted candidate
            if let url = candidate.canonicalURL {
                seenURLs.insert(url)
            }
            if !candidate.normalizedTitle.isEmpty {
                seenNormalizedTitles.insert(candidate.normalizedTitle)
            }
            if !candidate.titleTokens.isEmpty {
                selected.append((
                    sourceKey: candidate.sourceKey,
                    date: candidate.item.publicationDate,
                    tokens: candidate.titleTokens,
                    candidateIndex: candidateIndex
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
    /// required to appear in the SIFT Feed and warrant a system alert / notification.
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
            guard !isHighConfidenceNoise(cleanTitle, link: article.link) else {
                return false
            }
        }

        guard !isClickbait(cleanTitle) else {
            return false
        }

        let score = computeScore(for: article, ageHours: 0, isStarred: false, isVIP: isVIP)
        return score >= 85
    }

    /// Evaluates whether an article title alone qualifies for a SIFT Feed notification.
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
            let token = String(word)
            if (token.count >= 3 || token.allSatisfy(\.isNumber)) && !stopWords.contains(token) {
                tokens.insert(token)
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
        // English
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
        // Turkish
        "sponsorlu içerik",
        "sponsorlu icerik",
        "reklam içeriği",
        "reklam icerigi",
        "iş ilanı",
        "is ilani",
        "çekiliş",
        "cekilis",
        "fırsat ürünü",
        "indirim kuponu",
        // German
        "gesponserter beitrag",
        "gesponserte inhalte",
        "anzeige:",
        "partnerinhalt",
        "werbung:",
        "rabattcode",
        "gutscheincode",
        "gewinnspiel",
        "wir suchen mitarbeiter",
        "stellenangebot",
        // French
        "contenu sponsorisé",
        "contenu sponsorise",
        "article sponsorisé",
        "article sponsorise",
        "publicité :",
        "publicite :",
        "contenu partenaire",
        "code promo",
        "code de réduction",
        "code de reduction",
        "jeu concours",
        "tentez de gagner",
        "offre d'emploi",
        "nous recrutons"
    ]

    /// Structural, language-independent signal: many CMSs route sponsored posts
    /// through a consistent URL path regardless of the site's language, since
    /// the taxonomy is set by the publishing platform rather than the author.
    private static let promotionalURLPathMarkers: [String] = [
        "/sponsored/",
        "/sponsored-post/",
        "/sponsored-content/",
        "/advertorial/",
        "/partner-content/",
        "/paid-content/",
        "/promoted/",
        "/brandvoice/",
        "/branded-content/"
    ]

    private static func isPromotionalLink(_ link: String?) -> Bool {
        guard let link, let url = URL(string: link) else { return false }
        let path = url.path.lowercased()
        return promotionalURLPathMarkers.contains { path.contains($0) }
    }

    /// Detects unambiguous promotional/sponsored/ad boilerplate. Used both for
    /// SIFT Feed ranking and for deciding what's genuinely safe to discard from
    /// storage entirely (see `PromotionalCleanupStats`). Title-keyword coverage
    /// only extends to the app's supported languages (English, Turkish, German,
    /// French); passing `link` adds a language-independent structural check on
    /// top, so callers with a URL on hand should always supply it.
    public static func isHighConfidenceNoise(_ title: String, link: String? = nil) -> Bool {
        let lower = title.lowercased()
        if noiseMarkers.contains(where: lower.contains) {
            return true
        }
        return isPromotionalLink(link)
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
