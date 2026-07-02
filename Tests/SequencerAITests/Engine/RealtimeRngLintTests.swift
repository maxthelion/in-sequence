import XCTest

/// Self-test for `scripts/diagnostics/realtime-rng-lint.sh` — the MISSING
/// Phase-2 gate the spec named ("realtime-path-lint shows no RNG/alloc on the
/// tick path", `docs/plans/2026-06-30-precompute-lookahead-recording.md:101`)
/// but that the existing `realtime-path-lint.sh` never implemented.
///
/// This is a WORK-PRODUCT test (not a frozen rail): it proves the new lint
/// mechanism is load-bearing — it FIRES on a live per-tick
/// `SystemRandomNumberGenerator()` construction (the live-generation signature
/// Phase 2 must remove from the tick path), respects the `realtime-allow-`
/// opt-out grammar, and is scoped to the tick-path files.
///
/// NOTE: a `test_lint_passes_on_current_repo` is deliberately NOT included,
/// because it would (correctly) FAIL today: `EngineController.prepareTick`
/// still constructs a fresh RNG per (track, tick) and calls `resolvedStepNotes`
/// live — Phase 2's off-tick precompute was never wired into the tick path
/// (`BarPrecomputeEvaluator.precompute` has zero callers in `Sources/`). That
/// open defect is the BLOCKER this gate exposes; closing it (wiring the tick
/// path to consume a `PrecomputedBar`, with invalidation for the live
/// fill/pattern-slot/quantised overrides `prepareTick` threads) is the Phase-2
/// builder deliverable, verified against the frozen equivalence rail.
final class RealtimeRngLintTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var script: URL {
        repoRoot.appendingPathComponent("scripts/diagnostics/realtime-rng-lint.sh")
    }

    func test_failsOnLiveRNGConstructionOnTickPath() throws {
        let fixture = try makeFixture("""
        import Foundation
        func prepareTick() {
            var rng = SystemRandomNumberGenerator()
            _ = rng.next()
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Phase 2 violated"), result.output)
        XCTAssertTrue(result.output.contains("SystemRandomNumberGenerator"), result.output)
    }

    func test_passesWhenTickPathHasNoLiveRNG() throws {
        // The Phase-2 end state: the tick path consumes a precomputed bar with a
        // pure dictionary read — no RNG construction at all.
        let fixture = try makeFixture("""
        import Foundation
        func prepareTick(precomputed: [Int: [String: [Int]]], step: Int) -> [String: [Int]] {
            precomputed[step] ?? [:]
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_allowsAnnotatedOffTickRNGSeam() throws {
        let fixture = try makeFixture("""
        import Foundation
        func precomputeBarOffThread() {
            // realtime-allow-off-tick-precompute: bar generation runs on the background compile, not the tick. Test: PrecomputeBarEquivalenceTests.
            var rng = SystemRandomNumberGenerator()
            _ = rng.next()
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_rejectsUnreasonedAllowAnnotation() throws {
        let fixture = try makeFixture("""
        import Foundation
        func prepareTick() {
            // realtime-allow-off-tick-precompute
            var rng = SystemRandomNumberGenerator()
            _ = rng.next()
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("allow annotation"), result.output)
    }

    func test_ignoresRNGOutsideTickPathFiles() throws {
        // The lint is scoped to the tick/prepare/scheduling files; a system RNG
        // in some unrelated file is not the tick path this gate guards.
        let fixture = try makeFixture("""
        import Foundation
        func someUiHelper() {
            var rng = SystemRandomNumberGenerator()
            _ = rng.next()
        }
        """, fileName: "SomeUnrelatedFile.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    private func makeFixture(_ source: String, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("realtime-rng-lint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runLint(arguments: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }
}
