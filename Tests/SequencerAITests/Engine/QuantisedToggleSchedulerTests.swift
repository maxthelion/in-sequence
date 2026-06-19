import Foundation
import XCTest
@testable import SequencerAI

/// Pins the QuantisedToggleScheduler contract (perform/setup split slice 2):
/// arm → group-commit at the bar boundary; second arm of the same key
/// cancels; committed mutes stay live until confirmed; fill cues are active
/// for exactly one bar.
final class QuantisedToggleSchedulerTests: XCTestCase {
    private let trackA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let trackB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let phraseID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    private func muteChange(_ trackID: UUID, muted: Bool = true) -> QuantisedToggleChange {
        .mute(trackID: trackID, muted: muted, basisPhraseID: phraseID)
    }

    private func oneBarMuteChange(_ trackID: UUID, muted: Bool = true, startTick: UInt64? = nil) -> QuantisedToggleChange {
        .lengthLimitedMute(
            trackID: trackID,
            muted: muted,
            basisPhraseID: phraseID,
            lengthBars: 1,
            startTick: startTick
        )
    }

    func test_armedChangeCommitsOnlyOnTheBarBoundaryTick() {
        let scheduler = QuantisedToggleScheduler()
        XCTAssertEqual(scheduler.armOrCancel(muteChange(trackA)), .armed)

        // Mid-bar ticks never commit.
        for tick in UInt64(13)...15 {
            XCTAssertTrue(scheduler.commitAtBarBoundary(upcomingTick: tick, ticksPerBar: 16).isEmpty)
            XCTAssertTrue(scheduler.activeMuteOverrides().isEmpty)
        }

        let committed = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)
        XCTAssertEqual(committed, [muteChange(trackA)])
        XCTAssertEqual(scheduler.activeMuteOverrides(), [trackA: true])
        XCTAssertTrue(scheduler.armedChanges().isEmpty, "commit drains the armed set")

