import XCTest
@testable import SequencerAI

/// Degradation profiling: scales track count and reports render cost per
/// audio second (real-time factor), per-tick processTick/render cost
/// percentiles, and over-budget tick counts — the offline equivalents of
/// "missed/late ticks" (a tick whose prep+render exceeds its musical
/// duration could not have met its deadline live).
///
/// Gated out of the default lane:
///   TEST_RUNNER_SEQUENCERAI_RENDER_HARNESS=1 xcodebuild ... \
///     -only-testing:SequencerAITests/RenderHarnessDegradationTests test-without-building
///
/// Writes docs/audits/render-harness-degradation.md (override the directory
/// with SEQUENCERAI_RENDER_HARNESS_REPORT_DIR).
final class RenderHarnessDegradationTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SEQUENCERAI_RENDER_HARNESS"] == "1" else {
            throw XCTSkip("Set SEQUENCERAI_RENDER_HARNESS=1 to run the render-harness degradation sweep.")
        }
        libraryRoot = try RenderScenarioProjectBuilder.makeFixtureLibraryRoot()
    }

    override func tearDownWithError() throws {
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    private struct SweepRow {
        var trackCount: Int
        var realTimeFactor: Double
        var processP50Ms: Double
        var processP95Ms: Double
        var processMaxMs: Double
        var renderP50Ms: Double
        var renderP95Ms: Double
        var renderMaxMs: Double
        var overBudgetTicks: Int
        var totalTicks: Int
        var peak: Float
        var onGrid: Bool
    }

    func test_degradationSweep_trackCountScaling() throws {
        let trackCounts = [1, 2, 4, 8, 16, 32]
        let voices: [RenderScenario.TrackKind] = [
            .sample(.kick), .sample(.snare), .sample(.hat), .sample(.perc),
        ]
        var rows: [SweepRow] = []

        for count in trackCounts {
            let tracks = (0..<count).map { index -> RenderScenario.TrackSpec in
                let base = index % 4
                return RenderScenario.TrackSpec(
                    name: "T\(index)",
                    kind: voices[index % voices.count],
                    steps: [base, base + 4, base + 8, base + 12],
                    level: min(0.5, 1.6 / Double(count))
                )
            }
            let scenario = RenderScenario(
                name: "degradation-\(count)-tracks",
                bpm: 120,
                bars: 2,
                tracks: tracks
            )
            let result = try OfflineRenderHarness.render(scenario: scenario, libraryRoot: libraryRoot)
            let verdict = try RenderHarnessAnalysis.verifyGrid(
                result: result,
                expectedOnsetTicks: scenario.expectedOnsetTicks
            )

            let process = result.tickStats.map { $0.processSeconds * 1_000 }.sorted()
            let render = result.tickStats.map { $0.renderSeconds * 1_000 }.sorted()
            let row = SweepRow(
                trackCount: count,
                realTimeFactor: result.realTimeFactor,
                processP50Ms: percentile(process, 0.5),
                processP95Ms: percentile(process, 0.95),
                processMaxMs: process.last ?? 0,
                renderP50Ms: percentile(render, 0.5),
                renderP95Ms: percentile(render, 0.95),
                renderMaxMs: render.last ?? 0,
                overBudgetTicks: result.overBudgetTickCount,
                totalTicks: result.tickStats.count,
                peak: result.peak,
                onGrid: verdict.isPass
            )
            rows.append(row)
            print(String(
                format: "[render-harness] degradation tracks=%d rtf=%.4f processP95=%.3fms renderP95=%.3fms overBudget=%d/%d onGrid=%@",
                row.trackCount,
                row.realTimeFactor,
                row.processP95Ms,
                row.renderP95Ms,
                row.overBudgetTicks,
                row.totalTicks,
                row.onGrid ? "yes" : "NO — \(verdict.details)"
            ))
        }

        try writeReport(rows: rows)

        // The sweep is a profile, not a hard gate — but correctness must
        // hold at every density, and the machine must keep at least 32
        // tracks faster than realtime or live playback is already at risk.
        for row in rows {
            XCTAssertTrue(row.onGrid, "\(row.trackCount)-track scenario drifted off grid")
        }
        if let densest = rows.last {
            XCTAssertLessThan(
                densest.realTimeFactor,
                1.0,
                "32-track render slower than realtime — live playback would underrun on this machine"
            )
        }
    }

    private func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded()))
        return sorted[index]
    }

    private func writeReport(rows: [SweepRow]) throws {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["SEQUENCERAI_RENDER_HARNESS_REPORT_DIR"] {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            // Tests/SequencerAITests/RenderHarness/<file> -> repo root.
            directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("docs/audits", isDirectory: true)
        }
        // The test host is sandboxed and may not be able to write into the
        // repo; fall back to the temporary directory and print the path so
        // the runner can copy the report into docs/audits/.
        var resolvedDirectory = directory
        do {
            try FileManager.default.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
            let probe = resolvedDirectory.appendingPathComponent(".render-harness-write-probe")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            resolvedDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("render-harness-reports", isDirectory: true)
            try FileManager.default.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
        }
        let url = resolvedDirectory.appendingPathComponent("render-harness-degradation.md")

        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("# Render harness degradation profile")
        lines.append("")
        lines.append("Generated by `RenderHarnessDegradationTests` on \(formatter.string(from: Date())).")
        lines.append("Offline manual-rendering sweep: 2 bars at 120 BPM, 16 steps/bar, 4 onsets per")
        lines.append("track per bar, track count scaled. `rtf` = wall-clock render time per audio")
        lines.append("second (<1 is faster than realtime). `over-budget ticks` counts ticks whose")
        lines.append("processTick + render cost exceeded the tick's musical duration (125 ms) — the")
        lines.append("offline equivalent of a missed/late tick deadline.")
        lines.append("")
        lines.append("| tracks | rtf | processTick p50/p95/max (ms) | render p50/p95/max (ms) | over-budget ticks | peak | on grid |")
        lines.append("|-------:|----:|------------------------------|--------------------------|------------------:|-----:|:-------:|")
        for row in rows {
            lines.append(String(
                format: "| %d | %.4f | %.3f / %.3f / %.3f | %.3f / %.3f / %.3f | %d / %d | %.3f | %@ |",
                row.trackCount,
                row.realTimeFactor,
                row.processP50Ms, row.processP95Ms, row.processMaxMs,
                row.renderP50Ms, row.renderP95Ms, row.renderMaxMs,
                row.overBudgetTicks, row.totalTicks,
                row.peak,
                row.onGrid ? "yes" : "NO"
            ))
        }
        lines.append("")
        if let first = rows.first, let last = rows.last, first.realTimeFactor > 0 {
            lines.append(String(
                format: "Scaling: %dx tracks cost %.1fx render time (rtf %.4f -> %.4f).",
                last.trackCount / max(1, first.trackCount),
                last.realTimeFactor / first.realTimeFactor,
                first.realTimeFactor,
                last.realTimeFactor
            ))
        }
        let knee = rows.first(where: { $0.realTimeFactor > 0.5 || $0.overBudgetTicks > 0 })
        if let knee {
            lines.append(String(
                format: "Knee: first configuration at >0.5 rtf or with over-budget ticks is %d tracks.",
                knee.trackCount
            ))
        } else {
            lines.append("Knee: none observed in this sweep — all configurations rendered well under realtime budgets.")
        }
        lines.append("")
        lines.append("Run: `TEST_RUNNER_SEQUENCERAI_RENDER_HARNESS=1 xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -derivedDataPath build-dd test-without-building -only-testing:SequencerAITests/RenderHarnessDegradationTests`")
        lines.append("")

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("[render-harness] degradation report written to \(url.path)")
    }
}
