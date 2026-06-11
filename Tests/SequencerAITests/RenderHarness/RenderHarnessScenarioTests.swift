import XCTest
@testable import SequencerAI

/// The combinatorial timing-correctness matrix: songs built up across the
/// scenario axes (track count/types, sources, buses, sends, FX inserts,
/// phrase structures, BPM) with scripted parameter changes, rendered
/// offline and verified for grid alignment, consistency, dropouts, and
/// clipping.
///
/// Slower than unit tests — gated out of the default lane:
///   TEST_RUNNER_SEQUENCERAI_RENDER_HARNESS=1 xcodebuild ... \
///     -only-testing:SequencerAITests/RenderHarnessScenarioTests test-without-building
final class RenderHarnessScenarioTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SEQUENCERAI_RENDER_HARNESS"] == "1" else {
            throw XCTSkip("Set SEQUENCERAI_RENDER_HARNESS=1 to run the full render-harness scenario matrix.")
        }
        libraryRoot = try RenderScenarioProjectBuilder.makeFixtureLibraryRoot()
    }

    override func tearDownWithError() throws {
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    private func runGridScenario(
        _ scenario: RenderScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> OfflineRenderHarness.Result {
        let result = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)
        let verdict = try RenderHarnessAnalysis.verifyGrid(
            result: result,
            expectedOnsetTicks: scenario.expectedOnsetTicks
        )
        print(String(
            format: "[render-harness] %@: ticks=%d onsets=%d %@ peak=%.3f rtf=%.4f overBudgetTicks=%d",
            scenario.name,
            scenario.totalTicks,
            scenario.expectedOnsetTicks.count,
            verdict.report.summary,
            result.peak,
            result.realTimeFactor,
            result.overBudgetTickCount
        ))
        XCTAssertTrue(
            verdict.isPass,
            "\(scenario.name): output must stay on beat — \(verdict.details)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            result.peak,
            RenderHarnessAnalysis.clipCeiling,
            "\(scenario.name): unintended clipping",
            file: file,
            line: line
        )
        return result
    }

    // S1 — track-count/type axis: four sample tracks, classic drum kit.
    func test_scenario_fourTrackDrumKit() throws {
        _ = try runGridScenario(RenderScenario(
            name: "four-track-drum-kit",
            bpm: 120,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Snare", kind: .sample(.snare), steps: [4, 12], level: 0.45),
                .init(name: "Hat", kind: .sample(.hat), steps: [2, 6, 10, 14], level: 0.4),
                .init(name: "Perc", kind: .sample(.perc), steps: [7, 15], level: 0.4),
            ]
        ))
    }

    // S2 — source axis: slicer track alongside sample tracks.
    func test_scenario_slicerPlusSampleTracks() throws {
        _ = try runGridScenario(RenderScenario(
            name: "slicer-plus-samples",
            bpm: 110,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Slices", kind: .slicer, steps: [2, 6, 10], level: 0.5),
                .init(name: "Hat", kind: .sample(.hat), steps: [1, 5, 9, 13], level: 0.35),
            ]
        ))
    }

    // S3 — bus axis: tracks routed to user buses, one bus with an occupied
    // FX slot, bus fader moved mid-render.
    func test_scenario_mixerBusesWithInsertAndFaderMoves() throws {
        _ = try runGridScenario(RenderScenario(
            name: "buses-insert-fader-moves",
            bpm: 124,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5, busIndex: 0),
                .init(name: "Snare", kind: .sample(.snare), steps: [4, 12], level: 0.45, busIndex: 1),
                .init(name: "Hat", kind: .sample(.hat), steps: [2, 6, 10, 14], level: 0.4),
            ],
            buses: [
                .init(name: "Drum Bus", level: 0.9, withFilterInsert: true),
                .init(name: "Snare Bus", level: 1.0),
            ],
            actions: [
                .init(tick: 20, kind: .setBusLevel(busIndex: 0, level: 0.6)),
                .init(tick: 36, kind: .setBusLevel(busIndex: 1, level: 0.75)),
                .init(tick: 44, kind: .setBusLevel(busIndex: 0, level: 0.85)),
            ]
        ))
    }

    // S4 — send axis: occupied send-bus FX slot, sends active from the
    // start, send levels moved mid-bar (nonzero -> nonzero: crossing zero
    // rewires topology, which is a stop/start in production too).
    func test_scenario_sendsOccupiedWithSendMoves() throws {
        _ = try runGridScenario(RenderScenario(
            name: "sends-occupied-send-moves",
            bpm: 128,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.35, sendA: 0.25, sendB: 0.1),
                .init(name: "Perc", kind: .sample(.perc), steps: [3, 7, 11, 15], level: 0.3, sendA: 0.15),
            ],
            sendBusAOccupied: true,
            actions: [
                .init(tick: 8, kind: .setTrackSends(trackIndex: 0, sendA: 0.35, sendB: 0.2)),
                .init(tick: 24, kind: .setTrackSends(trackIndex: 1, sendA: 0.3, sendB: 0.1)),
                .init(tick: 41, kind: .setTrackSends(trackIndex: 0, sendA: 0.15, sendB: 0.3)),
            ]
        ))
    }

    // S5 — BPM axis: tempo changes at bar boundaries; the grid the output
    // is checked against is derived from the scripted BPM curve.
    func test_scenario_bpmChangesAtBarBoundaries() throws {
        _ = try runGridScenario(RenderScenario(
            name: "bpm-bar-boundary-changes",
            bpm: 120,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Hat", kind: .sample(.hat), steps: [0, 2, 4, 6, 8, 10, 12, 14], level: 0.35),
            ],
            actions: [
                .init(tick: 16, kind: .setBPM(150)),
                .init(tick: 32, kind: .setBPM(90)),
                .init(tick: 48, kind: .setBPM(140)),
            ]
        ))
    }

    // S6 — "playing around while it plays": dense mid-bar fader/pan/send/
    // master moves; the scripted performance must render identically twice.
    func test_scenario_midBarParamRampage_rendersConsistently() throws {
        var actions: [RenderScenario.Action] = []
        for tick in stride(from: 2, to: 64, by: 4) {
            let phase = Double(tick % 16) / 16
            actions.append(.init(tick: tick, kind: .setTrackLevel(trackIndex: 0, level: 0.3 + 0.25 * phase)))
            actions.append(.init(tick: tick + 1, kind: .setTrackPan(trackIndex: 1, pan: phase - 0.5)))
            actions.append(.init(tick: tick + 2, kind: .setMasterOutputGain(0.7 + 0.2 * phase)))
        }
        let scenario = RenderScenario(
            name: "mid-bar-param-rampage",
            bpm: 120,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Snare", kind: .sample(.snare), steps: [4, 12], level: 0.4),
                .init(name: "Hat", kind: .sample(.hat), steps: [2, 6, 10, 14], level: 0.35),
            ],
            actions: actions
        )
        let first = try runGridScenario(scenario)
        let second = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)
        let maxDiff = RenderHarnessAnalysis.maxAbsDifference(first, second)
        XCTAssertLessThanOrEqual(
            maxDiff,
            RenderHarnessAnalysis.consistencyTolerance,
            "identical param-change scripts must produce identical renders (max abs diff \(maxDiff))"
        )
    }

    // S7 — phrase-structure axis: a 1-bar and a 2-bar phrase cycling.
    func test_scenario_phraseCycling() throws {
        _ = try runGridScenario(RenderScenario(
            name: "phrase-cycling-1bar-2bar",
            bpm: 120,
            bars: 6,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Snare", kind: .sample(.snare), steps: [4, 12], level: 0.45),
            ],
            phraseLengthsBars: [1, 2]
        ))
    }

    // S8 — fast tempo: 200 BPM eighth-note hats stay on the tighter grid.
    func test_scenario_fastTempo200() throws {
        _ = try runGridScenario(RenderScenario(
            name: "fast-tempo-200",
            bpm: 200,
            bars: 4,
            tracks: [
                .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5),
                .init(name: "Hat", kind: .sample(.hat), steps: [0, 2, 4, 6, 8, 10, 12, 14], level: 0.35),
            ]
        ))
    }

    // S9 — density axis: 12 mixed tracks (samples + slicer + buses + sends)
    // must stay on grid and render consistently.
    func test_scenario_denseTwelveTracks() throws {
        let voices: [RenderScenario.TrackKind] = [
            .sample(.kick), .sample(.snare), .sample(.hat), .sample(.perc), .slicer,
        ]
        let tracks = (0..<12).map { index -> RenderScenario.TrackSpec in
            RenderScenario.TrackSpec(
                name: "T\(index)",
                kind: voices[index % voices.count],
                steps: [index % 16, (index % 16 + 8) % 16],
                level: 0.22,
                pan: Double(index % 5) / 2 - 1,
                sendA: index % 3 == 0 ? 0.2 : 0,
                busIndex: index % 4 == 0 ? 0 : nil
            )
        }
        let scenario = RenderScenario(
            name: "dense-twelve-tracks",
            bpm: 132,
            bars: 4,
            tracks: tracks,
            buses: [.init(name: "Bus", level: 0.9, withFilterInsert: true)]
        )
        let first = try runGridScenario(scenario)
        let second = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)
        let maxDiff = RenderHarnessAnalysis.maxAbsDifference(first, second)
        XCTAssertLessThanOrEqual(
            maxDiff,
            RenderHarnessAnalysis.consistencyTolerance,
            "dense scenario must render identically across runs (max abs diff \(maxDiff))"
        )
    }
}