        // The next boundary has nothing left to commit.
        XCTAssertTrue(scheduler.commitAtBarBoundary(upcomingTick: 32, ticksPerBar: 16).isEmpty)
    }

    func test_secondArmOfSameKeyCancels() {
        let scheduler = QuantisedToggleScheduler()
        XCTAssertEqual(scheduler.armOrCancel(muteChange(trackA, muted: true)), .armed)
        // Tap-while-armed cancels regardless of the carried value.
        XCTAssertEqual(scheduler.armOrCancel(muteChange(trackA, muted: false)), .cancelled)
        XCTAssertTrue(scheduler.armedChanges().isEmpty)

        XCTAssertTrue(scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16).isEmpty)
        XCTAssertTrue(scheduler.activeMuteOverrides().isEmpty)
    }

    func test_lengthLimitedMuteUsesMuteKeyAndCommitsWithBoundaryTick() {
        let scheduler = QuantisedToggleScheduler()
        XCTAssertEqual(scheduler.armOrCancel(oneBarMuteChange(trackA)), .armed)
        XCTAssertEqual(scheduler.armOrCancel(muteChange(trackA, muted: false)), .cancelled,
                       "held and length-limited mutes share the same per-track mute arm slot")

        XCTAssertEqual(scheduler.armOrCancel(oneBarMuteChange(trackA)), .armed)
        let committed = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)
        XCTAssertEqual(committed, [oneBarMuteChange(trackA, startTick: 16)])
        XCTAssertEqual(scheduler.activeMuteOverrides(), [trackA: true])
    }

    func test_muteAndFillKeysAreIndependentPerTrack() {
        let scheduler = QuantisedToggleScheduler()
        XCTAssertEqual(scheduler.armOrCancel(muteChange(trackA)), .armed)
        XCTAssertEqual(scheduler.armOrCancel(.fillCue(trackID: trackA)), .armed,
                       "a fill cue must not collide with the armed mute on the same track")
        XCTAssertEqual(scheduler.armedChanges().count, 2)
    }

    func test_groupCommit_changesArmedInTheSameWindowLandTogetherInArmOrder() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(muteChange(trackA, muted: true))
        scheduler.armOrCancel(.fillCue(trackID: trackB))
        scheduler.armOrCancel(muteChange(trackB, muted: false))

        let committed = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)
        XCTAssertEqual(
            committed,
            [
                muteChange(trackA, muted: true),
                .fillCue(trackID: trackB),
                muteChange(trackB, muted: false),
            ],
            "every change armed in the window commits on the SAME boundary, in arm order (Rytm mute-preselect)"
        )
        XCTAssertEqual(scheduler.activeMuteOverrides(), [trackA: true, trackB: false])
        XCTAssertEqual(scheduler.activeFillCueTrackIDs(atTick: 16), [trackB])
    }

    func test_fillCueIsActiveForExactlyOneBar() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(.fillCue(trackID: trackA))
        _ = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)

        for tick in UInt64(16)...31 {
            XCTAssertEqual(scheduler.activeFillCueTrackIDs(atTick: tick), [trackA])
        }
        XCTAssertTrue(scheduler.activeFillCueTrackIDs(atTick: 32).isEmpty,
                      "the cue auto-returns at the following boundary (Rytm next-cycle cue)")

        // The boundary pass also garbage-collects the expired cue.
        _ = scheduler.commitAtBarBoundary(upcomingTick: 32, ticksPerBar: 16)
        XCTAssertTrue(scheduler.activeFillCueTrackIDs(atTick: 32).isEmpty)
    }

    func test_reCueDuringActiveBarExtendsSeamlesslyIntoTheNextBar() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(.fillCue(trackID: trackA))
        _ = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)

        // Tap again inside the cued bar: the key is free (committed, not
        // armed), so this arms the NEXT bar's cue.
        XCTAssertEqual(scheduler.armOrCancel(.fillCue(trackID: trackA)), .armed)
        _ = scheduler.commitAtBarBoundary(upcomingTick: 32, ticksPerBar: 16)
        XCTAssertEqual(scheduler.activeFillCueTrackIDs(atTick: 32), [trackA])
        XCTAssertTrue(scheduler.activeFillCueTrackIDs(atTick: 48).isEmpty)
    }

    func test_confirmMuteAppliedRetiresOnlyTheNamedOverrides() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(muteChange(trackA, muted: true))
        scheduler.armOrCancel(muteChange(trackB, muted: true))
        _ = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)

        scheduler.confirmMuteApplied(trackIDs: [trackA])
        XCTAssertEqual(scheduler.activeMuteOverrides(), [trackB: true])
    }

    func test_cancelAllArmedLeavesCommittedStateUntouched() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(.fillCue(trackID: trackA))
        _ = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)
        scheduler.armOrCancel(muteChange(trackB))

        scheduler.cancelAllArmed()
        XCTAssertTrue(scheduler.armedChanges().isEmpty)
        XCTAssertEqual(scheduler.activeFillCueTrackIDs(atTick: 20), [trackA],
                       "cancelling arms must not kill the cue bar already playing")
    }

    func test_resetRuntimeClearsEverything() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(muteChange(trackA))
        scheduler.armOrCancel(.fillCue(trackID: trackB))
        _ = scheduler.commitAtBarBoundary(upcomingTick: 16, ticksPerBar: 16)
        scheduler.armOrCancel(muteChange(trackB))

        scheduler.resetRuntime()
        XCTAssertTrue(scheduler.armedChanges().isEmpty)
        XCTAssertTrue(scheduler.activeMuteOverrides().isEmpty)
        XCTAssertTrue(scheduler.activeFillCueTrackIDs(atTick: 16).isEmpty)
    }

    func test_tickZeroIsABarBoundary() {
        let scheduler = QuantisedToggleScheduler()
        scheduler.armOrCancel(muteChange(trackA))
        XCTAssertEqual(
            scheduler.commitAtBarBoundary(upcomingTick: 0, ticksPerBar: 16),
            [muteChange(trackA)]
        )
    }
}
