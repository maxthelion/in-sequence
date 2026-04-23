import XCTest
import SwiftUI
@testable import SequencerAI

// MARK: - MultiDocumentEngineIsolationTests
//
// Phase 1c guardrail: each SequencerDocumentSession owns a distinct EngineController.
//
// Tests use SequencerDocumentSession's test-only init (accepting an injected
// EngineController) so the suite does not require a CoreAudio device.

@MainActor
final class MultiDocumentEngineIsolationTests: XCTestCase {

    // MARK: - 1. Two sessions have distinct EngineControllers

    func test_twoSessions_haveDistinctEngineControllers() {
        let boxA = DocumentBox()
        let boxB = DocumentBox()

        let sessionA = SequencerDocumentSession(document: boxA.binding)
        let sessionB = SequencerDocumentSession(document: boxB.binding)

        XCTAssertNotEqual(
            ObjectIdentifier(sessionA.engineController),
            ObjectIdentifier(sessionB.engineController),
            "Each session must own a separate EngineController instance"
        )

        SequencerDocumentSessionRegistry.unregister(sessionA)
        SequencerDocumentSessionRegistry.unregister(sessionB)
    }

    // MARK: - 2. Mutation in session A does not affect session B's snapshot

    func test_mutationInSessionA_doesNotAffectSessionBSnapshot() throws {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let boxA = DocumentBox(project: project)
        let boxB = DocumentBox(project: project)

        let engineA = EngineController(client: nil, endpoint: nil)
        let engineB = EngineController(client: nil, endpoint: nil)

        let sessionA = SequencerDocumentSession(document: boxA.binding, engineController: engineA)
        let sessionB = SequencerDocumentSession(document: boxB.binding, engineController: engineB)

        // Activate both sessions so their engines hold snapshots derived from the project.
        sessionA.activate()
        sessionB.activate()

        // Capture session B's snapshot before any mutation.
        let beforeB = engineB.currentPlaybackSnapshotForTesting
        let clipInBBefore = try XCTUnwrap(
            beforeB.clipPool.first(where: { $0.id == clipID }),
            "Session B snapshot must contain the clip after activate()"
        )
        XCTAssertEqual(clipInBBefore.pitchPool, [60], "Session B baseline pitch must be 60")

        // Mutate a clip exclusively in session A.
        sessionA.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]
                        ),
                        fill: nil
                    )]
                )
            }
        }

        // Session A snapshot must reflect the new pitch.
        let afterA = engineA.currentPlaybackSnapshotForTesting
        let clipInA = afterA.clipPool.first(where: { $0.id == clipID })
        XCTAssertEqual(clipInA?.pitchPool, [72], "Session A snapshot must reflect the mutation")

        // Session B snapshot must be untouched.
        let afterB = engineB.currentPlaybackSnapshotForTesting
        let clipInBAfter = try XCTUnwrap(
            afterB.clipPool.first(where: { $0.id == clipID }),
            "Session B clip must still be present after session A mutates"
        )
        XCTAssertEqual(clipInBAfter.pitchPool, [60], "Session B snapshot must not reflect session A's mutation")

        SequencerDocumentSessionRegistry.unregister(sessionA)
        SequencerDocumentSessionRegistry.unregister(sessionB)
    }

    // MARK: - 3. Transport state in session A is independent of session B

    func test_transportStartInSessionA_leavesSessionBStopped() {
        let boxA = DocumentBox()
        let boxB = DocumentBox()

        let engineA = EngineController(client: nil, endpoint: nil)
        let engineB = EngineController(client: nil, endpoint: nil)

        let sessionA = SequencerDocumentSession(document: boxA.binding, engineController: engineA)
        let sessionB = SequencerDocumentSession(document: boxB.binding, engineController: engineB)

        // Both engines start stopped.
        XCTAssertFalse(engineA.isRunning)
        XCTAssertFalse(engineB.isRunning)

        // Attempt to start engine A. (Without a prepared executor the call is a
        // no-op, but the key assertion is that B remains independent of A.)
        engineA.start()

        // B must remain stopped regardless of what we do to A.
        XCTAssertFalse(engineB.isRunning, "Engine B must remain stopped when A is started")

        // The two engines are distinct objects.
        XCTAssertFalse(
            engineA === engineB,
            "Sessions must not share an EngineController instance"
        )

        SequencerDocumentSessionRegistry.unregister(sessionA)
        SequencerDocumentSessionRegistry.unregister(sessionB)
    }

    // MARK: - 4. AppDelegate shutsDown all registered engines via registry

    func test_appDelegate_shutsDownBothEngines() {
        let boxA = DocumentBox()
        let boxB = DocumentBox()

        let engineA = EngineController(client: nil, endpoint: nil)
        let engineB = EngineController(client: nil, endpoint: nil)

        var shutdownCountA = 0
        var shutdownCountB = 0
        engineA.shutdownObserver = { shutdownCountA += 1 }
        engineB.shutdownObserver = { shutdownCountB += 1 }

        let sessionA = SequencerDocumentSession(document: boxA.binding, engineController: engineA)
        let sessionB = SequencerDocumentSession(document: boxB.binding, engineController: engineB)

        // Simulate the terminate path.
        SequencerDocumentSessionRegistry.shutdownAll()

        XCTAssertEqual(shutdownCountA, 1, "Engine A must be shut down exactly once by shutdownAll()")
        XCTAssertEqual(shutdownCountB, 1, "Engine B must be shut down exactly once by shutdownAll()")

        SequencerDocumentSessionRegistry.unregister(sessionA)
        SequencerDocumentSessionRegistry.unregister(sessionB)
    }
}

// MARK: - Test Helpers

@MainActor
private final class DocumentBox {
    var document: SeqAIDocument

    init(project: Project? = nil) {
        self.document = project.map { SeqAIDocument(project: $0) } ?? SeqAIDocument()
    }

    var binding: Binding<SeqAIDocument> {
        Binding(
            get: { self.document },
            set: { self.document = $0 }
        )
    }
}
