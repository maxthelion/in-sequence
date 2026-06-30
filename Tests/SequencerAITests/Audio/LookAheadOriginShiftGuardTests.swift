import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER work-product guard (NOT a frozen rail) for the Phase 3 flam fix.
///
/// # Why this exists
///
/// The frozen rail `LookAheadSchedulingTests` (GATE B / GATE C) builds the
/// controller with `EngineController(...)` + `apply` + `setBPM` and NEVER calls
/// the mechanism that ships the lead (`start()` →
/// `AudioMasterClock.captureOrigin(_:leadSeconds:)`, the origin shift). It then
/// hands `leadStampedAudioTime` an artificially EARLY dispatch `now = m - lead +
/// lateness` (< m). Because the rail derives BOTH the expected stamp AND `now`
/// independently of the lead mechanism, reverting the shipped fix (the origin
/// shift in `captureOrigin`) to a no-op leaves that rail GREEN — the rail is
/// ceremonial w.r.t. the actual fix.
///
/// This guard closes that hole the right way: it drives the REAL production
/// mechanism — `AudioMasterClock.captureOrigin(..., leadSeconds:)` — and asserts
/// the origin is ACTUALLY shifted forward by the lead, so a KNIFE-EDGE dispatch
/// (`now == m`, no artificial early offset) lands in the FUTURE and is NOT
/// clamped to immediate. Revert the origin shift (the shipped flam fix) to a
/// no-op and this goes RED. It touches no frozen rail.
final class LookAheadOriginShiftGuardTests: XCTestCase {

    /// Gate-1 LOCKED lead (spec constant — not read back from the feature).
    private static let specLeadSeconds: TimeInterval = 0.100

    /// The shipped fix shifts the captured origin forward by the lead. With no
    /// render position available (offline fixture: `renderPositionProvider` nil),
    /// `captureOrigin` takes the fallback branch and `originHostSeconds` must
    /// include the lead — so an event at musical second `m` is stamped at
    /// `fallback + lead + m`, strictly ahead of a knife-edge dispatch at `now ==
    /// fallback + m`. Reverting the origin shift makes the stamp `fallback + m ==
    /// now`, which `effectivePlaybackTime` clamps to immediate (the flam) → RED.
    func test_captureOriginShiftsByLead_knifeEdgeDispatchNotClamped() throws {
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { nil })

        let fallback: TimeInterval = 1000.0
        clock.captureOrigin(fallbackHostSeconds: fallback, leadSeconds: Self.specLeadSeconds)

        let m: TimeInterval = 1.0

        // 1) The origin shift is REAL: the stamp is fallback + lead + m.
        let stamp = clock.audioTime(atMusicalSeconds: m)
        let stampSeconds = AVAudioTime.seconds(forHostTime: stamp.hostTime)
        XCTAssertEqual(
            stampSeconds, fallback + Self.specLeadSeconds + m, accuracy: 1e-6,
            "captureOrigin must shift the origin forward by the look-ahead lead — the shipped flam fix. " +
            "Got \(stampSeconds), expected \(fallback + Self.specLeadSeconds + m)."
        )

        // 2) Behavioural consequence: a knife-edge dispatch (now == the event's
        // UNSHIFTED musical time — the wake the pump would hit with no lead, NO
        // artificial early offset) is still BEFORE the shifted stamp, so it is NOT
        // clamped to immediate. The clamp uses a STRICT `scheduled > now`, so the
        // knife-edge `now` is taken through the same host-time round-trip as the
        // stamp (the unshifted stamp host-seconds), matching the production clamp.
        let knifeEdgeNow = AVAudioTime.seconds(
            forHostTime: AVAudioTime.hostTime(forSeconds: fallback + m)
        )
        let effective = SamplePlaybackEngine.effectivePlaybackTime(for: stamp, now: knifeEdgeNow)
        XCTAssertNotNil(
            effective,
            "with the origin shifted forward by the lead, a knife-edge dispatch (now=\(knifeEdgeNow)) must " +
            "land before the shifted stamp (\(stampSeconds)) and NOT clamp to immediate. A nil here is the " +
            "flam returning — the origin shift was reverted to a no-op."
        )
    }

    /// The render-derived upgrade path must carry the SAME lead (so the live
    /// fallback→render origin upgrade does not silently drop the lead). Drives a
    /// provider that starts nil (fallback capture) then yields a render position
    /// (upgrade), and asserts the upgraded host origin still includes the lead.
    func test_renderDerivedUpgradeCarriesLead() throws {
        var position: (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)?
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })

        // Capture provisionally with no render position (fallback branch).
        let fallback: TimeInterval = 0
        clock.captureOrigin(fallbackHostSeconds: fallback, leadSeconds: Self.specLeadSeconds)

        // Now a render position appears; the next conversion triggers the upgrade.
        let renderHostSeconds: TimeInterval = 2000.0
        position = (
            sampleTime: 0,
            hostTime: AVAudioTime.hostTime(forSeconds: renderHostSeconds),
            sampleRate: 48_000
        )

        let m: TimeInterval = 1.0
        let stampSeconds = AVAudioTime.seconds(forHostTime: clock.audioTime(atMusicalSeconds: m).hostTime)
        XCTAssertEqual(
            stampSeconds, renderHostSeconds + Self.specLeadSeconds + m, accuracy: 1e-6,
            "the fallback→render-derived origin upgrade must carry the SAME look-ahead lead; got " +
            "\(stampSeconds), expected \(renderHostSeconds + Self.specLeadSeconds + m)."
        )
    }

    /// NEGATIVE CONTROL: with NO lead (the offline / manual-driver path passes 0),
    /// a knife-edge dispatch IS clamped — proving the guard above is load-bearing
    /// (it is the lead that prevents the clamp, nothing else), and confirming the
    /// 0-frame offline gate is unaffected by the live lead.
    func test_noLead_knifeEdgeDispatchIsClamped_negativeControl() throws {
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { nil })
        let fallback: TimeInterval = 1000.0
        clock.captureOrigin(fallbackHostSeconds: fallback, leadSeconds: 0)

        let m: TimeInterval = 1.0
        let stamp = clock.audioTime(atMusicalSeconds: m)
        // The clamp is strict (`scheduled > now`); take `now` as the stamp's own
        // host-time round-trip so equality clamps, mirroring the production path.
        let knifeEdgeNow = AVAudioTime.seconds(forHostTime: stamp.hostTime)
        XCTAssertNil(
            SamplePlaybackEngine.effectivePlaybackTime(for: stamp, now: knifeEdgeNow),
            "with no lead the knife-edge stamp equals `now` and must clamp to immediate — the pre-Phase-3 " +
            "flam. If this does not clamp, the positive guard would be vacuous."
        )
    }
}
