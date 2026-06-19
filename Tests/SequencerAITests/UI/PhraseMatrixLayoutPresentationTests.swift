import SwiftUI
import XCTest
@testable import SequencerAI

final class PhraseMatrixLayoutPresentationTests: XCTestCase {
    func test_firstPageKeepsPreviousArrowVisibleDisabledAndShowsNextOccupancy() {
        let layout = PhraseMatrixLayoutPresentation(trackCount: 12, pageIndex: 0)

        let previous = layout.arrow(for: .previous)
        let next = layout.arrow(for: .next)

        XCTAssertFalse(previous.isEnabled)
        XCTAssertNil(previous.occupancyHint)
        XCTAssertEqual(previous.adjacentTrackCount, 0)
        XCTAssertTrue(previous.accessibilityLabel.contains("unavailable"))

        XCTAssertTrue(next.isEnabled)
        XCTAssertEqual(next.occupancyHint, "4")
        XCTAssertEqual(next.adjacentTrackCount, 4)
    }

    func test_middlePageShowsPositiveOccupancyInBothDirections() {
        let layout = PhraseMatrixLayoutPresentation(trackCount: 20, pageIndex: 1)

        let previous = layout.arrow(for: .previous)
        let next = layout.arrow(for: .next)

        XCTAssertTrue(previous.isEnabled)
        XCTAssertEqual(previous.occupancyHint, "8")
        XCTAssertEqual(previous.adjacentTrackCount, 8)

        XCTAssertTrue(next.isEnabled)
        XCTAssertEqual(next.occupancyHint, "4")
        XCTAssertEqual(next.adjacentTrackCount, 4)
    }

    func test_finalPageKeepsNextArrowVisibleDisabledWithoutOccupancy() {
        let layout = PhraseMatrixLayoutPresentation(trackCount: 12, pageIndex: 1)

        let previous = layout.arrow(for: .previous)
        let next = layout.arrow(for: .next)

        XCTAssertTrue(previous.isEnabled)
        XCTAssertEqual(previous.occupancyHint, "8")

        XCTAssertFalse(next.isEnabled)
        XCTAssertNil(next.occupancyHint)
        XCTAssertEqual(next.adjacentTrackCount, 0)
        XCTAssertTrue(next.accessibilityLabel.contains("unavailable"))
    }

    func test_layerSelectorHasStableFixedWidthAcrossNamedLayers() {
        let layerNames = [
            "Pattern",
            "Transpose",
            "Variance %",
            "FX Send",
            "Mute",
            "Extremely Long User Authored FX Send Layer Label"
        ]

        let widths = Set(layerNames.map { layerName in
            PhraseLayerSelectorPresentation(
                layerName: layerName,
                subtitle: "track layer",
                indexLabel: "1 / 6"
            )
            .fixedOuterWidthForTesting
        })

        XCTAssertEqual(widths, [PhraseLayerSelectorPresentation.fixedOuterWidth])
        XCTAssertEqual(PhraseLayerSelectorPresentation.lineLimit, 1)
    }

    func test_layerSelectorUsesRuntimeBackedPhraseLayerOrderAndLabels() {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let selectableLayers = PhraseLayerSelectorPresentation.selectableLayers(from: layers)

        XCTAssertEqual(selectableLayers.map(\.id), ["pattern", "mute", "fill-flag"])
        XCTAssertEqual(
            selectableLayers.map { PhraseLayerSelectorPresentation.displayName(for: $0) },
            ["Pattern", "Mute", "Fill"]
        )
    }

    func test_defaultPhraseLayersCanIncludeFxSendWithoutExposingItInRuntimeBackedSelector() {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let fxSendLayer = layers.first { $0.id == "fx-send" }
        let selectableLayerIDs = PhraseLayerSelectorPresentation.selectableLayers(from: layers).map(\.id)

        XCTAssertEqual(fxSendLayer?.name, "FX Send")
        XCTAssertEqual(fxSendLayer?.valueType, .scalar)
        XCTAssertEqual(fxSendLayer?.minValue, 0)
        XCTAssertEqual(fxSendLayer?.maxValue, 1)
        XCTAssertEqual(fxSendLayer?.defaults[track.id], .scalar(0))
        XCTAssertFalse(selectableLayerIDs.contains("fx-send"))
    }

    func test_longLayerLabelKeepsFullAccessibilityText() {
        let longName = "Extremely Long User Authored FX Send Layer Label"
        let presentation = PhraseLayerSelectorPresentation(
            layerName: longName,
            subtitle: "macro param",
            indexLabel: "6 / 6"
        )

        XCTAssertEqual(presentation.displayName, longName.uppercased())
        XCTAssertTrue(presentation.accessibilityLabel.contains(longName))
        XCTAssertTrue(presentation.accessibilityLabel.contains("macro param"))
    }
}

private extension PhraseLayerSelectorPresentation {
    var fixedOuterWidthForTesting: CGFloat {
        Self.fixedOuterWidth
    }
}
