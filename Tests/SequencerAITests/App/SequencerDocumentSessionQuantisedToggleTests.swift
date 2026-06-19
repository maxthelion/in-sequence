import Foundation
import SwiftUI
import XCTest
@testable import SequencerAI

/// Session-side contract for quantised perform toggles (slice 2):
/// the Q setting defaults to BAR and gates arming; the committed handler
/// stages the same overlay record an immediate tap would have; and leaving
/// the quantise context cancels pending arms.
@MainActor
final class SequencerDocumentSessionQuantisedToggleTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    private func makeSession() -> (SequencerDocumentSession, EngineController, DocumentBox) {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, engine, box)
    }

    private func startEngineForManualTicks(_ engine: EngineController) {
        engine.start()
        engine.clock.stop()
    }

    private var muteLayerID: String {
        TrackPerformLayerMode.mute.phraseLayerID!
    }

    // MARK: - The Q setting

    func test_performQuantiseDefaultsToBar() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.performQuantise, .bar,
                       "quantise defaults ON (BAR) in perform mode — intent-dictation §2")
    }

    func test_armingIsActiveOnlyInPerformModeWithQBarAndTransportRunning() {
        let (session, engine, _) = makeSession()

        XCTAssertFalse(session.isQuantisedPerformToggleArmingActive,
                       "setup mode never arms")

        session.workspaceMode = .perform
        XCTAssertFalse(session.isQuantisedPerformToggleArmingActive,
                       "no boundary exists while the transport is stopped — fall back to immediate")

        startEngineForManualTicks(engine)
        defer { engine.stop() }
        XCTAssertTrue(session.isQuantisedPerformToggleArmingActive)

        session.performQuantise = .off
        XCTAssertFalse(session.isQuantisedPerformToggleArmingActive,
                       "Q:OFF is exactly today's immediate toggle")
    }

    // MARK: - Arm capture

    func test_toggleQuantisedMuteArmsTheInverseOfTheResolvedValuePerTrack() {
        let (session, engine, _) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        let phrase = session.store.selectedPhrase
        let layer = session.store.layer(id: muteLayerID)!
        let trackID = session.store.tracks[0].id

        session.toggleQuantisedMute(trackIDs: [trackID], basisPhrase: phrase, layer: layer, stepIndex: 0)
        XCTAssertEqual(
            engine.quantisedPendingChanges,
            [.mute(trackID: trackID, muted: true, basisPhraseID: phrase.id)],
            "an unmuted track arms 'muted' — the inverse of the value resolved at arm time"
        )

        // Tap-while-armed cancels.
        session.toggleQuantisedMute(trackIDs: [trackID], basisPhrase: phrase, layer: layer, stepIndex: 0)
        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty)
    }

    func test_toggleQuantisedFillCueGroupTogglesAcrossTheEditSet() {
        let (session, engine, _) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        session.appendTrack(trackType: .monoMelodic)
        let groupTrackIDs = Array(session.store.tracks.map(\.id).prefix(2))
        guard groupTrackIDs.count == 2 else {
            return XCTFail("fixture needs at least two tracks")
        }

        session.toggleQuantisedFillCue(trackIDs: groupTrackIDs)
        XCTAssertTrue(groupTrackIDs.allSatisfy { engine.hasQuantisedPendingFillCue(for: $0) })

        // Mixed state: one cancelled by a solo tap → group tap re-arms it.
        session.toggleQuantisedFillCue(trackIDs: [groupTrackIDs[0]])
        XCTAssertFalse(engine.hasQuantisedPendingFillCue(for: groupTrackIDs[0]))
        session.toggleQuantisedFillCue(trackIDs: groupTrackIDs)
        XCTAssertTrue(groupTrackIDs.allSatisfy { engine.hasQuantisedPendingFillCue(for: $0) })

        // All armed → group tap cancels all.
        session.toggleQuantisedFillCue(trackIDs: groupTrackIDs)
        XCTAssertFalse(groupTrackIDs.contains { engine.hasQuantisedPendingFillCue(for: $0) })
    }

    // MARK: - Boundary commit staging

    func test_committedMuteStagesTheOverlayCellAndRetiresTheEngineOverride() {
        let (session, engine, _) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        let phrase = session.store.selectedPhrase
        let layer = session.store.layer(id: muteLayerID)!
        let trackID = session.store.tracks[0].id

        session.toggleQuantisedMute(trackIDs: [trackID], basisPhrase: phrase, layer: layer, stepIndex: 0)

        // Drive the engine across the bar boundary (16 ticks per bar by
        // default); the committed handler runs inline on main.
        for tick in UInt64(0)...16 {
            engine.processTick(tickIndex: tick, now: TimeInterval(tick) / 10)
        }

        XCTAssertTrue(session.phrasePerformOverlay.isDirty,
                      "the commit stages the same perform-overlay record an immediate tap would")
        XCTAssertEqual(
            session.performOverlayCell(phraseID: phrase.id, layerID: muteLayerID, trackID: trackID),
            .single(.bool(true))
        )
        XCTAssertTrue(engine.quantisedMuteOverridesForTesting.isEmpty,
                      "after staging publishes the snapshot, the live override retires")
        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty)
    }

    func test_committedLengthLimitedMuteStagesBarCellForTheCommittedBar() throws {
        let (session, engine, _) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }
        session.workspaceMode = .perform

        let phrase = session.store.selectedPhrase
        let trackID = session.store.tracks[0].id

        session.applyCommittedQuantisedToggles([
            .lengthLimitedMute(
                trackID: trackID,
                muted: true,
                basisPhraseID: phrase.id,
                lengthBars: 1,
                startTick: 16
            )
        ])

        let staged = try XCTUnwrap(session.performOverlayCell(
            phraseID: phrase.id,
            layerID: muteLayerID,
            trackID: trackID
        ))
        guard case let .bars(values) = staged else {
            return XCTFail("Expected one-bar latch to stage a bar-shaped phrase cell, got \(staged)")
        }

        XCTAssertEqual(values.count, phrase.lengthBars)
        XCTAssertEqual(values[0], .bool(false), "bar before the committed boundary keeps the resolved baseline")
        XCTAssertEqual(values[1], .bool(true), "tick 16 is the start of phrase bar 2 in the default phrase")
        XCTAssertEqual(values[2], .bool(false), "the one-bar length expires through phrase-cell resolution")
        XCTAssertTrue(engine.quantisedMuteOverridesForTesting.isEmpty)
    }

    // MARK: - Leaving the quantise context cancels arms

    func test_flippingQToOffCancelsPendingArms() {
        let (session, engine, _) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        let trackID = session.store.tracks[0].id
        engine.armQuantisedToggle(.fillCue(trackID: trackID))
        XCTAssertFalse(engine.quantisedPendingChanges.isEmpty)

        session.performQuantise = .off
        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty,
                      "Q:OFF must not leave a stale change to fire at a boundary the player opted out of")
    }

    func test_leavingPerformModeCancelsPendingArms() {
        let (session, engine, _) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        let trackID = session.store.tracks[0].id
        engine.armQuantisedToggle(.fillCue(trackID: trackID))
        XCTAssertFalse(engine.quantisedPendingChanges.isEmpty)

        session.workspaceMode = .setup
        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty)
    }

    func test_externalDocumentChangeResetsTheScheduler() {
        let (session, engine, box) = makeSession()
        session.workspaceMode = .perform
        startEngineForManualTicks(engine)
        defer { engine.stop() }

        let trackID = session.store.tracks[0].id
        engine.armQuantisedToggle(.fillCue(trackID: trackID))

        var changedProject = box.document.project
        changedProject.appendTrack(trackType: .monoMelodic)
        session.ingestExternalDocumentChange(changedProject)

        XCTAssertTrue(engine.quantisedPendingChanges.isEmpty,
                      "a replaced document invalidates every armed change")
    }
}
