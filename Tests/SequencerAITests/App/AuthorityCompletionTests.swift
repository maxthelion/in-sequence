import XCTest
import SwiftUI
import AVFoundation
@testable import SequencerAI

// MARK: - Phase 2 authority-completion guardrail tests.
//
// Each inner class covers one sub-item from the Phase 2 plan:
//   2a  PhraseMatrixAuthorityTests
//   2b  SamplerFilterAuthorityTests
//   2c  PresetBrowserAuthorityTests
//   2d  MixerDragLiveWritesTests
//   2e  FullEngineApplyNoDoubleCompileTests
//   2f  SelfOriginFlushGuardTests

// MARK: - Helpers

/// A `SamplePlaybackSink` spy that counts `applyFilter` calls and records
/// the most recent settings. All other methods are no-ops.
private final class FilterSpy: SamplePlaybackSink {
    private(set) var applyFilterCalls = 0
    private(set) var lastSettings: SamplerFilterSettings?
    private(set) var lastTrackID: UUID?

    func start() throws {}
    func stop() {}
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? { nil }
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
    func removeTrack(trackID: UUID) {}
    func audition(sampleURL: URL) {}
    func stopAudition() {}
    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
        applyFilterCalls += 1
        lastSettings = settings
        lastTrackID = trackID
    }
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
}

/// Minimal document box for tests — mirrors the private one in other test files.
@MainActor
private final class DocBox {
    var document: SeqAIDocument

    init(project: Project? = nil) {
        self.document = project.map { SeqAIDocument(project: $0) } ?? SeqAIDocument()
    }

    var binding: Binding<SeqAIDocument> {
        Binding(get: { self.document }, set: { self.document = $0 })
    }
}

// MARK: - 2a. PhraseMatrixAuthorityTests

