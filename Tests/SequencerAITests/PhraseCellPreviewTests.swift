import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

final class PhraseCellPreviewTests: XCTestCase {
    private let track = StepSequenceTrack(
        id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
        name: "Track",
        trackType: .monoMelodic,
        pitches: [60],
        stepPattern: Array(repeating: true, count: 16),
        velocity: 100,
        gateLength: 4
    )

    private var defaultLayers: [PhraseLayerDefinition] {
        PhraseLayerDefinition.defaultSet(for: [track])
    }

    func test_toggled_boolean_value_uses_normalized_layer_semantics() {
        let muteLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "mute" })!

        XCTAssertEqual(toggledBooleanValue(.scalar(0), for: muteLayer), .bool(true))
        XCTAssertEqual(toggledBooleanValue(.scalar(1), for: muteLayer), .bool(false))
        XCTAssertEqual(toggledBooleanValue(.index(0), for: muteLayer), .bool(true))
        XCTAssertEqual(toggledBooleanValue(.index(1), for: muteLayer), .bool(false))
    }

    func test_cycled_value_wraps_pattern_indexes() {
        let patternLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "pattern" })!

        XCTAssertEqual(cycledValue(.index(15), for: patternLayer), .index(0))
        XCTAssertEqual(cycledValue(.index(0), for: patternLayer), .index(1))
    }

    func test_cycled_value_advances_scalar_by_quarters_of_layer_range() {
        let volumeLayer = PhraseLayerDefinition.defaultSet(for: [track]).first(where: { $0.id == "volume" })!

        XCTAssertEqual(cycledValue(.scalar(0), for: volumeLayer), .scalar(31.75))
        XCTAssertEqual(cycledValue(.scalar(127), for: volumeLayer), .scalar(0))
    }

    func test_boolean_preview_renders_mute_special_case() {
        let muteLayer = defaultLayers.first(where: { $0.id == "mute" })!
        let preview = BooleanCellPreview(
            layer: muteLayer,
            resolvedValue: .bool(true),
            accent: StudioTheme.success,
            isMixed: false,
            metrics: .matrix
        )

        XCTAssertTrue(preview.booleanState)
        XCTAssertEqual(preview.booleanLabel, "Muted")
    }

    func test_scalar_preview_clamps_fillRatio() {
        let volumeLayer = defaultLayers.first(where: { $0.id == "volume" })!
        let loudPreview = ScalarCellPreview(
            layer: volumeLayer,
            cell: .single(.scalar(999)),
            resolvedValue: .scalar(999),
            accent: StudioTheme.cyan,
            summary: "999%",
            isMixed: false,
            metrics: .matrix
        )
        let quietPreview = ScalarCellPreview(
            layer: volumeLayer,
            cell: .single(.scalar(-10)),
            resolvedValue: .scalar(-10),
            accent: StudioTheme.cyan,
            summary: "-10%",
            isMixed: false,
            metrics: .matrix
        )

        XCTAssertEqual(loudPreview.clampedFillRatio, 1)
        XCTAssertEqual(quietPreview.clampedFillRatio, 0)
    }

    func test_pattern_index_preview_highlights_current_slot_in_pattern_colour() {
        let patternLayer = defaultLayers.first(where: { $0.id == "pattern" })!
        let preview = PatternIndexCellPreview(
            layer: patternLayer,
            resolvedValue: .index(3),
            accent: StudioTheme.violet,
            summary: "P4",
            isMixed: false,
            metrics: .matrix
        )

        XCTAssertEqual(preview.activeIndex, 3)
        // Bold-flat pass: the active slot is a fully solid phrase accent.
        XCTAssertEqual(
            String(describing: preview.slotFill(for: 3)),
            String(describing: StudioTheme.violet)
        )
        XCTAssertNotEqual(String(describing: preview.slotFill(for: 2)), String(describing: preview.slotFill(for: 3)))
        XCTAssertEqual(
            String(describing: preview.slotStroke(for: 2)),
            String(describing: StudioTheme.violet)
        )
    }

    @MainActor
    func test_pattern_index_preview_clicks_exact_slots_at_centerAndPaddedEdge() throws {
        let patternLayer = try XCTUnwrap(defaultLayers.first(where: { $0.id == "pattern" }))
        var selectedSlots: [Int] = []
        let preview = PatternIndexCellPreview(
            layer: patternLayer,
            resolvedValue: .index(0),
            accent: StudioTheme.violet,
            summary: "P1",
            isMixed: false,
            metrics: .matrix,
            onSelectSlot: { selectedSlots.append($0) }
        )
        .frame(width: 180, height: CellPreviewMetrics.matrix.valueHeight)

        let host = NSHostingView(rootView: preview)
        host.frame = NSRect(x: 0, y: 0, width: 180, height: CellPreviewMetrics.matrix.valueHeight)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        // The first synthetic click activates the off-screen test window on
        // macOS. It is harness setup, not part of the assertion.
        click(host: host, window: window, at: NSPoint(x: 24, y: 72))
        selectedSlots.removeAll()

        // With 4pt outer/grid spacing, each allocation is 40x16pt. P7 is
        // pressed centrally; P11 is pressed one point inside its rectangular
        // allocation, outside the rounded label corner but inside the Button's
        // expanded content shape.
        click(host: host, window: window, at: NSPoint(x: 112, y: 32))
        click(host: host, window: window, at: NSPoint(x: 94, y: 46))

        XCTAssertEqual(selectedSlots, [6, 10])
    }

    @MainActor
    private func click(host: NSView, window: NSWindow, at point: NSPoint) {
        let location = host.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )
            if let event {
                window.sendEvent(event)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
