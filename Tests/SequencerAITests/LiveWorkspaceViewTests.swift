import SwiftUI
import XCTest
@testable import SequencerAI

final class LiveWorkspaceViewTests: XCTestCase {
    func test_view_initializes_for_default_document() {
        let view = LiveWorkspaceView(
            document: .constant(SeqAIDocument()),
            selectedLayerID: .constant("pattern")
        )

        XCTAssertNotNil(view)
    }
}