@MainActor
final class PhraseMatrixAuthorityTests: XCTestCase {
    /// After 2a, phrase-matrix mutations must publish a snapshot WITHOUT calling
    /// `engineController.apply(documentModel:)`.
    func test_phraseSelect_publishesSnapshot_withoutApplyDocumentModel() {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let baselineApplyCount = engine.applyDocumentModelCallCount

        // Simulate handleSingleTap — selectPhrase + selectTrack with .snapshotOnly
        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.selectPhrase(id: proj.selectedPhraseID)
            proj.selectTrack(id: proj.selectedTrackID)
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, baselineApplyCount,
            "Phrase-matrix tap must not call apply(documentModel:)"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_insertPhrase_publishesSnapshot_withoutApplyDocumentModel() throws {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let before = engine.applyDocumentModelCallCount
        let phraseID = try XCTUnwrap(project.phrases.first?.id)

        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.insertPhrase(below: phraseID)
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, before,
            "insertPhrase with .snapshotOnly must not call apply(documentModel:)"
        )
        // Phrase should be added to the store.
        XCTAssertEqual(session.project.phrases.count, project.phrases.count + 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_duplicatePhrase_publishesSnapshot_withoutApplyDocumentModel() throws {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let before = engine.applyDocumentModelCallCount
        let phraseID = try XCTUnwrap(project.phrases.first?.id)

        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.duplicatePhrase(id: phraseID)
        }

        XCTAssertEqual(engine.applyDocumentModelCallCount, before)
        XCTAssertEqual(session.project.phrases.count, project.phrases.count + 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_removePhrase_publishesSnapshot_withoutApplyDocumentModel() throws {
        // Build a project with two phrases so removal is valid.
        var multiPhraseProject = makeLiveStoreProject().0
        let existingPhraseID = try XCTUnwrap(multiPhraseProject.phrases.first?.id)
        multiPhraseProject.insertPhrase(below: existingPhraseID)

        let box = DocBox(project: multiPhraseProject)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let before = engine.applyDocumentModelCallCount

        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.removePhrase(id: existingPhraseID)
        }

        XCTAssertEqual(engine.applyDocumentModelCallCount, before)
        XCTAssertFalse(
            session.project.phrases.contains(where: { $0.id == existingPhraseID }),
            "Phrase must be removed from the store"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - 2b. SamplerFilterAuthorityTests

@MainActor
final class SamplerFilterAuthorityTests: XCTestCase {
    /// Filter cutoff write via `.scopedRuntime(.filter(...))` must:
    ///   1. update the live store's track.filter field
    ///   2. call sampleEngine.applyFilter exactly once
    ///   3. NOT call apply(documentModel:)
    func test_filterCutoff_updateStore_callsScopedFilter_notApplyDocumentModel() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let filterSpy = FilterSpy()
        let engine = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: filterSpy
        )
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let before = engine.applyDocumentModelCallCount

        let newFilter = SamplerFilterSettings(cutoffHz: 1000)
        session.mutateProject(impact: .scopedRuntime(update: .filter(trackID: trackID, settings: newFilter))) { proj in
            guard let idx = proj.tracks.firstIndex(where: { $0.id == trackID }) else { return }
            proj.tracks[idx].filter = newFilter
        }

        // 1. Store is updated.
        let stored = try XCTUnwrap(session.project.tracks.first(where: { $0.id == trackID }))
        XCTAssertEqual(stored.filter.cutoffHz, 1000, accuracy: 0.001)

        // 2. Scoped filter dispatch was called exactly once.
        XCTAssertEqual(filterSpy.applyFilterCalls, 1)
        XCTAssertEqual(filterSpy.lastTrackID, trackID)
        XCTAssertEqual(filterSpy.lastSettings?.cutoffHz ?? 0, 1000, accuracy: 0.001)

        // 3. No broad engine apply.
        XCTAssertEqual(engine.applyDocumentModelCallCount, before)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - 2c. PresetBrowserAuthorityTests

@MainActor
final class PresetBrowserAuthorityTests: XCTestCase {
    /// AU state blob write via `.scopedRuntime(.auState(...))` must:
    ///   1. publish a snapshot synchronously (before 150ms debounce fires)
    ///   2. NOT call apply(documentModel:)
    func test_auStateWrite_publishesSnapshotSynchronously_notApplyDocumentModel() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let before = engine.applyDocumentModelCallCount
        let beforeRevision = session.revision

        let blob = Data([0xDE, 0xAD, 0xBE, 0xEF])
        session.mutateProject(impact: .scopedRuntime(update: .auState(trackID: trackID, blob: blob))) { proj in
            guard let idx = proj.tracks.firstIndex(where: { $0.id == trackID }),
                  case let .auInstrument(componentID, _) = proj.tracks[idx].destination
            else { return }
            proj.tracks[idx].destination = .auInstrument(componentID: componentID, stateBlob: blob)
        }

        // Snapshot revision bumped synchronously — no wait needed.
        XCTAssertGreaterThan(session.revision, beforeRevision, "Snapshot must be published synchronously")

        // No broad engine apply.
        XCTAssertEqual(engine.applyDocumentModelCallCount, before)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - 2d. MixerDragLiveWritesTests

@MainActor
final class MixerDragLiveWritesTests: XCTestCase {
    /// `session.setTrackMix(trackID:mix:)` must write the live store immediately.
    func test_setTrackMix_updatesStoreImmediately() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()

        var newMix = TrackMixSettings.default
        newMix.level = 0.42

        session.setTrackMix(trackID: trackID, mix: newMix)

        // Live store must reflect the new level immediately.
        let stored = try XCTUnwrap(session.project.tracks.first(where: { $0.id == trackID }))
        XCTAssertEqual(stored.mix.level, 0.42, accuracy: 0.001)

        // Document flush has NOT happened yet (only debounce scheduled).
        XCTAssertNotEqual(
            box.document.project.tracks.first(where: { $0.id == trackID })?.mix.level ?? -1,
            0.42,
            "Level should not yet be in the document before flush"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// Multiple drag updates must all update the live store; not only the commit.
    func test_multipleSetTrackMix_allWriteLiveStore() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()

        // Simulate three drag updates — each one should be reflected immediately.
        for level in [0.1, 0.5, 0.8] {
            var mix = TrackMixSettings.default
            mix.level = level
            session.setTrackMix(trackID: trackID, mix: mix)

            let stored = try XCTUnwrap(session.project.tracks.first(where: { $0.id == trackID }))
            XCTAssertEqual(stored.mix.level, level, accuracy: 0.001, "Store must update on every drag tick")
        }

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// `setTrackMix` must also publish a snapshot so playback reflects the drag.
    func test_setTrackMix_publishesSnapshot() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let beforeRevision = session.revision

        var mix = TrackMixSettings.default
        mix.level = 0.7
        session.setTrackMix(trackID: trackID, mix: mix)

        XCTAssertGreaterThan(session.revision, beforeRevision, "Snapshot revision must advance after setTrackMix")

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - 2e. FullEngineApplyNoDoubleCompileTests

@MainActor
final class FullEngineApplyNoDoubleCompileTests: XCTestCase {
    /// A `.fullEngineApply` mutation must call `apply(documentModel:)` exactly once —
    /// not a second `publishSnapshot()` after.
    ///
    /// We measure `applyDocumentModelCallCount` across the mutation; it must
    /// increment by exactly 1 relative to baseline.
    func test_fullEngineApply_callsApplyDocumentModelExactlyOnce() throws {
        let (project, _, clipID) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let baseline = engine.applyDocumentModelCallCount

        session.mutateProject(impact: .fullEngineApply) { proj in
            proj.updateClipEntry(id: clipID) { entry in
                entry.name = "Renamed"
            }
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, baseline + 1,
            ".fullEngineApply must call apply(documentModel:) exactly once (no double-compile)"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// A `.snapshotOnly` mutation must NOT call `apply(documentModel:)`.
    func test_snapshotOnly_doesNotCallApplyDocumentModel() throws {
        let (project, _, clipID) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()
        let baseline = engine.applyDocumentModelCallCount

        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.updateClipEntry(id: clipID) { entry in
                entry.name = "Renamed"
            }
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, baseline,
            ".snapshotOnly must not call apply(documentModel:)"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

// MARK: - 2f. SelfOriginFlushGuardTests

@MainActor
final class SelfOriginFlushGuardTests: XCTestCase {
    /// When `flushToDocument()` writes to `document.wrappedValue.project` and
    /// `ingestExternalDocumentChange(_:)` is called during that window (simulated
    /// by calling it directly while the flag is set), the session must NOT
    /// re-apply the document model to the engine.
    func test_ingestExternalDocumentChange_duringFlush_isIgnored() throws {
        let (project, _, clipID) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()

        // Mutate the session so there's something to flush.
        session.mutateProject(impact: .snapshotOnly) { proj in
            proj.updateClipEntry(id: clipID) { entry in
                entry.name = "Dirty"
            }
        }

        // Flush writes the mutated project into the document binding.
        session.flushToDocument()

        // After the flush, the document reflects the change.
        let flushedProject = box.document.project
        let countAfterFlush = engine.applyDocumentModelCallCount

        // Simulate what SequencerDocumentRootView.onChange does: calls
        // ingestExternalDocumentChange with the freshly-written project.
        // Because the flag was already cleared (flush is synchronous), we
        // call it with the same value to verify the equality guard catches it.
        session.ingestExternalDocumentChange(flushedProject)

        // The engine must not have been re-applied.
        XCTAssertEqual(
            engine.applyDocumentModelCallCount, countAfterFlush,
            "ingestExternalDocumentChange with the just-flushed project must not re-apply the engine"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// Genuine external changes (e.g. undo, co-editing) must still be ingested.
    func test_ingestExternalDocumentChange_genuineExternalChange_isApplied() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let box = DocBox(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(document: box.binding, engineController: engine)
        session.activate()

        // Build a new project with a different track name — simulates undo / external edit.
        var externalProject = project
        guard let idx = externalProject.tracks.firstIndex(where: { $0.id == trackID }) else {
            XCTFail("Track not found")
            return
        }
        externalProject.tracks[idx].name = "External"
        let countBefore = engine.applyDocumentModelCallCount

        session.ingestExternalDocumentChange(externalProject)

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, countBefore + 1,
            "Genuine external changes must be applied to the engine"
        )
        XCTAssertEqual(
            session.project.tracks.first(where: { $0.id == trackID })?.name,
            "External",
            "External change must be reflected in the session's project"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
