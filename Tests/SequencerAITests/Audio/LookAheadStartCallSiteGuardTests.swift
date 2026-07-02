import AVFoundation
import XCTest
@testable import SequencerAI

/// Phase 3 production start-call guard — G2 AMENDMENT, OWNER-APPROVED
/// 2026-07-02 (locked thresholds: startup anchor lead = 50 ms, rail cap
/// = 60 ms, per the plan's "adjust on return and re-gate" provision).
///
/// The superseded overnight implementation tried to realize look-ahead by
/// shifting the master-clock origin forward by the lead. That made tests green
/// but paid the lead as first-play latency. The recovery plan made the opposite
/// invariant explicit; the G2 amendment refines it: `start()` anchors musical
/// second 0 EXACTLY `AudioMasterClock.startupAnchorLeadSeconds` after the real
/// render/fallback origin — a small NAMED transport-start constant that makes
/// step 0's stamp schedulable (the 2026-07-02 rig measured a zero-anchored
/// step 0 landing +41 ms off-grid, non-deterministically). NOT zero, NOT
/// `lookAheadLeadSeconds` (the look-ahead lead belongs to the pump dispatch
/// horizon, never the origin), and the legacy `captureOrigin(leadSeconds:)`
/// offset stays at its default zero. The spirit is unchanged: the origin
/// offset is a small named constant, never the look-ahead lead.
final class LookAheadStartCallSiteGuardTests: XCTestCase {

    /// Gate-1 LOCKED lead (spec constant — not read back from the feature).
    private static let specLeadSeconds: TimeInterval = 0.100

    /// The G2 OWNER-LOCKED startup-anchor rail cap (spec constant — not read
    /// back from the feature). Any origin offset above this is treated as a
    /// lead-shaped origin delay and fails.
    private static let specStartupAnchorRailCapSeconds: TimeInterval = 0.060

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    func test_start_anchorsCapturedOriginByExactlyStartupAnchorLead() throws {
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

        // The lead remains a real scheduler contract, and it must sit strictly
        // ABOVE the anchor rail cap so the two constants can never be confused.
        let lead = controller.lookAheadLeadSeconds
        XCTAssertGreaterThanOrEqual(lead, Self.specLeadSeconds)
        XCTAssertGreaterThan(
            lead, Self.specStartupAnchorRailCapSeconds,
            "the look-ahead lead must exceed the startup-anchor rail cap — otherwise a lead-shifted " +
            "origin could pass the cap checks below."
        )
        XCTAssertGreaterThan(
            AudioMasterClock.startupAnchorLeadSeconds, 0,
            "production start() must anchor by a real positive startup lead (a zero anchor is the " +
            "unschedulable knife-edge step-0 stamp)."
        )
        XCTAssertLessThanOrEqual(
            AudioMasterClock.startupAnchorLeadSeconds, Self.specStartupAnchorRailCapSeconds,
            "the startup anchor must respect the owner-locked rail cap."
        )

        // The render frame at transport start: static in manual rendering mode
        // (this test renders no frames), so it is the exact frame start()'s
        // `captureOrigin` reads.
        let renderFrameAtStart = try XCTUnwrap(graph.renderPosition).sampleTime

        let before = ProcessInfo.processInfo.systemUptime
        controller.start()
        defer { controller.stop() }

        XCTAssertTrue(controller.isRunning, "start() must take the transport live for this guard to be meaningful")

        // FRAME-DOMAIN EXACT: the captured origin frame must be the render
        // frame plus EXACTLY the startup anchor — not zero (anchor dropped),
        // not the lead (origin delay), and with no residual legacy
        // `leadSeconds` contribution (any extra offset breaks the equality).
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(correlation.isRenderDerived)
        let expectedAnchorFrames = AVAudioFramePosition(
            (AudioMasterClock.startupAnchorLeadSeconds * correlation.sampleRate).rounded()
        )
        XCTAssertEqual(
            correlation.sampleTime, renderFrameAtStart + expectedAnchorFrames,
            "EngineController.start() must anchor musical second 0 by EXACTLY " +
            "startupAnchorLeadSeconds (\(expectedAnchorFrames) frames): measured origin frame " +
            "\(correlation.sampleTime) vs render frame \(renderFrameAtStart). More means the " +
            "look-ahead lead (or a legacy leadSeconds) leaked into the origin; less/zero means the " +
            "anchor was dropped."
        )

        // HOST-DOMAIN WINDOW: origin host-seconds for musical second 0 sits the
        // anchor past the real start time (plus start() overhead), and never
        // beyond the rail cap — `before + lead` fails here.
        let originHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)
        let observedOffset = originHostSeconds - before
        XCTAssertGreaterThanOrEqual(
            observedOffset, AudioMasterClock.startupAnchorLeadSeconds - 1e-6,
            "EngineController.start() must anchor musical second 0 the startup lead past the origin; " +
            "observed offset \(observedOffset) s is below the anchor — the host origin was not anchored."
        )
        XCTAssertLessThanOrEqual(
            observedOffset,
            Self.specStartupAnchorRailCapSeconds,
            "EngineController.start() must not shift musical second 0 beyond the owner-locked " +
            "\(Self.specStartupAnchorRailCapSeconds * 1000) ms rail cap. Observed offset " +
            "\(observedOffset) s with lead \(lead) s — a value near the lead is the rejected " +
            "origin-delay mechanism."
        )
    }
}
