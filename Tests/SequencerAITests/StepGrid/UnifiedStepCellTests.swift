import CoreGraphics
import XCTest
@testable import SequencerAI

final class UnifiedStepCellTests: XCTestCase {
    func test_compoundPlayingSelectedValueCellKeepsAllSignals() {
        let configuration = UnifiedStepCellVisualConfiguration(
            visualState: .on,
            isPlaying: true,
            isSelected: true,
            content: .valueBar(fraction: 0.7)
        )

        XCTAssertTrue(configuration.isActive)
        XCTAssertTrue(configuration.isPlaying)
        XCTAssertTrue(configuration.isSelected)
        XCTAssertTrue(configuration.showsCompoundPlayingSelection)
        XCTAssertEqual(configuration.valueFraction ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertGreaterThan(configuration.playingBorderInset, 0.5)
    }

    func test_selectedOffCellIsUnfilledButSelected() {
        let configuration = UnifiedStepCellVisualConfiguration(
            visualState: .off,
            isPlaying: false,
            isSelected: true,
            content: .toggle
        )

        XCTAssertFalse(configuration.isActive)
        XCTAssertFalse(configuration.isPlaying)
        XCTAssertTrue(configuration.isSelected)
        XCTAssertNil(configuration.valueFraction)
    }

    func test_toggleAndValueBarUseIdenticalGeometry() {
        let geometry = UnifiedStepCellGeometry()

        XCTAssertEqual(geometry.size(for: .toggle), geometry.size(for: .valueBar(fraction: 0.5)))
        XCTAssertEqual(geometry.size(for: .sliceLabel(index: 1, label: "S2")), geometry.size(for: .toggle))
        XCTAssertEqual(geometry.size(for: .chordLabel(name: "Am7")), geometry.size(for: .toggle))
        XCTAssertEqual(geometry.size(for: .optionLabel(text: "Run")), geometry.size(for: .toggle))
    }

    func test_valueFractionsClampToUnitRange() {
        let low = UnifiedStepCellVisualConfiguration(
            visualState: .off,
            isPlaying: false,
            isSelected: false,
            content: .valueBar(fraction: -0.2)
        )
        let high = UnifiedStepCellVisualConfiguration(
            visualState: .off,
            isPlaying: false,
            isSelected: false,
            content: .valueBar(fraction: 1.4)
        )

        XCTAssertEqual(low.valueFraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(high.valueFraction ?? -1, 1, accuracy: 0.0001)
    }

    func test_valueDragThresholdAndAbsoluteMapping() {
        XCTAssertFalse(UnifiedStepCellGesturePolicy.hasExceededDragThreshold(CGSize(width: 0, height: 3.9)))
        XCTAssertTrue(UnifiedStepCellGesturePolicy.hasExceededDragThreshold(CGSize(width: 0, height: 4)))
        XCTAssertEqual(
            UnifiedStepCellGesturePolicy.normalizedValue(locationY: 13, height: 52),
            0.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(UnifiedStepCellGesturePolicy.normalizedValue(locationY: -10, height: 52), 1, accuracy: 0.0001)
        XCTAssertEqual(UnifiedStepCellGesturePolicy.normalizedValue(locationY: 62, height: 52), 0, accuracy: 0.0001)
    }
}
