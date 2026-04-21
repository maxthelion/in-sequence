import SwiftUI
import XCTest
@testable import SequencerAI

final class StudioTypographyTests: XCTestCase {
    func test_all_recipes_declare_rounded_design_except_chromeLabel() {
        for style in StudioTypography.allCases where style != .chromeLabel {
            XCTAssertEqual(style.design, .rounded, "\(style) must use .rounded design to match house style")
        }
    }

    func test_recipe_sizes_match_measured_census() {
        XCTAssertEqual(StudioTypography.eyebrow.size, 11)
        XCTAssertEqual(StudioTypography.label.size, 12)
        XCTAssertEqual(StudioTypography.body.size, 13)
        XCTAssertEqual(StudioTypography.subtitle.size, 14)
        XCTAssertEqual(StudioTypography.title.size, 18)
        XCTAssertEqual(StudioTypography.display.size, 28)
    }

    func test_weights_match_measured_census() {
        XCTAssertEqual(StudioTypography.eyebrow.weight, .semibold)
        XCTAssertEqual(StudioTypography.labelBold.weight, .bold)
        XCTAssertEqual(StudioTypography.body.weight, .medium)
        XCTAssertEqual(StudioTypography.bodyEmphasis.weight, .semibold)
    }
}
