import XCTest
@testable import Sift

final class StoryClusteringSpikeTests: XCTestCase {
    func testCosineSimilarityHandlesEqualOrthogonalAndInvalidVectors() {
        XCTAssertEqual(StoryClusteringSpike.cosineSimilarity([1, 0], [1, 0])!, 1, accuracy: 0.000_001)
        XCTAssertEqual(StoryClusteringSpike.cosineSimilarity([1, 0], [0, 1])!, 0, accuracy: 0.000_001)
        XCTAssertNil(StoryClusteringSpike.cosineSimilarity([1], [1, 0]))
        XCTAssertNil(StoryClusteringSpike.cosineSimilarity([0, 0], [1, 0]))
    }

    func testRunningMeanWeightsEachArticleEqually() {
        let result = StoryClusteringSpike.runningMean([1, 0], [0, 1], existingCount: 1)

        XCTAssertEqual(result[0], 0.5, accuracy: 0.000_001)
        XCTAssertEqual(result[1], 0.5, accuracy: 0.000_001)
    }

    func testRunningMeanStartsNewCentroidWhenExistingCountIsZero() {
        XCTAssertEqual(StoryClusteringSpike.runningMean([], [0.2, 0.8], existingCount: 0), [0.2, 0.8])
    }

    func testEquivalentEnglishPivotRepresentationsCanJoinAcrossSourceLanguages() {
        // These vectors stand in for two Apple Translation + Natural Language
        // outputs after the Turkish and English reports are normalized to English.
        let turkishReportVector = [0.8, 0.6]
        let englishReportVector = [0.8, 0.6]
        let similarity = StoryClusteringSpike.cosineSimilarity(
            turkishReportVector,
            englishReportVector
        )

        let decision = StoryClusteringSpike.candidateDecision(
            centroidSimilarity: similarity,
            eventSignatureCompatible: nil,
            representativeSimilarity: similarity,
            recentMemberSimilarities: [similarity],
            candidateActionTerms: ["announce"],
            representativeActionTerms: ["announce"],
            threshold: 0.82
        )

        XCTAssertEqual(decision, .accepted)
    }

    func testBroadTopicCentroidCannotMergeDistinctEventsWithoutRepresentativeSupport() {
        let decision = StoryClusteringSpike.candidateDecision(
            centroidSimilarity: 0.91,
            eventSignatureCompatible: nil,
            representativeSimilarity: 0.73,
            recentMemberSimilarities: [0.74, 0.76],
            candidateActionTerms: ["announce"],
            representativeActionTerms: ["announce"],
            threshold: 0.82
        )

        XCTAssertEqual(decision, .rejectedRepresentativeSimilarity)
    }

    func testDifferentReportedActionsDoNotMergeJustBecauseTopicCentroidIsClose() {
        let decision = StoryClusteringSpike.candidateDecision(
            centroidSimilarity: 0.90,
            eventSignatureCompatible: nil,
            representativeSimilarity: 0.90,
            recentMemberSimilarities: [0.90],
            candidateActionTerms: ["approve"],
            representativeActionTerms: ["reject"],
            threshold: 0.82
        )

        XCTAssertEqual(decision, .rejectedActionMismatch)
    }

    func testNearDuplicateCanOverrideDifferentActionWords() {
        let decision = StoryClusteringSpike.candidateDecision(
            centroidSimilarity: 0.99,
            eventSignatureCompatible: nil,
            representativeSimilarity: 0.99,
            recentMemberSimilarities: [0.99],
            candidateActionTerms: ["approve"],
            representativeActionTerms: ["reject"],
            threshold: 0.82
        )

        XCTAssertEqual(decision, .accepted)
    }

    func testRecentMemberSupportPreventsCentroidDrift() {
        let decision = StoryClusteringSpike.candidateDecision(
            centroidSimilarity: 0.87,
            eventSignatureCompatible: nil,
            representativeSimilarity: 0.87,
            recentMemberSimilarities: [0.92, 0.71],
            candidateActionTerms: [],
            representativeActionTerms: [],
            threshold: 0.82
        )

        XCTAssertEqual(decision, .rejectedRecentMemberSupport)
    }

    func testCandidateWindowUsesCorpusTimelineAndKeepsExactBoundary() {
        let clusterTime = Date(timeIntervalSince1970: 1_000)
        let exactBoundary = clusterTime.addingTimeInterval(72 * 60 * 60)
        let justOutside = exactBoundary.addingTimeInterval(1)

        XCTAssertFalse(StoryClusteringSpike.isOutsideCandidateWindow(
            articleTime: exactBoundary,
            clusterTime: clusterTime,
            candidateWindow: 72 * 60 * 60
        ))
        XCTAssertTrue(StoryClusteringSpike.isOutsideCandidateWindow(
            articleTime: justOutside,
            clusterTime: clusterTime,
            candidateWindow: 72 * 60 * 60
        ))
    }
}
