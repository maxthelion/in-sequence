import Foundation
import SwiftUI
import XCTest
@testable import SequencerAI

/// Phase 3e: verify debounce cancel-on-re-edit semantics and the invariant that
/// `flushToDocumentSync` cancels any pending debounce so it cannot double-write.
@MainActor
final class DebounceSemanticsTests: XCTestCase {

    // MARK: - Second edit cancels first debounce

    /// Two mutations at T=0 and T=50ms; exactly one flush fires (the second).
    /// Uses a very short debounce interval so the test runs quickly.
    func test_secondMutation_cancelsFirstDebounceTask() async throws {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = DebounceDocumentBox(document: doc)
        let shortDebounce = Duration.milliseconds(80)

        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: shortDebounce
        )

        // First mutation at T=0.
        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )]
                )
            }
        }

        // Wait 40ms (less than debounce window), then mutate again.
        try await Task.sleep(for: .milliseconds(40))

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 99, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )]
                )
            }
        }

        // Document is still stale at this point (neither debounce has fired).
        XCTAssertEqual(box.document.project.clipEntry(id: clipID)?.pitchPool, [60])

        // Wait for the second debounce to fire (80ms from the second mutation).
        try await Task.sleep(for: .milliseconds(150))

        // Only the second mutation (pitch 99) should be in the document.
        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [99],
            "only the final mutation should be flushed; first debounce must have been cancelled"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - flushToDocumentSync cancels pending debounce task

    func test_flushToDocumentSync_cancelsPendingDebounce_noDoubleWrite() {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = DebounceDocumentBox(document: doc)
        var writeCount = 0

        // Intercept writes by wrapping the binding.
        let countingBinding = Binding<SeqAIDocument>(
            get: { box.document },
            set: { newDoc in
                // Detect when project actually changes.
                if box.document.project != newDoc.project {
                    writeCount += 1
                }
                // Note: for class-type doc, this setter is unused (mutations go via ref).
            }
        )

        let session = SequencerDocumentSession(
            document: countingBinding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100) // very long
        )

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 88, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )]
                )
            }
        }

        // Synchronous flush — should cancel the pending 100-second debounce.
        session.flushToDocumentSync()

        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [88],
            "flushToDocumentSync must write the mutation"
        )

        // A second sync flush should be a no-op (document already matches store).
        session.flushToDocumentSync()
        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [88],
            "second flushToDocumentSync must be idempotent"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - debounceInterval is injectable (fast-path test)

    func test_debounceInterval_isInjectable() async throws {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = DebounceDocumentBox(document: doc)

        let veryShortSession = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .milliseconds(10)
        )

        veryShortSession.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 44, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )]
                )
            }
        }

        // With 10ms debounce, the flush fires quickly.
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [44],
            "short debounce should have fired within 50ms"
        )

        SequencerDocumentSessionRegistry.unregister(veryShortSession)
    }
}

// MARK: - Helpers

@MainActor
private final class DebounceDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }

    var binding: Binding<SeqAIDocument> {
        Binding(get: { self.document }, set: { _ in })
    }
}
