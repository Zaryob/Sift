import Foundation

/// The readable body of an article, extracted from the publisher's page.
nonisolated public struct ExtractedArticle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case paragraph, heading, quote, listItem, code
    }

    public struct Block: Codable, Equatable, Hashable, Sendable {
        public var kind: Kind
        public var text: String
    }

    public var blocks: [Block]
    public var leadImageURL: String?

    public var wordCount: Int {
        blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    public var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 220).rounded(.up)))
    }
}

/// A small Readability-style extractor.
///
/// It scans tags with a stack instead of parsing a DOM: whole elements whose tag or class/id looks
/// like chrome (nav, share bars, donation boxes, comments, related links…) are skipped, and the
/// remaining p/h2–h4/blockquote/li blocks are split into runs wherever a lot of non-skipped markup
/// separates them. The run that contains the start of the feed's summary — or, failing that, the
/// run with the most words — is the article.
nonisolated public enum ArticleExtractor {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Markup (outside skipped elements) between two blocks beyond which they belong to different regions.
    private static let regionGapThreshold = 2_000
    private static let minimumWordCount = 120

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr", "param"
    ]
    private static let skippedElements: Set<String> = [
        "script", "style", "noscript", "svg", "template", "iframe", "nav", "header", "footer",
        "aside", "form", "button", "select", "figure", "table"
    ]
    private static let blockKinds: [String: ExtractedArticle.Kind] = [
        "p": .paragraph, "h2": .heading, "h3": .heading, "h4": .heading, "blockquote": .quote, "li": .listItem, "pre": .code
    ]

    private static let tagRegex = try! NSRegularExpression(pattern: "<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>")
    private static let classOrIDRegex = try! NSRegularExpression(pattern: "(?:class|id)\\s*=\\s*[\"']([^\"']*)[\"']", options: .caseInsensitive)
    private static let paragraphClosers: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figure", "footer",
        "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre",
        "section", "table", "ul"
    ]
    /// Page-level containers are never skipped because of their class names.
    private static let neverSkippedByClass: Set<String> = ["html", "body", "main", "article"]
    private static let boilerplatePrefixes = [
        "support", "donat", "patreon", "promo", "sponsor", "advert", "banner", "newsletter", "subscri",
        "share", "sharing", "social", "comment", "related", "recommend", "author", "byline", "breadcrumb",
        "cookie", "consent", "modal", "popup", "toolbar", "menu", "sidebar", "itembox", "footer",
        "navbox", "navbar", "navigation"
    ]
    private static let boilerplateExactParts: Set<String> = ["ad", "ads", "nav"]
    private static let ogImageRegex = try! NSRegularExpression(
        pattern: "<meta[^>]+(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]*content=[\"']([^\"']+)[\"']|<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"'](?:og:image|twitter:image)[\"']",
        options: .caseInsensitive
    )

    @concurrent public static func fetch(url: URL, summary: String?) async throws -> ExtractedArticle? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = decode(data, response: http) else {
            return nil
        }
        return extract(html: html, baseURL: http.url ?? url, summary: summary)
    }

    public static func extract(html rawHTML: String, baseURL: URL, summary: String?) -> ExtractedArticle? {
        let html = rawHTML.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        let blocks = scanBlocks(in: html)
        guard !blocks.isEmpty else { return nil }

        let runs = splitIntoRuns(blocks)
        let anchor = summaryAnchor(summary)
        var article: [ExtractedArticle.Block]
        if let anchor, let (runIndex, blockIndex) = locate(anchor: anchor, in: runs) {
            // With a known start, whatever follows the next big gap is credits/footer, not article.
            article = Array(runs[runIndex][blockIndex...]).map(\.block)
        } else if let best = runs.indices.max(by: { proseWords(in: runs[$0]) < proseWords(in: runs[$1]) }) {
            let span = mergedSpan(around: best, in: runs)
            article = runs[span].flatMap { $0.map(\.block) }
        } else {
            return nil
        }
        // A run shouldn't end on a heading or a leftover like "Continue Reading".
        while let last = article.last, last.kind == .heading || last.text.split(whereSeparator: \.isWhitespace).count < 5 {
            article.removeLast()
        }

        let result = ExtractedArticle(blocks: article, leadImageURL: leadImage(in: html, baseURL: baseURL))
        let summaryWords = summary.map { HTMLSanitizer.stripTags(from: $0).split(whereSeparator: \.isWhitespace).count } ?? 0
        // Not worth showing if it isn't clearly more than the feed already gave us.
        guard result.wordCount >= minimumWordCount, Double(result.wordCount) > Double(summaryWords) * 1.3 else {
            return nil
        }
        return result
    }

    // MARK: - Scanning

    struct ScannedBlock {
        var block: ExtractedArticle.Block
        /// Non-skipped markup seen since the previous block ended.
        var gapBefore: Int
    }

    static func scanBlocks(in html: String) -> [ScannedBlock] {
        let ns = html as NSString
        var stack: [(name: String, skips: Bool)] = []
        var skippingDepth = 0
        var blocks: [ScannedBlock] = []
        var buffer: String?
        var bufferTag: String?
        var linkText = ""
        var anchorDepth = 0
        var gap = 0
        var gapAtBlockStart = 0
        var cursor = 0

        func finishBlock() {
            guard let tag = bufferTag, let text = buffer else { return }
            let normalized = HTMLSanitizer.normalizeWhitespace(HTMLSanitizer.decodeEntities(text))
            let linkLength = HTMLSanitizer.normalizeWhitespace(HTMLSanitizer.decodeEntities(linkText)).count
            // Mostly-link blocks are navigation ("See also", tag lists, "Continue Reading").
            let isMostlyLinks = Double(linkLength) / Double(max(normalized.count, 1)) > 0.5
            if let kind = blockKinds[tag], !normalized.isEmpty, !isMostlyLinks,
               kind != .listItem || normalized.count >= 20 {
                // Code keeps its line breaks and indentation.
                let blockText = kind == .code
                    ? HTMLSanitizer.decodeEntities(text).trimmingCharacters(in: .newlines)
                    : normalized
                blocks.append(ScannedBlock(block: .init(kind: kind, text: blockText), gapBefore: gapAtBlockStart))
            }
            if !normalized.isEmpty {
                gap = 0
            }
            buffer = nil
            bufferTag = nil
            linkText = ""
            anchorDepth = 0
        }

        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let textRange = NSRange(location: cursor, length: match.range.location - cursor)
            cursor = match.range.location + match.range.length

            if skippingDepth == 0 {
                if buffer != nil {
                    let text = ns.substring(with: textRange)
                    buffer?.append(text)
                    if anchorDepth > 0 { linkText.append(text) }
                } else {
                    gap += textRange.length + match.range.length
                }
            }

            let isClosing = ns.substring(with: match.range(at: 1)) == "/"
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let attributes = ns.substring(with: match.range(at: 3))

            if name == "br" {
                buffer?.append(" ")
                continue
            }
            if name == "a", buffer != nil {
                anchorDepth = max(0, anchorDepth + (isClosing ? -1 : 1))
            }

            if isClosing {
                if let index = stack.lastIndex(where: { $0.name == name }) {
                    skippingDepth -= stack[index...].filter(\.skips).count
                    stack.removeSubrange(index...)
                }
                if name == bufferTag, skippingDepth == 0 {
                    finishBlock()
                }
                continue
            }

            if voidElements.contains(name) || attributes.hasSuffix("/") {
                continue
            }

            // Like the HTML parser: a block-level start tag implicitly closes an open <p>. Some sites
            // inject "related content" boxes inside unclosed paragraphs.
            if bufferTag == "p", skippingDepth == 0, paragraphClosers.contains(name) {
                finishBlock()
                if let index = stack.lastIndex(where: { $0.name == "p" }) {
                    skippingDepth -= stack[index...].filter(\.skips).count
                    stack.removeSubrange(index...)
                }
            }

            let skips = skippedElements.contains(name)
                || (!neverSkippedByClass.contains(name) && looksLikeBoilerplate(attributes))
            stack.append((name, skips))
            if skips { skippingDepth += 1 }

            if buffer == nil, skippingDepth == 0, blockKinds[name] != nil {
                buffer = ""
                bufferTag = name
                gapAtBlockStart = gap
            }
        }
        return blocks
    }

    /// Matches keywords against the *parts* of class/id tokens ("comments-container" → "comments"),
    /// not substrings, so e.g. Wikipedia's `vector-feature-main-menu-pinned` on <body> can't hide the page.
    private static func looksLikeBoilerplate(_ attributes: String) -> Bool {
        let ns = attributes as NSString
        for match in classOrIDRegex.matches(in: attributes, range: NSRange(location: 0, length: ns.length)) {
            let parts = ns.substring(with: match.range(at: 1)).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for part in parts {
                if boilerplateExactParts.contains(String(part)) || boilerplatePrefixes.contains(where: { part.hasPrefix($0) }) {
                    return true
                }
            }
        }
        return false
    }

    static func splitIntoRuns(_ blocks: [ScannedBlock]) -> [[ScannedBlock]] {
        var runs: [[ScannedBlock]] = []
        for block in blocks {
            if block.gapBefore > regionGapThreshold || runs.isEmpty {
                runs.append([block])
            } else {
                runs[runs.count - 1].append(block)
            }
        }
        return runs
    }

    /// Figures, tables and embeds inside an article also produce big gaps, so neighboring runs that
    /// are themselves mostly prose and not too far away are treated as the same article.
    static func mergedSpan(around index: Int, in runs: [[ScannedBlock]]) -> ClosedRange<Int> {
        let maxGap = regionGapThreshold * 4
        func belongs(_ run: [ScannedBlock]) -> Bool {
            let prose = proseWords(in: run)
            let total = run.reduce(0) { $0 + $1.block.text.split(whereSeparator: \.isWhitespace).count }
            return run[0].gapBefore <= maxGap && prose >= 40 && Double(prose) >= Double(total) * 0.6
        }
        var lower = index
        var upper = index
        // runs[i] joins the previous run only if runs[i]'s own gap is moderate.
        while lower > 0, runs[lower][0].gapBefore <= maxGap, belongs(runs[lower - 1]) {
            lower -= 1
        }
        while upper + 1 < runs.count, belongs(runs[upper + 1]) {
            upper += 1
        }
        return lower...upper
    }

    /// Paragraphs and quotes only, so long link or tag lists can't outscore the article itself.
    static func proseWords(in run: [ScannedBlock]) -> Int {
        run.reduce(0) { total, scanned in
            guard scanned.block.kind == .paragraph || scanned.block.kind == .quote else { return total }
            return total + scanned.block.text.split(whereSeparator: \.isWhitespace).count
        }
    }

    // MARK: - Anchoring

    private static func summaryAnchor(_ summary: String?) -> String? {
        guard let summary else { return nil }
        let text = HTMLSanitizer.stripTags(from: summary).lowercased()
        guard text.count >= 30 else { return nil }
        return String(text.prefix(40))
    }

    private static func locate(anchor: String, in runs: [[ScannedBlock]]) -> (Int, Int)? {
        for (runIndex, run) in runs.enumerated() {
            if let blockIndex = run.firstIndex(where: { $0.block.text.lowercased().hasPrefix(anchor) }) {
                return (runIndex, blockIndex)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func leadImage(in html: String, baseURL: URL) -> String? {
        let ns = html as NSString
        guard let match = ogImageRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        guard range.location != NSNotFound else { return nil }
        let value = HTMLSanitizer.decodeEntities(ns.substring(with: range))
        return URL(string: value, relativeTo: baseURL)?.absoluteString
    }

    private static func decode(_ data: Data, response: HTTPURLResponse) -> String? {
        if let charset = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let string = String(data: data, encoding: encoding) {
                    return string
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1254)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
