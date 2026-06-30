import AVFoundation
import XCTest
@testable import SequencerAI

/// FROZEN RAIL — Phase 3 flam-fix START call-site guard.
///
/// # Frozen-rail status (do NOT weaken/skip/delete — HARD RULE)
///
/// This file matches the fleet brief's frozen-rail glob ("any
/// `Tests/.../*LookAhead*` test"), so it is a FROZEN RAIL: builders must not
/// edit, weaken, `XCTSkip`, delete, or stub it, and the integrator's
/// rails-diff-empty proof covers it. It was authored from the SPEC + the
/// production call-site contract (NOT from a builder transcript) to close a
/// reward-hacking hole the other Phase 3 rails leave open (below). Its earlier
/// header described it as a deletable "verifier work-product"; that escape hatch
/// was the very hole a prosecutor exploited ("the only catch is a file a builder
/// may delete"), so it is removed: this guard is frozen exactly like
/// `LookAheadSchedulingTests`.
///
/// # The hole this closes (prosecution finding, 2026-06-30)
///
/// The Phase 3 flam fix ships ENTIRELY at one production call site: live
/// transport start shifts the captured render origin forward by the look-ahead
/// lead —
///   `EngineController.start()` →
///   `audioMasterClock.captureOrigin(fallbackHostSeconds:, leadSeconds: lookAheadLeadSeconds)`
/// (`EngineController.swift:1028`).
///
/// Neither the frozen rail (`LookAheadSchedulingTests`) nor the earlier
/// work-product guard (`LookAheadOriginShiftGuardTests`) exercises THAT call
/// site:
///   - `LookAheadSchedulingTests` builds the controller with
///     `EngineController(...) + apply + setBPM` and NEVER calls `start()`, then
///     feeds `leadStampedAudioTime` a TEST-supplied early `now = m - lead +
///     lateness`. Its non-clamp is a consequence of the test choosing an early
///     `now`, not of the engine applying any lead — so reverting the call site
///     to `leadSeconds: 0` leaves it GREEN.
///   - `LookAheadOriginShiftGuardTests` calls `captureOrigin(..., leadSeconds:
///     specLeadSeconds)` with the lead HARD-CODED as the argument, proving
///     `captureOrigin` honours a non-zero lead — but it does not drive the
///     production call site that DECIDES what lead to pass, so reverting that
///     call site to `0` also leaves it GREEN.
///   - The testing transport seam `startTransportWithoutClockForTesting(now:)`
///     calls `captureOrigin(fallbackHostSeconds:)` with NO `leadSeconds`
///     (defaults to 0) — so it also does not exercise the lead.
///
/// Empirically verified: with `EngineController.swift:1028` reverted to
/// `leadSeconds: 0` (knife-edge stamping, the ~47 ms flam re-introduced), all of
/// `LookAheadSchedulingTests` + `LookAheadOriginShiftGuardTests` stayed GREEN.
/// The ONLY remaining catch was the device-dependent capture rig, which the
/// fleet brief permits to be unavailable — so the deterministic substitute did
/// NOT guard the fix.
///
/// # What this guard asserts
///
/// It drives the REAL production path — `EngineController.start()` over a real
/// `MainAudioGraph` in offline manual-rendering mode, with an EMPTY document (a
/// live session, no firing tracks, so start() schedules no voices) — and asserts
/// the captured clock origin was shifted forward by the look-ahead lead. At
/// start there is no render position yet, so `captureOrigin` takes the fallback
/// branch and sets `originHostSeconds = systemUptime + lead`. `systemUptime` is
/// monotonic and start() is fast, so the origin host-seconds read back for
/// musical second 0 must exceed the `systemUptime` sampled just BEFORE `start()`
/// by at least (most of) the lead. Revert the call site to `leadSeconds: 0` and
/// this goes RED. It exercises only production seams and touches no OTHER frozen
/// rail (it is itself one).
final class LookAheadStartCallSiteGuardTests: XCTestCase {

    /// Gate-1 LOCKED lead (spec constant — not read back from the feature).
    private static let specLeadSeconds: TimeInterval = 0.100

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    /// THE GUARD. Drives the production `start()` call site and asserts the
    /// captured origin carries the look-ahead lead. `systemUptime` is monotonic
    /// and `start()` is fast, so the origin host-seconds for musical second 0
    /// (`fallback + lead`, where `fallback` is the `systemUptime` sampled INSIDE
    /// `start()`, i.e. >= `before`) must exceed `before` by at least the lead.
    /// A generous slack absorbs only scheduling jitter — far smaller than the
    /// 100 ms lead — so a reverted call site (`leadSeconds: 0`, origin == fallback,
    /// lead absent) fails: `originHost - before` would be ~0, well under the lead.
    func test_start_capturesOriginWithLookAheadLead() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )
        // Empty document: live session active, no firing tracks, so start()
        // brings the transport up without scheduling any sample voices.
        controller.apply(documentModel: .empty)
        controller.setBPM(120)

        // The lead the engine SHOULD apply (>= the spec lead by the frozen rail).
        let lead = controller.lookAheadLeadSeconds
        XCTAssertGreaterThanOrEqual(lead, Self.specLeadSeconds)

        let before = ProcessInfo.processInfo.systemUptime
        controller.start()
        defer { controller.stop() }

        XCTAssertTrue(controller.isRunning, "start() must take the transport live for this guard to be meaningful")

        // Origin host-seconds for musical second 0 (== captured origin). With the
        // lead applied this is `fallback + lead`, fallback >= before.
        let originHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)

        // Slack covers only scheduling jitter between sampling `before` and the
        // `systemUptime` read inside start(); it is an order of magnitude below
        // the 100 ms lead, so a lead-0 revert (delta ~= jitter) fails this.
        let jitterSlack: TimeInterval = 0.030
        let observedLead = originHostSeconds - before
        XCTAssertGreaterThanOrEqual(
            observedLead, lead - jitterSlack,
            "EngineController.start() must shift the captured render origin forward by the look-ahead lead " +
            "(\(lead) s) — the production flam fix at the start() call site. Observed origin lead " +
            "\(observedLead) s (origin host-seconds \(originHostSeconds), before \(before)). A value near 0 " +
            "means the call site was reverted to leadSeconds: 0 — the ~47 ms stale→immediate flam is back."
        )
    }
}
