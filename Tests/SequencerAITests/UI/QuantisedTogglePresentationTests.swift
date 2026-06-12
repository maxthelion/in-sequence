import SwiftUI
import XCTest
@testable import SequencerAI

/// Pins the armed-toggle presentation grammar (wireframes §2): armed =
/// dashed amber outline + the pending glyph; applies-at-boundary = solid.
final class QuantisedTogglePresentationTests: XCTestCase {
    func test_armedStateUsesTheDashedPendingStroke() {
        let armed = QuantisedTogglePresentation.strokeStyle(isPending: true, lineWidth: 2)
        XCTAssertEqual(armed.dash, QuantisedTogglePresentation.pendingDashPattern,
                       "armed toggles read as the dashed pending outline")
        XCTAssertEqual(armed.lineWidth, 2)

        let applied = QuantisedTogglePresentation.strokeStyle(isPending: false, lineWidth: 2)
        XCTAssertTrue(applied.dash.isEmpty, "applies-at-boundary = the stroke becomes solid")
    }

    func test_pendingGlyphIsTheTimerMark() {
        XCTAssertEqual(QuantisedTogglePresentation.pendingGlyphSystemName, "timer")
    }

    func test_fillCueLabels() {
        let pending = QuantisedFillCuePresentation(isPending: true, isCueBarActive: false)
        XCTAssertEqual(pending.stateLabel, "CUED")
        XCTAssertEqual(pending.detailLabel, "NEXT BAR")
        XCTAssertTrue(pending.usesDashedStroke)

        let active = QuantisedFillCuePresentation(isPending: false, isCueBarActive: true)
        XCTAssertNil(active.stateLabel, "the cued bar defers to the cell's ACTIVE label")
        XCTAssertEqual(active.detailLabel, "THIS BAR")
        XCTAssertFalse(active.usesDashedStroke, "the landed cue is solid, not dashed")

        let idle = QuantisedFillCuePresentation(isPending: false, isCueBarActive: false)
        XCTAssertNil(idle.stateLabel)
        XCTAssertNil(idle.detailLabel)
        XCTAssertFalse(idle.usesDashedStroke)
    }
}
