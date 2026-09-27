import Foundation

private struct SnapshotArticle: Codable, Sendable {
    let id: UUID
    let title: String
    let summary: String?
    let publisherKey: String
    let publishedAt: String
    let url: String
    let language: String
    let feedName: String
    let feedCategory: String?
    var fullText: String?
    var fullTextExtractionStatus: String?
    var fullTextWordCount: Int?
}

private struct Options {
    var input: URL?
    var concurrency = 8

    init(arguments: [String]) throws {
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else {
                throw ExtractorError.usage("Missing value for \(flag)")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--input": input = URL(fileURLWithPath: value)
            case "--concurrency":
                guard let parsed = Int(value), (1...16).contains(parsed) else {
                    throw ExtractorError.usage("--concurrency must be between 1 and 16")
                }
                concurrency = parsed
            default: throw ExtractorError.usage("Unknown option: \(flag)")
            }
            index += 2
        }
        guard input != nil else { throw ExtractorError.usage("Required: --input snapshot.jsonl") }
    }
}

private enum ExtractorError: Error, CustomStringConvertible {
    case usage(String)
    case invalidRecord(Int, Error)

    var description: String {
        switch self {
        case .usage(let message): message
        case let .invalidRecord(line, error): "Input line \(line): \(error)"
        }
    }
}

@main
private enum ExtractM0ArticleBodies {
    static func main() async {
        do {
            let options = try Options(arguments: CommandLine.arguments)
            let data = try Data(contentsOf: options.input!)
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
            let decoder = JSONDecoder()
            let articles = try lines.enumerated().map { offset, line -> SnapshotArticle in
                do {
                    return try decoder.decode(SnapshotArticle.self, from: Data(line.utf8))
                } catch {
                    throw ExtractorError.invalidRecord(offset + 1, error)
                }
            }

            var output = articles
            var attempted = 0
            var extracted = 0
            for start in stride(from: 0, to: articles.count, by: options.concurrency) {
                let end = min(start + options.concurrency, articles.count)
                let batch = Array(articles[start..<end])
                let results = await withTaskGroup(of: (Int, SnapshotArticle).self) { group in
                    for (offset, article) in batch.enumerated() {
                        group.addTask {
                            var updated = article
                            guard let url = URL(string: article.url),
                                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                                updated.fullTextExtractionStatus = "invalidURL"
                                return (start + offset, updated)
                            }
                            do {
                                if let result = try await ArticleExtractor.fetch(url: url, summary: article.summary) {
                                    let text = result.blocks.map(\.text).joined(separator: "\n\n")
                                    let wordCount = text.split(whereSeparator: \.isWhitespace).count
                                    updated.fullText = text
                                    updated.fullTextWordCount = wordCount
                                    updated.fullTextExtractionStatus = "extracted"
                                } else {
                                    updated.fullTextExtractionStatus = "noReadableBody"
                                }
                            } catch {
                                updated.fullTextExtractionStatus = "fetchFailed"
                            }
                            return (start + offset, updated)
                        }
                    }
                    var gathered: [(Int, SnapshotArticle)] = []
                    for await item in group { gathered.append(item) }
                    return gathered
                }
                for (index, article) in results {
                    output[index] = article
                    attempted += 1
                    if article.fullTextExtractionStatus == "extracted" { extracted += 1 }
                }
                FileHandle.standardError.write(Data(
                    "Processed \(attempted)/\(articles.count); readable bodies \(extracted).\n".utf8
                ))
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            for article in output {
                FileHandle.standardOutput.write(try encoder.encode(article))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
