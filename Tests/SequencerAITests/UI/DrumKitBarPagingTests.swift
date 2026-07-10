import XCTest
@testable import SequencerAI

/// Pure page-math tests for the kit matrix's 16-step bar pager (AC3.1).
/// These exercise the boundaries the SwiftUI view used to hide behind private
/// helpers: empty rows, the exact one-page edge, the spill into a second page,
/// a full two-bar row, and the clamp that catches a stale page after shrink.
final class DrumKitBarPagingTests: XCTestCase {
    private let stepsPerBar = 16

    func test_pageCount_zeroSteps_isOnePage() {
        // An empty kit still renders a single 16-step window.
        XCTAssertEqual(
            DrumKitBarPaging.pageCount(length: 0, stepsPerBar: stepsPerBar),
            1
        )
    }

    func test_pageCount_exactlyOneBar_isOnePage() {
        XCTAssertEqual(
            DrumKitBarPaging.pageCount(length: 16, stepsPerBar: stepsPerBar),
            1
        )
    }

    func test_pageCount_oneStepOverOneBar_isTwoPages() {
        // 17 steps spill the partial 17th into its own page.
        XCTAssertEqual(
            DrumKitBarPaging.pageCount(length: 17, stepsPerBar: stepsPerBar),
            2
        )
    }

    func test_pageCount_exactlyTwoBars_isTwoPages() {
        XCTAssertEqual(
            DrumKitBarPaging.pageCount(length: 32, stepsPerBar: stepsPerBar),
            2
        )
    }

    func test_clampedPage_staleIndexAfterShrink_clampsToLastPage() {
        // A page index left over from a longer row (e.g. page 2 of a 3-bar row)
        // must clamp to the last valid page when the row shrinks to one bar.
        XCTAssertEqual(
            DrumKitBarPaging.clampedPage(2, length: 16, stepsPerBar: stepsPerBar),
            0
        )
        // Shrinking from 3 bars to 2 bars clamps page 2 to page 1.
        XCTAssertEqual(
            DrumKitBarPaging.clampedPage(2, length: 32, stepsPerBar: stepsPerBar),
            1
        )
    }

    func test_clampedPage_negativeIndex_clampsToZero() {
        XCTAssertEqual(
            DrumKitBarPaging.clampedPage(-3, length: 32, stepsPerBar: stepsPerBar),
            0
        )
    }

    func test_clampedPage_inRangeIndex_isUnchanged() {
        XCTAssertEqual(
            DrumKitBarPaging.clampedPage(1, length: 32, stepsPerBar: stepsPerBar),
            1
        )
    }

    func test_indicators_areAlwaysEightWithUnavailableTail() {
        let indicators = DrumKitBarPaging.indicators(pageCount: 3, currentPage: 1)

        XCTAssertEqual(indicators.count, 8)
        XCTAssertEqual(indicators.map(\.page), Array(0..<8))
        XCTAssertEqual(
            indicators.map(\.state),
            [.available, .current, .available, .unavailable, .unavailable, .unavailable, .unavailable, .unavailable]
        )
    }

    func test_indicators_bankLegacyPagesBeyond128Steps() {
        let indicators = DrumKitBarPaging.indicators(pageCount: 11, currentPage: 9)

        XCTAssertEqual(indicators.map(\.page), Array(8..<16))
        XCTAssertEqual(indicators[1].state, .current)
        XCTAssertEqual(indicators[2].state, .available)
        XCTAssertEqual(indicators[3].state, .unavailable)
        XCTAssertEqual(DrumKitBarPaging.previousBankPage(currentPage: 9), 0)
        XCTAssertNil(DrumKitBarPaging.nextBankPage(pageCount: 11, currentPage: 9))
        XCTAssertEqual(DrumKitBarPaging.nextBankPage(pageCount: 17, currentPage: 9), 16)
    }
}
