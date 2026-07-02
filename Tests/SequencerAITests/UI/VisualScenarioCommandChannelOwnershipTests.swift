import XCTest
@testable import SequencerAI

/// The visual-command channel is a SINGLE-DRIVER protocol: exactly one
/// process-wide watcher loop may own the command file.
///
/// # Why (2026-07-02 12:40 drum-timing rig run — the "26.4 ms early step 0")
///
/// macOS window restoration after a `kill -9`'d harness run resurrects extra
/// document windows. Each `ContentView.onAppear` spawns its own
/// `VisualScenarioCommandRunner.runIfConfigured` loop bound to ITS OWN
/// `SequencerDocumentSession` + `EngineController`. In the measured run TWO
/// loops each applied every command payload:
///
/// - two 808 kits were created (one per session);
/// - `EngineController.start` fired twice, 9 ms apart (12:40:49.609 / .618) —
///   on TWO DIFFERENT controllers (both later `stop` logs show
///   `isRunning=true`), each with its own perfectly-anchored grid, origins
///   10.667 ms apart (probe: 1212888.538009 vs 1212888.548676);
/// - `masterRender=start:<same path>` opened TWO writers on ONE WAV file, so
///   the captured audio interleaved two internally-perfect grids — the rig's
///   onset analysis then reported a phantom "step 0 lands 26.4 ms early".
///
/// Each individual transport start was single-origin and on-grid; the defect
/// was the duplicated DRIVER. The fix: first `runIfConfigured` loop claims
/// process-wide ownership, duplicates are suppressed (with a DevActivity
/// trace), and ownership is released when the owning loop exits (window
/// closed / task cancelled) so a genuine handoff still works.
@MainActor
final class VisualScenarioCommandChannelOwnershipTests: XCTestCase {

    func test_firstClaimWins_duplicateClaimIsRejected() {
        // Isolate from any claim left by another test; restore on exit.
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
        defer { VisualScenarioCommandRunner.releaseCommandChannelOwnership() }
        XCTAssertTrue(
            VisualScenarioCommandRunner.claimCommandChannelOwnership(),
            "the first runner loop must claim the command channel"
        )
        XCTAssertFalse(
            VisualScenarioCommandRunner.claimCommandChannelOwnership(),
            "a duplicate runner loop (restored window) must NOT attach — a second driver " +
            "double-applies every command: two kits, two transports 9 ms apart, two master-render " +
            "writers on one WAV (the 2026-07-02 rig poisoning)"
        )
    }

    func test_releaseHandsOwnershipBack() {
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
        defer { VisualScenarioCommandRunner.releaseCommandChannelOwnership() }
        XCTAssertTrue(VisualScenarioCommandRunner.claimCommandChannelOwnership())
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
        XCTAssertTrue(
            VisualScenarioCommandRunner.claimCommandChannelOwnership(),
            "after the owning loop exits (window closed / task cancelled) a new runner " +
            "loop must be able to claim the channel — handoff, not a permanent lockout"
        )
    }

    func test_releaseWithoutClaim_isHarmless() {
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
        XCTAssertTrue(VisualScenarioCommandRunner.claimCommandChannelOwnership())
        VisualScenarioCommandRunner.releaseCommandChannelOwnership()
    }
}
