import XCTest
@testable import SequencerAI

/// The strip scaffold's alignment contract: every strip kind shares the same
/// fixed slot heights, so identical elements line up row-for-row, and the
/// one Add Bus tile matches the strip footprint (ux-canon rules 5 and 9).
final class StudioMixerStripScaffoldTests: XCTestCase {
    func test_stripHeightSumsSlotsSpacingAndPadding() {
        let slots = StudioMixerStripMetrics.headerHeight
            + StudioMixerStripMetrics.processingHeight
            + StudioMixerStripMetrics.levelsHeight
            + StudioMixerStripMetrics.panHeight
            + StudioMixerStripMetrics.actionsHeight
            + StudioMixerStripMetrics.footerHeight
        let expected = slots
            + StudioMixerStripMetrics.slotSpacing * 5
            + StudioMixerStripMetrics.stripPadding * 2

        XCTAssertEqual(StudioMixerStripMetrics.stripHeight, expected)
    }

    func test_levelsSlotFitsFaderAndReadout() {
        // Fader plus an in-slot dB readout must fit the fixed levels slot;
        // overflow here is what made the bus faders sit lower than tracks.
        XCTAssertGreaterThanOrEqual(
            StudioMixerStripMetrics.levelsHeight,
            StudioMixerStripMetrics.faderSize.height + 16
        )
    }

    func test_masterStripOnlyKeepsScaleRoomItActuallyUses() {
        XCTAssertLessThan(StudioMixerStripMetrics.stripWidth, StudioMixerStripMetrics.masterWidth)
        XCTAssertLessThanOrEqual(StudioMixerStripMetrics.masterWidth, StudioMixerStripMetrics.stripWidth + 24)
        XCTAssertEqual(MixerWorkspaceLayout.busStripWidth, StudioMixerStripMetrics.stripWidth)
        XCTAssertEqual(MixerWorkspaceLayout.sendReturnStripWidth, StudioMixerStripMetrics.stripWidth)
    }

    func test_stripSlotsFitCompactRotaryPanControl() {
        XCTAssertGreaterThanOrEqual(StudioMixerStripMetrics.panHeight, 34 + 18)
    }

    func test_stripIdentityUsesStandardBorderAndOnlyEmphasisAddsWeight() {
        XCTAssertEqual(StudioMixerStripMetrics.identityBorderWidth, StudioMetrics.borderWidth)
        XCTAssertGreaterThan(
            StudioMixerStripMetrics.emphasizedBorderWidth,
            StudioMixerStripMetrics.identityBorderWidth
        )
    }

    func test_scrollbarChromeHidesWithoutOverflow() {
        XCTAssertFalse(StudioScrollbarMetrics.isOverflowing(contentLength: 120, viewportLength: 120))
        XCTAssertFalse(StudioScrollbarMetrics.isOverflowing(contentLength: 121, viewportLength: 120))
        XCTAssertEqual(
            StudioScrollbarMetrics.thumbLength(
                contentLength: 120,
                viewportLength: 120,
                trackLength: 100,
                minimumLength: 34
            ),
            100
        )
    }

    func test_scrollbarChromeCalculatesOverflowThumbAndClampsOffset() {
        XCTAssertTrue(StudioScrollbarMetrics.isOverflowing(contentLength: 400, viewportLength: 100))
        let thumbLength = StudioScrollbarMetrics.thumbLength(
            contentLength: 400,
            viewportLength: 100,
            trackLength: 100,
            minimumLength: 20
        )
        XCTAssertEqual(thumbLength, 25, accuracy: 0.001)
        XCTAssertEqual(
            StudioScrollbarMetrics.thumbOffset(
                contentLength: 400,
                viewportLength: 100,
                contentOffset: 150,
                trackLength: 100,
                thumbLength: thumbLength
            ),
            37.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StudioScrollbarMetrics.thumbOffset(
                contentLength: 400,
                viewportLength: 100,
                contentOffset: 999,
                trackLength: 100,
                thumbLength: thumbLength
            ),
            75,
            accuracy: 0.001
        )
    }

