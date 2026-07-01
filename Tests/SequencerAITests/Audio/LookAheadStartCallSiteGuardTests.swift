import AVFoundation
import XCTest
@testable import SequencerAI

/// Phase 3 production start-call guard.
///
/// The superseded overnight implementation tried to realize look-ahead by
/// shifting the master-clock origin forward by the lead. That made tests green
/// but paid the lead as first-play latency. The recovery plan makes the opposite
/// invariant explicit: `start()` captures the real render/fallback origin for
/// musical second 0, and any look-ahead lead belongs to the pump dispatch
/// horizon, not to the origin.
final class LookAheadStartCallSiteGuardTests: XCTestCase {

    /// Gate-1 LOCKED lead (spec constant — not read back from the feature).
    private static let specLeadSeconds: TimeInterval = 0.100

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    func test_start_doesNotShiftCapturedOriginByLookAheadLead() throws {
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

        // The lead remains a real scheduler contract, but start() must not pay it
        // as first-play latency by moving the captured origin.
        let lead = controller.lookAheadLeadSeconds
        XCTAssertGreaterThanOrEqual(lead, Self.specLeadSeconds)

        let before = ProcessInfo.processInfo.systemUptime
        controller.start()
        defer { controller.stop() }

        XCTAssertTrue(controller.isRunning, "start() must take the transport live for this guard to be meaningful")

        // Origin host-seconds for musical second 0 (== captured origin). It should
        // be close to the real start time, not `before + lead`.
        let originHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)

        let observedOffset = originHostSeconds - before
        XCTAssertLessThanOrEqual(
            observedOffset,
            0.030,
            "EngineController.start() must not shift musical second 0 by the look-ahead lead. " +
            "Observed offset \(observedOffset) s with lead \(lead) s."
        )
    }
}
