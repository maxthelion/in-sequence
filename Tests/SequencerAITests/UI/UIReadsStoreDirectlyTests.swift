import XCTest
import SwiftUI
@testable import SequencerAI

// MARK: - Phase 2 guardrail: UI read paths do not call exportToProject()
//
// Each test exercises the read helpers of a migrated view (or its direct
// equivalents) and asserts that `exportToProjectCallCount` does not advance.
//
// For views whose body cannot be rendered in unit tests, the invariant is
// verified by exercising the same store fields the view reads:
//   - "Read path" test: access the store fields the view's body reads,
//     assert no exportToProject() was called.
//   - "Edit then read" test: mutate via a session typed method, then re-read
//     the same fields, assert exportToProject() was NOT called by the read.
//
// The static evidence that files no longer contain `session.project` is
// captured in the grep-zero check documented in the Phase 2 report.

@MainActor
final class UIReadsStoreDirectlyTests: XCTestCase {

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project? = nil) -> (SequencerDocumentSession, DocumentBox) {
        let (defaultProject, _, _) = makeLiveStoreProject()
        let p = project ?? defaultProject
        let box = DocumentBox(document: SeqAIDocument(project: p))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(get: { box.document }, set: { box.document = $0 }),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, box)
    }

    // MARK: - MixerView read path

    /// MixerView reads `session.store.tracks` and `session.store.selectedTrackID`.
    /// Accessing those fields must not call `exportToProject`.
    func test_mixerView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            _ = session.store.tracks
            _ = session.store.selectedTrackID
            for track in session.store.tracks {
                _ = session.store.group(for: track.id)
            }
        }
    }

    /// Mutating a track's mix level via the session typed API, then re-reading
    /// the updated value from the store, must not trigger exportToProject.
    func test_mixerView_editThenRead_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let trackID = session.store.selectedTrackID
        session.mutateTrack(id: trackID) { $0.mix.level = 0.7 }
        let exportsBefore = session.store.exportToProjectCallCount
        // Re-read the updated track without going through exportToProject.
        let _ = session.store.tracks.first(where: { $0.id == trackID })?.mix.level
        XCTAssertEqual(session.store.exportToProjectCallCount, exportsBefore,
            "Re-reading a track after mutation should not call exportToProject")
    }

    // MARK: - InspectorView read path

    /// InspectorView reads `session.store.selectedTrack` and `session.store.group(for:)`.
    func test_inspectorView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let track = session.store.selectedTrack
            _ = track.name
            _ = track.mix.clampedLevel
            _ = track.mix.clampedPan
            _ = track.mix.isMuted
            _ = session.store.group(for: track.id)
        }
    }

    // MARK: - SidebarView read path

    /// SidebarView reads `session.store.tracks` and `session.store.selectedTrackID`.
    func test_sidebarView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            _ = session.store.tracks
            _ = session.store.selectedTrackID
        }
    }

    // MARK: - TracksMatrixView read path

    /// TracksMatrixView reads tracks, trackGroups, patternIndex, selectedTrackID.
    func test_tracksMatrixView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let tracks = session.store.tracks
            let selectedTrackID = session.store.selectedTrackID
            _ = session.store.trackGroups
            for track in tracks {
                _ = session.store.selectedPatternIndex(for: track.id)
                _ = track.id == selectedTrackID
            }
        }
    }

    // MARK: - WorkspaceDetailView read path

    /// WorkspaceDetailView itself has no store reads — it delegates to sub-views.
    /// The only session interaction is `session.setSelectedTrackID`, which is a write.
    /// Verify that setSelectedTrackID doesn't call exportToProject.
    func test_workspaceDetailView_selectTrack_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let trackID = session.store.selectedTrackID
        assertNoExportDuring(session.store) {
            session.setSelectedTrackID(trackID)
        }
    }

    // MARK: - TrackWorkspaceView read path

    /// TrackWorkspaceView reads `session.store.selectedTrack` and
    /// `session.store.routesSourced(from:)`.
    func test_trackWorkspaceView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let track = session.store.selectedTrack
            _ = session.store.routesSourced(from: track.id).count
        }
    }

    // MARK: - MacroKnobRow read path

    /// MacroKnobRow reads `session.store.tracks` (to find the track) and
    /// `session.store.layers` (to resolve macro layer defaults).
    func test_macroKnobRow_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let trackID = session.store.selectedTrackID
        assertNoExportDuring(session.store) {
            let track = session.store.tracks.first(where: { $0.id == trackID })
            let macros = track?.macros ?? []
            let layers = session.store.layers
            let vm = MacroKnobRowViewModel()
            for binding in macros {
                _ = vm.currentValue(binding: binding, trackID: trackID, layers: layers)
            }
        }
    }

    // MARK: - PhraseCellEditorSheet read path

    /// PhraseCellEditorSheet reads phrases, tracks, and layers by target IDs.
    func test_phraseCellEditorSheet_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let phraseID = session.store.selectedPhraseID
        let trackID = session.store.selectedTrackID
        assertNoExportDuring(session.store) {
            _ = session.store.phrases.first(where: { $0.id == phraseID })
            _ = session.store.tracks.first(where: { $0.id == trackID })
            _ = session.store.layer(id: "pattern")
        }
    }

    // MARK: - RoutesListView read path

    /// RoutesListView reads `session.store.selectedTrack` and `session.store.routesSourced(from:)`.
    func test_routesListView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let track = session.store.selectedTrack
            _ = session.store.routesSourced(from: track.id)
            _ = session.store.makeDefaultRoute(from: track.id)
        }
    }

    /// `session.upsertRoute` and `session.removeRoute` should not trigger
    /// an `exportToProject` call on the read side (they may call it on the
    /// write side for the snapshot, but not on the next read of the store).
    func test_routesListView_upsertRemove_readAfterwards_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let track = session.store.selectedTrack
        let route = session.makeDefaultRoute(from: track.id)
        session.upsertRoute(route)

        let exportsBefore = session.store.exportToProjectCallCount
        _ = session.store.routes
        XCTAssertEqual(session.store.exportToProjectCallCount, exportsBefore,
            "Reading routes after upsert must not call exportToProject")

        session.removeRoute(id: route.id)
        let exportsAfterRemove = session.store.exportToProjectCallCount
        _ = session.store.routes
        XCTAssertEqual(session.store.exportToProjectCallCount, exportsAfterRemove,
            "Reading routes after remove must not call exportToProject")
    }

    // MARK: - LiveWorkspaceView read path

    /// LiveWorkspaceView reads layers, selectedPhraseID, tracks, trackGroups, selectedTrack.
    func test_liveWorkspaceView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            _ = session.store.layers
            _ = session.store.selectedPhraseID
            _ = session.store.selectedPhrase
            _ = session.store.tracks
            _ = session.store.trackGroups
            _ = session.store.selectedTrackID
            _ = session.store.layer(id: "pattern")
            _ = session.store.patternLayer
            for track in session.store.tracks {
                _ = session.store.tracksInGroup(track.groupID ?? UUID())
            }
        }
    }

    // MARK: - PhraseWorkspaceView read path

    /// PhraseWorkspaceView reads phrases, tracks, layers, selectedPhrase, selectedTrack,
    /// selectedPhraseID, selectedTrackID.
    func test_phraseWorkspaceView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            _ = session.store.phrases
            _ = session.store.tracks
            _ = session.store.layers
            _ = session.store.selectedPhrase
            _ = session.store.selectedTrack
            _ = session.store.selectedPhraseID
            _ = session.store.selectedTrackID
            _ = session.store.layer(id: "pattern")
            _ = session.store.patternLayer
        }
    }

    // MARK: - TrackSourceEditorView read path

    /// TrackSourceEditorView reads selectedTrack, patternBank, patternIndex,
    /// selectedPattern, clipEntry, generatorEntry, etc.
    func test_trackSourceEditorView_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let track = session.store.selectedTrack
            let bank = session.store.patternBank(for: track.id)
            let index = session.store.selectedPatternIndex(for: track.id)
            let pattern = session.store.selectedPattern(for: track.id)
            _ = bank
            _ = index
            _ = pattern
            _ = session.store.clipEntry(id: pattern.sourceRef.clipID)
            _ = session.store.generatorEntry(id: pattern.sourceRef.generatorID)
            _ = session.store.generatorEntry(id: pattern.sourceRef.modifierGeneratorID)
            _ = session.store.compatibleGenerators(for: track)
            _ = session.store.generatedSourceInputClips()
            _ = session.store.harmonicSidechainClips()
            _ = session.store.layers
        }
    }

    // MARK: - TrackDestinationEditor read path

    /// TrackDestinationEditor reads selectedTrack, destinationWriteTarget,
    /// resolvedDestination, voiceSnapshotDestination, selectedPhrase, group.
    func test_trackDestinationEditor_readPath_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        assertNoExportDuring(session.store) {
            let track = session.store.selectedTrack
            _ = session.store.destinationWriteTarget(for: track.id)
            _ = session.store.resolvedDestination(for: track.id)
            _ = session.store.voiceSnapshotDestination(for: track.id)
            _ = session.store.selectedPhrase.name
            _ = session.store.group(for: track.id)
            _ = session.store.trackGroups
            _ = session.store.tracks
        }
    }

    /// `DestinationSummary.make(for:in:store:trackID:)` must not call exportToProject.
    func test_destinationSummary_storeOverload_doesNotCallExportToProject() {
        let (session, _) = makeSession()
        let track = session.store.selectedTrack
        let destination = Destination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        assertNoExportDuring(session.store) {
            _ = DestinationSummary.make(for: destination, in: session.store, trackID: track.id)
        }
    }

    // MARK: - Session typed methods: appendTrack / removeSelectedTrack / addDrumGroup

    /// `session.appendTrack()` should not cause a re-read of the store to
    /// call exportToProject beyond the internal dispatch path.
    func test_sessionAppendTrack_storeIsReadableAfterwards_withoutExtraExport() {
        let (session, _) = makeSession()
        session.appendTrack(trackType: .monoMelodic)
        let exportsBefore = session.store.exportToProjectCallCount
        let newCount = session.store.tracks.count
        XCTAssertGreaterThan(newCount, 1, "appendTrack should have added a track")
        XCTAssertEqual(session.store.exportToProjectCallCount, exportsBefore,
            "Reading tracks after appendTrack must not call exportToProject")
    }

    func test_sessionRemoveSelectedTrack_storeIsReadableAfterwards_withoutExtraExport() {
        let (session, _) = makeSession()
        // Append a track first so we can remove one.
        session.appendTrack(trackType: .polyMelodic)
        XCTAssertEqual(session.store.tracks.count, 2)
        session.setSelectedTrackID(session.store.tracks.last!.id)
        session.removeSelectedTrack()
        let exportsBefore = session.store.exportToProjectCallCount
        XCTAssertEqual(session.store.tracks.count, 1)
        XCTAssertEqual(session.store.exportToProjectCallCount, exportsBefore,
            "Reading tracks after removeSelectedTrack must not call exportToProject")
    }
}
