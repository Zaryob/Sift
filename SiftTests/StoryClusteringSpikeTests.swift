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
