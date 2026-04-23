import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import SequencerAI

/// Phase 3b: verify that the save pre-hook flushes pending live-store edits so
/// `fileWrapper(snapshot:configuration:)` always serializes the freshest state.
@MainActor
final class SaveFlushTests: XCTestCase {

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }

        var binding: Binding<SeqAIDocument> {
            Binding(get: { self.document }, set: { _ in })
        }
    }

    // MARK: - Save pre-hook flushes pending edit

    /// After a mutation but before the 150ms debounce fires, calling
    /// `snapshot(contentType:)` (the save pre-hook) must write the fresh state
    /// into `document.project`. The returned `Project` also contains the edit.
    func test_fileWrapper_afterPendingEdit_serializesFreshProject() throws {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = DocumentBox(document: doc)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil)
        )

        // Mutate a clip pitch (debounce has not fired yet).
        session.mutateProject {
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

        // Document is still stale (debounce hasn't fired).
        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [60],
            "document.project should be stale before the save pre-hook"
        )

        // Trigger the save pre-hook (simulates Cmd-S).
        let snapshotProject = try doc.snapshot(contentType: .seqAIDocument)

        // After the pre-hook, document.project must be updated.
        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [72],
            "document.project must be flushed after snapshot(contentType:)"
        )

        // The returned snapshot must also contain the updated state.
        XCTAssertEqual(
            snapshotProject.clipEntry(id: clipID)?.pitchPool,
            [72],
            "snapshot returned by pre-hook must reflect the mutation"
        )

        // Encode the returned snapshot — it must round-trip correctly.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshotProject)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.clipEntry(id: clipID)?.pitchPool, [72])

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - snapshot(contentType:) cancels pending debounce

    func test_snapshotPreHook_cancelsPendingDebounceTask() throws {
        let (baseProject, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let doc = SeqAIDocument(project: baseProject)
        let box = DocumentBox(document: doc)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100) // very long so it won't fire during test
        )

        // Mutate — schedules a 100-second debounce.
        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: 99, velocity: 100, lengthSteps: 4)]
                        ),
                        fill: nil
                    )]
                )
            }
        }

        // Pre-hook flushes synchronously and cancels the debounce.
        _ = try doc.snapshot(contentType: .seqAIDocument)

        XCTAssertEqual(
            box.document.project.clipEntry(id: clipID)?.pitchPool,
            [99],
            "flush must have written the mutation"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - No session registered — snapshot returns current project unchanged

    func test_snapshot_withNoSession_returnsCurrentProject() throws {
        let (project, _, _) = makeLiveStoreProject()
        let doc = SeqAIDocument(project: project)

        // No session registered for this document.
        let returned = try doc.snapshot(contentType: .seqAIDocument)
        XCTAssertEqual(returned, project)
    }
}
