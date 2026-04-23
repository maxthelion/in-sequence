import XCTest
@testable import SequencerAI

/// Verifies that clip-only edits and other snapshot-only paths do NOT call
/// `apply(documentModel:)`. Prior version asserted `destinationCallCount` unchanged,
/// which only proved `setDestination` wasn't called — not that the broad engine rebuild
/// was skipped.
///
/// These tests spy on `applyDocumentModelCallCount` (Phase 2e hook) which is the direct
/// observable of a broad engine rebuild.
final class EngineHotPathIsolationTests: XCTestCase {

    // MARK: - Case 1: clip-only edit via publishSnapshot

    /// A clip edit published via `apply(playbackSnapshot:)` must not call
    /// `apply(documentModel:)` — the snapshot path is hot-path isolated.
    func test_snapshotOnly_clipEdit_doesNotCall_applyDocumentModel() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)

        // Establish a baseline document model so pipelineShape is known.
        controller.apply(documentModel: project)
        let callCountAfterBoot = controller.applyDocumentModelCallCount

        // Edit the clip and publish only via the snapshot path.
        project.updateClipEntry(id: clipID) { entry in
            entry.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
            )
        }

        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))

        XCTAssertEqual(
            controller.applyDocumentModelCallCount,
            callCountAfterBoot,
            "clip-only snapshot update must not call apply(documentModel:)"
        )

        // Confirm playback reflects the edit (the snapshot was actually installed).
        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(sink.playedEvents.flatMap { $0 }.map(\.pitch), [72])
    }

    // MARK: - Case 2: pattern-source-slot edit via publishSnapshot

    /// Changing a pattern slot source (e.g. which clip a slot points to) published
    /// via the snapshot path must not trigger a full document-model apply.
    func test_snapshotOnly_patternSlotEdit_doesNotCall_applyDocumentModel() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)

        controller.apply(documentModel: project)
        let callCountAfterBoot = controller.applyDocumentModelCallCount

        // Add a second clip and change the slot to point to it.
        let altClipID = UUID()
        let altClip = ClipPoolEntry(
            id: altClipID,
            name: "Alt",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 64, velocity: 100, lengthSteps: 1)]), fill: nil)]
            )
        )
        project.clipPool.append(altClip)
        project.setPatternClipID(altClipID, for: trackID, slotIndex: 0)

        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))

        XCTAssertEqual(
            controller.applyDocumentModelCallCount,
            callCountAfterBoot,
            "pattern-slot edit via snapshot path must not call apply(documentModel:)"
        )
    }

    // MARK: - Case 3: phrase-layer edit via publishSnapshot

    /// A phrase-layer mutation published via the snapshot path must not call
    /// `apply(documentModel:)`.
    func test_snapshotOnly_phraseLayerEdit_doesNotCall_applyDocumentModel() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)

        controller.apply(documentModel: project)
        let callCountAfterBoot = controller.applyDocumentModelCallCount

        // Toggle the mute layer on via setPhraseCell.
        let phraseID = project.selectedPhraseID
        let muteLayerID = project.layers.first(where: { $0.target == .mute })?.id
        if let muteLayerID {
            project.setPhraseCell(
                .single(.bool(true)),
                layerID: muteLayerID,
                trackIDs: [trackID],
                phraseID: phraseID
            )
        }

        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))

        XCTAssertEqual(
            controller.applyDocumentModelCallCount,
            callCountAfterBoot,
            "phrase-layer edit via snapshot path must not call apply(documentModel:)"
        )
    }
}
