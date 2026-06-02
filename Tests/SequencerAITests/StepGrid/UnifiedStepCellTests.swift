import AppKit
import CoreGraphics
import SwiftUI
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

    func test_stepGridViewCanSwitchTriggerToValueContentWithoutChangingCellGeometry() {
        let triggerGrid = StepGridView(
            stepStates: [.on, .off],
            advanceStep: { _ in }
        )
        var draggedStep: Int?
        var draggedValue: Double?
        let valueGrid = StepGridView(
            stepStates: [.on, .off],
            contentProvider: { index, _ in .valueBar(fraction: index == 0 ? 0.5 : 0) },
            onValueDrag: { index, value in
                draggedStep = index
                draggedValue = value
            },
            advanceStep: { _ in }
        )
        let geometry = UnifiedStepCellGeometry()

        let triggerContent = triggerGrid.contentProvider(0, .on)
        let valueContent = valueGrid.contentProvider(0, .on)

        XCTAssertEqual(triggerContent, .toggle)
        XCTAssertEqual(valueContent, .valueBar(fraction: 0.5))
        XCTAssertEqual(geometry.size(for: triggerContent), geometry.size(for: valueContent))

        valueGrid.onValueDrag?(3, 0.75)
        XCTAssertEqual(draggedStep, 3)
        XCTAssertEqual(draggedValue ?? -1, 0.75, accuracy: 0.0001)
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

    @MainActor
    func test_writesPhase2AVisualEvidenceCaptureWhenRequested() throws {
        // The macOS test host is sandboxed, so the default capture path stays inside its writable container.
        let outputPath = ProcessInfo.processInfo.environment["UNIFIED_STEP_CELL_VISUAL_EVIDENCE_PATH"]
            ?? "\(NSHomeDirectory())/tmp/sequencer-visual-review/2026-05-23T11-25Z-phase2a-unified-step-cell-states.png"

        let targetSize = CGSize(width: 280, height: 92)
        let outputURL = URL(fileURLWithPath: outputPath)
        let host = NSHostingView(rootView: UnifiedStepCellVisualEvidenceView())
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: targetSize)
        host.setFrameSize(targetSize)
        host.layoutSubtreeIfNeeded()

        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not allocate bitmap representation for visual evidence capture.")
            return
        }

        host.cacheDisplay(in: host.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode UnifiedStepCell visual evidence capture as PNG.")
            return
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)

        XCTAssertGreaterThan(pngData.count, 1_000)
    }

    @MainActor
    func test_writesPhase2CSlicerSelectionBatchVisualEvidence() throws {
        let outputPath = ProcessInfo.processInfo.environment["SLICER_STEP_STRIP_VISUAL_EVIDENCE_PATH"]
            ?? "\(NSHomeDirectory())/tmp/sequencer-visual-review/2026-06-02T10-45Z-phase2c-slicer-selection-batch.png"

        let targetSize = CGSize(width: 760, height: 132)
        let outputURL = URL(fileURLWithPath: outputPath)
        let host = NSHostingView(rootView: SliceStepStripVisualEvidenceView())
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: targetSize)
        host.setFrameSize(targetSize)
        host.layoutSubtreeIfNeeded()

        guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not allocate bitmap representation for slicer visual evidence capture.")
            return
        }

        host.cacheDisplay(in: host.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode slicer visual evidence capture as PNG.")
            return
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)

        XCTAssertGreaterThan(pngData.count, 1_000)
    }
}

private struct UnifiedStepCellVisualEvidenceView: View {
    var body: some View {
        HStack(spacing: 8) {
            UnifiedStepCell(
                visualState: .off,
                isPlaying: false,
                isSelected: true,
                content: .toggle,
                onTap: {},
                onDrag: nil,
                onSelect: {}
            )
            UnifiedStepCell(
                visualState: .on,
                isPlaying: true,
                isSelected: true,
                content: .valueBar(fraction: 0.7),
                onTap: {},
                onDrag: { _ in },
                onSelect: {}
            )
            UnifiedStepCell(
                visualState: .accented,
                isPlaying: false,
                isSelected: false,
                content: .sliceLabel(index: 3, label: "S4"),
                onTap: {},
                onDrag: nil,
                onSelect: {}
            )
            UnifiedStepCell(
                visualState: .on,
                isPlaying: false,
                isSelected: false,
                content: .chordLabel(name: "Am7"),
                onTap: {},
                onDrag: nil,
                onSelect: {}
            )
            UnifiedStepCell(
                visualState: .off,
                isPlaying: true,
                isSelected: false,
                content: .optionLabel(text: "Run"),
                onTap: {},
                onDrag: nil,
                onSelect: {}
            )
        }
        .padding(16)
        .frame(width: 280, height: 92)
        .background(StudioTheme.background)
    }
}

private struct SliceStepStripVisualEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliceStepStrip(
                stepStates: [
                    .on(sliceIndex: 0, mode: .single),
                    .on(sliceIndex: 3, mode: .runFromHere),
                    .off,
                    .on(sliceIndex: 5, mode: .single)
                ],
                indexOffset: 0,
                playingStepIndex: 1,
                selectedStepIndex: 1,
                selectedStepIndexes: [1],
                activeLayer: .velocity,
                contentProvider: { index, _ in
                    .valueBar(fraction: [0.35, 0.82, 0, 0.55][index])
                },
                onValueDrag: { _, _ in },
                onSelect: { _ in },
                onTap: { _ in }
            )

            SliceStepBatchActionBar(
                isVisible: true,
                canPaste: true,
                onClear: {},
                onCopy: {},
                onPaste: {}
            )
        }
        .padding(16)
        .frame(width: 760, height: 132, alignment: .topLeading)
        .background(StudioTheme.background)
    }
}
