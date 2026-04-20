import SwiftUI
import XCTest
@testable import SequencerAI

final class GridEditorTests: XCTestCase {
    func test_cycledValues_advances_probability_grid_to_next_allowed_value() {
        let editor = GridEditor(
            values: [0.0, 0.25, 0.5],
            allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0],
            accent: StudioTheme.cyan
        ) { _ in }

        XCTAssertEqual(editor.cycledValues(tapping: 1), [0.0, 0.5, 0.5])
    }

    func test_cycledValues_wraps_weight_like_values_back_to_zero() {
        let editor = GridEditor(
            values: [0.0, 0.5, 1.0],
            allowedValues: [0.0, 0.5, 1.0],
            accent: StudioTheme.violet
        ) { _ in }

        XCTAssertEqual(editor.cycledValues(tapping: 2), [0.0, 0.5, 0.0])
    }

    func test_normalizedFill_clamps_to_zero_and_one() {
        let editor = GridEditor(
            values: [0.0],
            allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0],
            accent: StudioTheme.cyan
        ) { _ in }

        XCTAssertEqual(editor.normalizedFill(for: -0.25), 0)
        XCTAssertEqual(editor.normalizedFill(for: 1.25), 1)
    }
}
