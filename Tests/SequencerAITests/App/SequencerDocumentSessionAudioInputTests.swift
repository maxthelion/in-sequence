import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerDocumentSessionAudioInputTests: XCTestCase {
    func test_appendTrack_allowsOnlyOneAudioInputTrackInSessionAndRuntime() {
        let documentBox = AudioInputDocumentBox(document: SeqAIDocument(project: .empty))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        XCTAssertTrue(session.canAppendAudioInputTrack)

        session.appendTrack(trackType: .audioInput)
        let firstInputTrackID = session.store.selectedTrackID
        XCTAssertFalse(session.canAppendAudioInputTrack)
        XCTAssertEqual(session.store.tracks.filter { $0.trackType == .audioInput }.count, 1)
        XCTAssertEqual(engine.audioInputRuntimeTrackIDs, [firstInputTrackID])

        session.appendTrack(trackType: .audioInput)

        XCTAssertEqual(session.store.tracks.filter { $0.trackType == .audioInput }.count, 1)
        XCTAssertEqual(session.store.selectedTrackID, firstInputTrackID)
        XCTAssertEqual(engine.audioInputRuntimeTrackIDs, [firstInputTrackID])
        XCTAssertFalse(session.canAppendAudioInputTrack)
    }
}

private final class AudioInputDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
