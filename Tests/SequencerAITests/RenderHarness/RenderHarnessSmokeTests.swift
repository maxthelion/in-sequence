import XCTest
@testable import SequencerAI

/// Fast offline render smoke scenarios that run in the default test gate.
/// The full combinatorial matrix and the degradation sweep live in
/// RenderHarnessScenarioTests / RenderHarnessDegradationTests behind
/// SEQUENCERAI_RENDER_HARNESS=1. See docs/testing/render-harness.md.
final class RenderHarnessSmokeTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = try RenderScenarioProjectBuilder.makeFixtureLibraryRoot()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_singleKickTrack_offlineRender_onsetsLandOnStepGrid() throws {
        let scenario = RenderScenario(
            name: "smoke-kick-grid",
            bpm: 120,
            bars: 2,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.8),
            ]
        )
        let result = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)

        XCTAssertGreaterThan(result.peak, 0.05, "render must contain audio")
        let verdict = try RenderHarnessAnalysis.verifyGrid(
            result: result,
            expectedOnsetTicks: scenario.expectedOnsetTicks
        )
        XCTAssertTrue(verdict.isPass, "kick onsets must align to the step grid — \(verdict.details)")
        XCTAssertLessThanOrEqual(result.peak, RenderHarnessAnalysis.clipCeiling, "scenario does not intend clipping")
    }

    func test_sameScenario_rendersIdenticallyAcrossTwoRuns() throws {
        let scenario = RenderScenario(
            name: "smoke-consistency",
            bpm: 132,
            bars: 2,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.6),
                .init(name: "Hat", kind: .sample(.hat), steps: [2, 6, 10, 14], level: 0.5),
            ]
        )
        let first = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)
        let second = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)

        XCTAssertGreaterThan(first.peak, 0.05, "render must contain audio")
        let maxDiff = RenderHarnessAnalysis.maxAbsDifference(first, second)
        XCTAssertLessThanOrEqual(
            maxDiff,
            RenderHarnessAnalysis.consistencyTolerance,
            "two renders of the same scenario must be sample-identical (max abs diff \(maxDiff))"
        )
    }

    func test_scriptedFaderAndBPMChanges_keepOnsetsOnDerivedGrid() throws {
        let scenario = RenderScenario(
            name: "smoke-param-script",
            bpm: 120,
            bars: 2,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.7),
            ],
            actions: [
                .init(tick: 6, kind: .setTrackLevel(trackIndex: 0, level: 0.45)),
                .init(tick: 10, kind: .setTrackPan(trackIndex: 0, pan: -0.4)),
                .init(tick: 16, kind: .setBPM(150)), // bar boundary
                .init(tick: 24, kind: .setMasterOutputGain(0.85)), // mid-bar
            ]
        )
        let result = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)

        let verdict = try RenderHarnessAnalysis.verifyGrid(
            result: result,
            expectedOnsetTicks: scenario.expectedOnsetTicks
        )
        XCTAssertTrue(
            verdict.isPass,
            "onsets must stay on the BPM-derived grid through scripted changes — \(verdict.details)"
        )
    }
}
