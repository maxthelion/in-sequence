import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER REPRODUCTION (not a frozen rail) for the round-2 claim:
///
///   "Round-2 P3 removed the origin shift but added NO real early dispatch — the
///    flam is unmasked, not fixed. The 100 ms look-ahead lead is realised nowhere
///    at runtime."
///
/// These tests demonstrate, deterministically, that
/// `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)` discards `dispatchNow`
/// and returns the event's TRUE, UNSHIFTED musical stamp (identical to the plain
/// `scheduledAudioTime(for:)` the pre-Phase-3 path produced), so the pump hands
/// the sink a stamp with ZERO look-ahead margin. Combined with the fact that the
/// pump (`TickClock`) wakes AT the grid (no wake lead) and `dispatchTick`
/// dispatches the CURRENT step, the sink's
/// `SamplePlaybackEngine.effectivePlaybackTime(for:now:)` clamps to immediate at
/// grid-aligned dispatch — the stale->immediate flam the phase was meant to fix.
///
/// NOTE ON EXPECTED RESULT: `test_leadStampedAudioTime_isNoOp_flamUnmasked` is
/// authored to PASS against the current (hollow) build — i.e. it REPRODUCES the
/// defect (documents that the lead is a no-op). If the flam is genuinely fixed
/// (the pump dispatches early / the stamp carries a real future margin), the
/// `XCTAssert*` marked "FLAM PRESENT" below would need to be inverted — this file
/// is the failing-evidence artifact, not a gate.
final class Phase3LeadNoOpReproductionTests: XCTestCase {

    private static let lead: TimeInterval = 0.100 // Gate-1 locked look-ahead lead.

    override func setUp() {
        MainAudioGraph.useManualRenderingForAutomation = true
    }

    override func tearDown() {
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    private func makeStartedController() -> EngineController {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )
        controller.apply(documentModel: .empty)
        controller.setBPM(120)
        controller.start()
        return controller
    }

    /// CORE REPRODUCTION. `leadStampedAudioTime` ignores `dispatchNow` and equals
    /// the plain unshifted stamp, so the "100 ms early dispatch" is realised
    /// nowhere in the stamp; and at grid-aligned dispatch the stamp clamps to
    /// immediate.
    func test_leadStampedAudioTime_isNoOp_flamUnmasked() {
        let controller = makeStartedController()
        defer { controller.stop() }

        let musical: TimeInterval = 0.5 // some step's musical position (cumulative seconds)

        // The stamp is IDENTICAL whether the pump claims to dispatch a full lead
        // EARLY, exactly at the grid, or grossly LATE. `dispatchNow` is dead.
        let stampEarly = controller.leadStampedAudioTime(forMusicalSeconds: musical, dispatchNow: musical - Self.lead)
        let stampAtGrid = controller.leadStampedAudioTime(forMusicalSeconds: musical, dispatchNow: musical)
        let stampLate = controller.leadStampedAudioTime(forMusicalSeconds: musical, dispatchNow: musical + 5.0)
        let plainStamp = controller.scheduledAudioTime(for: musical)

        let e = try? XCTUnwrap(stampEarly)
        let g = try? XCTUnwrap(stampAtGrid)
        let l = try? XCTUnwrap(stampLate)
        let p = try? XCTUnwrap(plainStamp)
        XCTAssertNotNil(e); XCTAssertNotNil(g); XCTAssertNotNil(l); XCTAssertNotNil(p)

        // dispatchNow is DISCARDED — no early-dispatch logic exists in the stamp.
        XCTAssertEqual(e!.hostTime, g!.hostTime,
                       "leadStampedAudioTime returned the SAME stamp for a lead-early vs grid-aligned dispatch — dispatchNow is discarded (LookAheadScheduling.swift:115 `_ = dispatchNow`).")
        XCTAssertEqual(g!.hostTime, l!.hostTime,
                       "leadStampedAudioTime returned the SAME stamp for a grid vs grossly-late dispatch — dispatchNow is discarded.")

        // The lead lives NOWHERE in the stamp: it is byte-identical to the plain
        // pre-Phase-3 `scheduledAudioTime(for:)` (== `dispatchSampleAudioTime`).
        XCTAssertEqual(g!.hostTime, p!.hostTime,
                       "leadStampedAudioTime == plain scheduledAudioTime — the 100 ms lead is realised nowhere in the stamp.")

        // FLAM PRESENT: the pump (TickClock) wakes AT the grid, so the real
        // dispatch wall-clock for this step is its grid host time. At that instant
        // the stamp is NOT in the future, so effectivePlaybackTime clamps to
        // IMMEDIATE — the stale->immediate flam returns.
        let gridDispatchHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: musical)
        let effectiveAtGrid = SamplePlaybackEngine.effectivePlaybackTime(for: stampAtGrid, now: gridDispatchHostSeconds)
        XCTAssertNil(effectiveAtGrid,
                     "FLAM: at grid-aligned dispatch the stamp is not in the future -> effectivePlaybackTime clamps to IMMEDIATE. The look-ahead lead provides no margin.")

        // And even a MODEST dispatch lateness (1 ms, well inside the 100 ms lead
        // the pump was supposed to absorb) also clamps to immediate.
        let effectiveLate1ms = SamplePlaybackEngine.effectivePlaybackTime(for: stampAtGrid, now: gridDispatchHostSeconds + 0.001)
        XCTAssertNil(effectiveLate1ms,
                     "FLAM: a 1 ms-late dispatch (far inside the 100 ms lead) still clamps to IMMEDIATE — the lead absorbs no lateness.")
    }

    /// CONTRAST: a stamp that genuinely carried the 100 ms lead (round-1's origin
    /// shift, or any real early-dispatch margin) WOULD survive a grid-aligned and
    /// a 1 ms-late dispatch. This proves the assertions above are load-bearing:
    /// they fail specifically because the round-2 stamp has zero margin, not
    /// because `effectivePlaybackTime` rejects everything.
    func test_leadProtectedStamp_survivesLateDispatch_contrast() {
        let controller = makeStartedController()
        defer { controller.stop() }

        let musical: TimeInterval = 0.5
        let gridDispatchHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: musical)

        // A stamp with a REAL +100 ms future margin (what a working look-ahead
        // would hand the sink relative to the pump's dispatch wall clock).
        let protectedStamp = AVAudioTime(
            hostTime: AVAudioTime.hostTime(forSeconds: gridDispatchHostSeconds + Self.lead)
        )

        XCTAssertNotNil(
            SamplePlaybackEngine.effectivePlaybackTime(for: protectedStamp, now: gridDispatchHostSeconds),
            "a lead-protected stamp survives grid-aligned dispatch (scheduled, not immediate)."
        )
        XCTAssertNotNil(
            SamplePlaybackEngine.effectivePlaybackTime(for: protectedStamp, now: gridDispatchHostSeconds + 0.001),
            "a lead-protected stamp survives a 1 ms-late dispatch (scheduled, not immediate)."
        )
    }
}
