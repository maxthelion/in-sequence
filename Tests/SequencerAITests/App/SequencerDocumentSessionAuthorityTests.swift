import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerDocumentSessionAuthorityTests: XCTestCase {
    func test_live_mutation_updates_store_before_document_flush() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
                )
            }
        }

        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [60])
        XCTAssertEqual(session.project.clipEntry(id: clipID)?.pitchPool, [72])

        session.flushToDocument()

        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [72])

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

@MainActor
private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
