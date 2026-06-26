import SwiftUI
import XCTest
@testable import SequencerAI

/// #60 — mute and solo must be mutually exclusive per track/bus.
///
/// Precedence: the just-engaged control wins. Engaging solo clears mute;
/// engaging mute drops the track from solo. The invariant is enforced at the
/// model level (the session mutation setters), so the two indicators can never
/// both show active on the same track, and the resolved effective-audibility
/// (`EngineController.effectiveMixerMuteState`) follows the rule.
@MainActor
final class TrackMuteSoloExclusivityTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession() -> (SequencerDocumentSession, UUID) {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        return (session, trackID)
    }

    private func mix(_ session: SequencerDocumentSession, _ trackID: UUID) -> TrackMixSettings {
        session.store.tracks.first(where: { $0.id == trackID })!.mix
    }

    // MARK: - Soloing a muted track clears the mute

    func test_soloingMutedTrack_clearsMute() {
        let (session, trackID) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        session.setTrackMuted(true, trackID: trackID)
        XCTAssertTrue(mix(session, trackID).isMuted)
        XCTAssertFalse(mix(session, trackID).isSoloed)

        // Engaging solo on the muted track must clear the mute.
        session.setTrackSoloed(true, trackID: trackID)
        XCTAssertTrue(mix(session, trackID).isSoloed)
        XCTAssertFalse(mix(session, trackID).isMuted, "solo must clear mute (mutual exclusion)")

        // The two indicators are never both active.
        XCTAssertFalse(mix(session, trackID).isMuted && mix(session, trackID).isSoloed)
    }

    // MARK: - Muting a soloed track drops it from solo

    func test_mutingSoloedTrack_clearsSolo() {
        let (session, trackID) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        session.setTrackSoloed(true, trackID: trackID)
        XCTAssertTrue(mix(session, trackID).isSoloed)
        XCTAssertFalse(mix(session, trackID).isMuted)

        // Engaging mute on the soloed track must drop it from solo.
        session.setTrackMuted(true, trackID: trackID)
        XCTAssertTrue(mix(session, trackID).isMuted)
        XCTAssertFalse(mix(session, trackID).isSoloed, "mute must clear solo (mutual exclusion)")

        XCTAssertFalse(mix(session, trackID).isMuted && mix(session, trackID).isSoloed)
    }

    // MARK: - toggleTrackMute enforces the invariant too

    func test_toggleMuteOnSoloedTrack_clearsSolo() {
        let (session, trackID) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        session.setTrackSoloed(true, trackID: trackID)
        session.toggleTrackMute(trackID: trackID)
        XCTAssertTrue(mix(session, trackID).isMuted)
        XCTAssertFalse(mix(session, trackID).isSoloed)
    }

    // MARK: - Effective audibility follows the precedence

    func test_effectiveAudibility_followsPrecedence_soloWins() {
        let (session, trackID) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        // Start muted, then solo: solo wins, track is NOT in the muted set.
        session.setTrackMuted(true, trackID: trackID)
        session.setTrackSoloed(true, trackID: trackID)

        let muteState = EngineController.effectiveMixerMuteState(
            tracks: session.store.tracks,
            buses: session.store.buses
        )
        XCTAssertTrue(muteState.isSoloActive)
        XCTAssertFalse(
            muteState.mutedTrackIDs.contains(trackID),
            "a soloed track (mute cleared) must be audible"
        )
    }

    func test_effectiveAudibility_followsPrecedence_muteWins() {
        let (session, trackID) = makeSession()
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        // Start soloed, then mute: mute wins, solo dropped, track is muted and
        // (with no other solo active) solo is no longer active at all.
        session.setTrackSoloed(true, trackID: trackID)
        session.setTrackMuted(true, trackID: trackID)

        let muteState = EngineController.effectiveMixerMuteState(
            tracks: session.store.tracks,
            buses: session.store.buses
        )
        XCTAssertFalse(muteState.isSoloActive, "the only soloed track was muted, so solo is inactive")
        XCTAssertTrue(muteState.mutedTrackIDs.contains(trackID), "a muted track must be silent")
    }
}
