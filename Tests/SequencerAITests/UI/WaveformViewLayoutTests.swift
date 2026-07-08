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

    func test_fittedBucketsUpsamplesToDrawableCapacityWhenBucketsAreSparse() {
        let buckets: [Float] = [0.1, 0.2, 0.3]

        let fitted = WaveformView.fittedBuckets(
            buckets,
            width: 20,
            maxBarWidth: 3,
            spacing: 1
        )

        XCTAssertEqual(fitted.count, 5)
        XCTAssertEqual(fitted.first, 0.1, accuracy: 0.001)
        XCTAssertEqual(fitted.last, 0.3, accuracy: 0.001)
        XCTAssertEqual(fitted[2], 0.2, accuracy: 0.001)
    }

    func test_fittedBucketsRecalculatesCapacityFromWidth() {
        let buckets: [Float] = [0.1, 0.2, 0.3]

        let narrow = WaveformView.fittedBuckets(
            buckets,
            width: 20,
            maxBarWidth: 3,
            spacing: 1
        )
        let wide = WaveformView.fittedBuckets(
            buckets,
            width: 40,
            maxBarWidth: 3,
            spacing: 1
        )

        XCTAssertEqual(narrow.count, 5)
        XCTAssertEqual(wide.count, 10)
    }
}
