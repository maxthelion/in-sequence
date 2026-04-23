import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

/// Phase 3d: verify that `applicationWillTerminate` and `applicationDidResignActive`
/// both flush pending live-store edits into the document before any other teardown.
@MainActor
final class TerminateFlushTests: XCTestCase {

    // MARK: - applicationWillTerminate flushes before engine shutdown

    func test_applicationWillTerminate_flushesPendingEdits() {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = TerminateDocumentBox(document: doc)

        let spyEngine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: spyEngine,
            debounceInterval: .seconds(100) // prevent automatic flush
        )

        // Mutate without letting the debounce fire.
        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: 88, velocity: 100, lengthSteps: 4)]
                        ),
                        fill: nil
                    )]
                )
            }
        }

        // Document is still stale.
        XCTAssertEqual(box.document.project.clipEntry(id: clipID)?.pitchPool, [60])

        // Terminate.
        let delegate = SequencerAIAppDelegate()
        delegate.windowHost = NoOpWindowHost()
        delegate.drainRunLoop = { _ in }
        delegate.shutdownDrainInterval = 0

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        // After terminate, the document must contain the flushed edit.
        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [88],
            "terminate must flush pending edits before shutdown"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - applicationDidResignActive flushes pending edits

    func test_applicationDidResignActive_flushesPendingEdits() {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = TerminateDocumentBox(document: doc)

        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: 77, velocity: 100, lengthSteps: 4)]
                        ),
                        fill: nil
                    )]
                )
            }
        }

        XCTAssertEqual(box.document.project.clipEntry(id: clipID)?.pitchPool, [60])

        let delegate = SequencerAIAppDelegate()
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))

        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [77],
            "resign-active must flush pending edits"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - flushAll is idempotent

    func test_flushAll_isIdempotent() {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = TerminateDocumentBox(document: doc)

        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil)
        )

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 55, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )]
                )
            }
        }

        SequencerDocumentSessionRegistry.flushAll()
        XCTAssertEqual(box.document.project.clipEntry(id: clipID)?.pitchPool, [55])

        // Second flush should be a no-op (document matches store).
        SequencerDocumentSessionRegistry.flushAll()
        XCTAssertEqual(box.document.project.clipEntry(id: clipID)?.pitchPool, [55])

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - Test helpers

@MainActor
private final class TerminateDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }

    var binding: Binding<SeqAIDocument> {
        Binding(get: { self.document }, set: { _ in })
    }
}

@MainActor
private final class NoOpWindowHost: AUWindowHosting {
    func closeAll() {}
}