    func test_scrollChromeDiscoveryChoosesNestedListOverOuterWorkspace() {
        let target = NSRect(x: 320, y: 140, width: 320, height: 360)
        let outerWorkspace = NSRect(x: 24, y: 24, width: 1_040, height: 720)
        let listViewport = NSRect(x: 320, y: 140, width: 320, height: 360)

        XCTAssertEqual(
            StudioScrollChromeDiscovery.nearestMatchingCandidate(
                targetRect: target,
                candidateRects: [outerWorkspace, listViewport]
            ),
            1
        )
    }

    func test_scrollChromeDiscoveryRejectsNonOverlappingCandidates() {
        let target = NSRect(x: 320, y: 140, width: 320, height: 360)
        let unrelated = NSRect(x: 0, y: 0, width: 280, height: 120)

        XCTAssertNil(
            StudioScrollChromeDiscovery.nearestMatchingCandidate(
                targetRect: target,
                candidateRects: [unrelated]
            )
        )
    }

    func test_scrollChromeDiscoveryRejectsOuterWorkspaceWhenListIsNotReady() {
        let target = NSRect(x: 320, y: 140, width: 320, height: 360)
        let outerWorkspace = NSRect(x: 24, y: 24, width: 1_040, height: 720)

        XCTAssertNil(
            StudioScrollChromeDiscovery.nearestMatchingCandidate(
                targetRect: target,
                candidateRects: [outerWorkspace]
            )
        )
    }

    // MARK: - dB convergence

    func test_dBLabelConvergesOnMasterVocabulary() {
        XCTAssertEqual(StudioLevelFormat.dBLabel(forLinear: 0), "-inf")
        XCTAssertEqual(StudioLevelFormat.dBLabel(forLinear: 1), "0 dB")
        XCTAssertEqual(StudioLevelFormat.dBLabel(forLinear: 0.5), "-6.0")
        XCTAssertEqual(StudioLevelFormat.dBLabel(forLinear: 0.25), "-12.0")
    }

    func test_dBFSLabelForMeterOnlyLanes() {
        XCTAssertEqual(StudioLevelFormat.dBFSLabel(forPeak: -Double.infinity), "-inf")
        XCTAssertEqual(StudioLevelFormat.dBFSLabel(forPeak: -6.02), "-6.0")
        XCTAssertEqual(StudioLevelFormat.dBFSLabel(forPeak: 0), "0.0")
    }

    // MARK: - Slide control model (pan and master blend)

    func test_slideControlValuePositionRoundTrip() {
        let range: ClosedRange<Double> = -1...1
        XCTAssertEqual(StudioSlideControlModel.normalized(0, in: range), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StudioSlideControlModel.normalized(-1, in: range), 0, accuracy: 0.0001)
        XCTAssertEqual(StudioSlideControlModel.normalized(1, in: range), 1, accuracy: 0.0001)

        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: 50, width: 100, range: range), 0, accuracy: 0.0001)
        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: 0, width: 100, range: range), -1, accuracy: 0.0001)
        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: 100, width: 100, range: range), 1, accuracy: 0.0001)
    }

    func test_slideControlClampsOutOfBoundsDrags() {
        let range: ClosedRange<Double> = 0...1
        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: -25, width: 100, range: range), 0)
        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: 160, width: 100, range: range), 1)
        XCTAssertEqual(StudioSlideControlModel.value(forLocationX: 50, width: 0, range: range), 0)
    }

    func test_slideControlAccessibilityAdjustmentUsesRequestedStepAndClamps() {
        let range: ClosedRange<Double> = 0...1
        XCTAssertEqual(
            StudioSlideControlModel.adjustedValue(0.4, incrementing: true, step: 0.05, range: range),
            0.45,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StudioSlideControlModel.adjustedValue(0.02, incrementing: false, step: 0.05, range: range),
            0
        )
        XCTAssertEqual(
            StudioSlideControlModel.adjustedValue(0.98, incrementing: true, step: 0.05, range: range),
            1
        )
    }

    func test_panLabelUsesCompactVocabulary() {
        XCTAssertEqual(StudioSlideControlModel.panLabel(for: 0), "C")
        XCTAssertEqual(StudioSlideControlModel.panLabel(for: -0.5), "L50")
        XCTAssertEqual(StudioSlideControlModel.panLabel(for: 0.25), "R25")
        XCTAssertEqual(StudioSlideControlModel.panLabel(for: -1), "L100")
        XCTAssertEqual(StudioSlideControlModel.panLabel(for: 1), "R100")
    }
}
