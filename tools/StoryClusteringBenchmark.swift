import Foundation
import CryptoKit
import Darwin

private struct BenchmarkMetadata: Encodable {
    let runStartedAt: Date
    let corpusSHA256: String
    let articleCount: Int
    let osVersion: String
    let hardwareModel: String?
    let processorCount: Int
    let totalProcessingMilliseconds: Double
}

private struct BenchmarkOutput: Encodable {
    let benchmark: BenchmarkMetadata
    let clustering: StoryClusteringSpikeResult
}

private struct CorpusRecord: Decodable {
    let id: UUID
    let title: String
    let summary: String?
    let fullText: String?
    let publisherKey: String
    let publishedAt: Date
    let goldStoryID: String?

    var article: StoryClusteringArticle {
        StoryClusteringArticle(
            id: id,
            title: title,
            summary: summary,
            fullText: fullText,
            publisherKey: publisherKey,
            publishedAt: publishedAt
        )
    }
}

private struct EvaluatorRecord: Encodable {
    let articleID: String
    let goldStoryID: String
    let predictedClusterID: String
    let language: String
}

private struct Options {
    var input: URL?
    var evaluatorOutput: URL?
    var assignmentsOutput: URL?
    var assignmentsToStandardOutput = false
    var analysisLocale = "en"
    var threshold: Double?
    var windowHours = 72.0
    var translationStrategy = StoryClusteringSpike.TranslationStrategy.highFidelity
    var eventSignaturesEnabled = false

    init(arguments: [String]) throws {
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else {
                throw BenchmarkError.usage("Missing value for \(flag)")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--input": input = value == "-" ? URL(fileURLWithPath: "/dev/stdin") : URL(fileURLWithPath: value)
            case "--evaluator-output":
                guard value != "-" else {
                    throw BenchmarkError.usage("--evaluator-output must be a file path")
                }
                evaluatorOutput = URL(fileURLWithPath: value)
            case "--assignments-output":
                if value == "-" {
                    assignmentsToStandardOutput = true
                } else {
                    assignmentsOutput = URL(fileURLWithPath: value)
                }
            case "--locale": analysisLocale = value
            case "--threshold":
                guard let parsed = Double(value), (0...1).contains(parsed) else {
                    throw BenchmarkError.usage("--threshold must be between 0 and 1")
                }
                threshold = parsed
            case "--window-hours":
                guard let parsed = Double(value), parsed > 0 else {
                    throw BenchmarkError.usage("--window-hours must be greater than 0")
                }
                windowHours = parsed
            case "--translation-strategy":
                guard let parsed = StoryClusteringSpike.TranslationStrategy(rawValue: value) else {
                    throw BenchmarkError.usage("--translation-strategy must be lowLatency or highFidelity")
                }
                translationStrategy = parsed
            case "--event-signatures":
                guard value == "enabled" || value == "disabled" else {
                    throw BenchmarkError.usage("--event-signatures must be enabled or disabled")
                }
                eventSignaturesEnabled = value == "enabled"
            default:
                throw BenchmarkError.usage("Unknown option: \(flag)")
            }
            index += 2
        }

        guard input != nil, (assignmentsOutput != nil || assignmentsToStandardOutput), threshold != nil else {
            throw BenchmarkError.usage(
                "Required: --input corpus.jsonl|- --assignments-output assignments.json|- --threshold value"
            )
        }
        if evaluatorOutput != nil, assignmentsToStandardOutput {
            throw BenchmarkError.usage("--assignments-output - cannot be combined with --evaluator-output")
        }
    }
}

private enum BenchmarkError: Error, CustomStringConvertible {
    case usage(String)
    case invalidRecord(line: Int, reason: String)

    var description: String {
        switch self {
        case .usage(let message):
            "\(message)\n\(Self.help)"
        case .invalidRecord(let line, let reason):
            "Input line \(line): \(reason)"
        }
    }

    static let help = """
    Usage:
      StoryClusteringBenchmark \
        --input corpus.jsonl|- \
        --assignments-output assignments.json \
        --threshold value [--evaluator-output predictions.jsonl] \
        [--locale en] [--window-hours 72] \
        [--translation-strategy lowLatency|highFidelity] \\
        [--event-signatures enabled|disabled] (default disabled for the NL baseline)

    Corpus JSONL fields: id (UUID), title, optional summary/fullText,
    publisherKey, publishedAt (ISO-8601), and optional manually assigned goldStoryID.
    Omit goldStoryID and --evaluator-output for an unscored shadow preview.
    Use --input - to read JSONL from stdin and --assignments-output - to write
    assignments JSON to stdout. Preview output contains IDs and assignments, not text.
    """
}

