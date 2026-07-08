import XCTest
import SwiftUI
@testable import SequencerAI

final class WaveformViewLayoutTests: XCTestCase {
    func test_fittedBucketsDownsamplesToDrawableCapacityUsingPeaks() {
        let buckets: [Float] = [0.1, 0.8, 0.2, 0.4, 0.9, 0.3, 0.6, 0.5]

        let fitted = WaveformView.fittedBuckets(
            buckets,
            width: 16,
            maxBarWidth: 3,
            spacing: 1
        )

        XCTAssertEqual(fitted.count, 4)
        XCTAssertEqual(fitted, [0.8, 0.4, 0.9, 0.6])
    }

    func test_fittedBucketsKeepsBucketsWhenTheyFit() {
        let buckets: [Float] = [0.1, 0.2, 0.3]

        let fitted = WaveformView.fittedBuckets(
            buckets,
            width: 100,
            maxBarWidth: 3,
            spacing: 1
        )

        XCTAssertEqual(fitted, buckets)
    }
}
