import SwiftUI
import XCTest
@testable import SequencerAI

/// Geometry + feel-constant coverage for the shared rotary template.
final class StudioRotaryControlTests: XCTestCase {

    // MARK: - StudioRotaryArc geometry

    private let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    /// Zero sits at ~7 o'clock: the arc starts at 135° in y-down coordinates
    /// (lower-left of the dial).
    func test_arc_starts_at_seven_oclock() {
        XCTAssertEqual(StudioRotaryArc.startDegrees, 135)
        let path = StudioRotaryArc(progress: 0.0001).path(in: rect)
        let start = startPoint(of: path)
        // center (50,50) + 50 * (cos 135°, sin 135°)
        XCTAssertEqual(start.x, 50 + 50 * cos(135 * .pi / 180), accuracy: 0.5)
        XCTAssertEqual(start.y, 50 + 50 * sin(135 * .pi / 180), accuracy: 0.5)
    }

    /// Half value points straight up (12 o'clock): the sweep passes over the
    /// TOP of the dial, not under the bottom.
    func test_arc_midpoint_is_twelve_oclock() {
        let path = StudioRotaryArc(progress: 0.5).path(in: rect)
        let end = path.currentPoint ?? .zero
        XCTAssertEqual(end.x, 50, accuracy: 0.5)
        XCTAssertEqual(end.y, 0, accuracy: 0.5)
    }

    /// Full value ends at ~5 o'clock (45° in y-down coordinates) after a
    /// 270° sweep.
    func test_arc_full_value_ends_at_five_oclock() {
        XCTAssertEqual(StudioRotaryArc.sweepDegrees, 270)
        let path = StudioRotaryArc(progress: 1).path(in: rect)
        let end = path.currentPoint ?? .zero
        XCTAssertEqual(end.x, 50 + 50 * cos(45 * .pi / 180), accuracy: 0.5)
        XCTAssertEqual(end.y, 50 + 50 * sin(45 * .pi / 180), accuracy: 0.5)
    }

    func test_arc_clamps_progress_outside_unit_range() {
        let over = StudioRotaryArc(progress: 2).path(in: rect)
        let full = StudioRotaryArc(progress: 1).path(in: rect)
        XCTAssertEqual(over.currentPoint, full.currentPoint)
    }

    // MARK: - Scroll feel constants

    func test_precise_scroll_deltas_pass_through_unscaled() {
        XCTAssertEqual(StudioDrag.scrollTravel(deltaY: 12.5, hasPreciseDeltas: true), 12.5)
        XCTAssertEqual(StudioDrag.scrollTravel(deltaY: -3, hasPreciseDeltas: true), -3)
    }

    func test_line_based_wheel_deltas_scale_to_points() {
        XCTAssertEqual(
            StudioDrag.scrollTravel(deltaY: 1, hasPreciseDeltas: false),
            StudioDrag.wheelLinePoints
        )
        XCTAssertEqual(
            StudioDrag.scrollTravel(deltaY: -2, hasPreciseDeltas: false),
            -2 * StudioDrag.wheelLinePoints
        )
    }

    // MARK: - Hit target

    func test_minimum_hit_target_is_apple_44pt_floor() {
        XCTAssertEqual(StudioMetrics.ControlSize.minimumHitTarget, 44)
    }

    // MARK: - Macro value text

    func test_macro_value_text_wide_ranges_read_as_integers() {
        XCTAssertEqual(MacroValueText.short(127.4, maxValue: 127), "127")
    }

    func test_macro_value_text_unit_ranges_keep_two_decimals() {
        XCTAssertEqual(MacroValueText.short(0.25, maxValue: 1), "0.25")
        XCTAssertEqual(MacroValueText.short(1, maxValue: 1), "1")
    }

    // MARK: - Helpers

    private func startPoint(of path: Path) -> CGPoint {
        var start = CGPoint.zero
        path.cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint, start == .zero {
                start = element.pointee.points[0]
            }
        }
        return start
    }
}