@main
private enum StoryClusteringBenchmark {
    static func main() async {
        do {
            if CommandLine.arguments.dropFirst().contains("--help") {
                print(BenchmarkError.help)
                return
            }
            let options = try Options(arguments: CommandLine.arguments)
            let corpusData = options.input?.path == "/dev/stdin"
                ? FileHandle.standardInput.readDataToEndOfFile()
                : try Data(contentsOf: options.input!)
            let records = try loadCorpus(from: corpusData)
            if options.evaluatorOutput != nil {
                for (offset, record) in records.enumerated() {
                    guard let goldStoryID = record.goldStoryID,
                          !goldStoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw BenchmarkError.invalidRecord(
                            line: offset + 1,
                            reason: "--evaluator-output requires a non-empty goldStoryID on every row"
                        )
                    }
                }
            }
            let spike = StoryClusteringSpike()
            let runStartedAt = Date()
            let processingStartedAt = ContinuousClock.now
            let result = await spike.cluster(
                records.map(\.article),
                analysisLocale: options.analysisLocale,
                similarityThreshold: options.threshold!,
                candidateWindow: options.windowHours * 60 * 60,
                translationStrategy: options.translationStrategy,
                eventSignaturesEnabled: options.eventSignaturesEnabled
            )
            let processingDuration = processingStartedAt.duration(to: .now)
            let totalMilliseconds = Double(processingDuration.components.seconds) * 1_000
                + Double(processingDuration.components.attoseconds) / 1_000_000_000_000_000

            let predictionByID = Dictionary(
                uniqueKeysWithValues: result.assignments.map { ($0.id, $0) }
            )
            if let evaluatorOutput = options.evaluatorOutput {
                let evaluatorRecords = records.map { record -> EvaluatorRecord in
                    let assignment = predictionByID[record.id]
                    // Keep failed/unsupported rows in scoring as singleton clusters so
                    // dropping hard language cases cannot inflate benchmark quality.
                    let predictedClusterID = assignment?.predictedClusterID
                        ?? "unassigned-\(record.id.uuidString.lowercased())"
                    return EvaluatorRecord(
                        articleID: record.id.uuidString.lowercased(),
                        goldStoryID: record.goldStoryID!,
                        predictedClusterID: predictedClusterID,
                        language: assignment?.detectedLanguage ?? "und"
                    )
                }
                try writeJSONLines(evaluatorRecords, to: evaluatorOutput)
            }

            let output = BenchmarkOutput(
                benchmark: BenchmarkMetadata(
                    runStartedAt: runStartedAt,
                    corpusSHA256: SHA256.hash(data: corpusData).map { String(format: "%02x", $0) }.joined(),
                    articleCount: records.count,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    hardwareModel: Self.hardwareModel(),
                    processorCount: ProcessInfo.processInfo.processorCount,
                    totalProcessingMilliseconds: totalMilliseconds
                ),
                clustering: result
            )
            if options.assignmentsToStandardOutput {
                try writeJSONToStandardOutput(output)
            } else {
                try writeJSON(output, to: options.assignmentsOutput!)
            }

            let assignedCount = result.assignments.filter { $0.predictedClusterID != nil }.count
            let unassignedCount = records.count - assignedCount
            FileHandle.standardError.write(Data((
                "Pipeline \(result.analysisPipelineVersion); model \(result.embeddingModelIdentifier) r\(result.embeddingModelRevision); " +
                "assigned \(assignedCount)/\(records.count), unassigned \(unassignedCount).\n"
            ).utf8))
            if unassignedCount > 0 {
                let explanation = options.evaluatorOutput == nil
                    ? "Inspect assignments for readiness and reasons."
                    : "Unassigned rows remain singleton predictions in the evaluator file. Inspect assignments for readiness and reasons."
                FileHandle.standardError.write(Data(
                    "\(explanation)\n"
                        .utf8
                ))
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func loadCorpus(from data: Data) throws -> [CorpusRecord] {
        let content = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var seenIDs = Set<UUID>()
        let records = try content
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .map { offset, line -> CorpusRecord in
                do {
                    let record = try decoder.decode(CorpusRecord.self, from: Data(line.utf8))
                    guard seenIDs.insert(record.id).inserted else {
                        throw BenchmarkError.invalidRecord(line: offset + 1, reason: "duplicate id \(record.id)")
                    }
                    return record
                } catch let error as BenchmarkError {
                    throw error
                } catch {
                    throw BenchmarkError.invalidRecord(line: offset + 1, reason: String(describing: error))
                }
            }
        guard !records.isEmpty else { throw BenchmarkError.usage("Input corpus is empty") }
        return records
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname("hw.model", buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(cString: bytes)
    }

    private static func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func writeJSONToStandardOutput<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(value))
        try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
    }
}
