import XCTest

/// Fixture-driven proof of scripts/diagnostics/ux-canon-lint.sh — the same
/// planted-violation pattern as RealtimePathLintTests. The lint is STRICT
/// zero-tolerance (the 2026-07-02 migration burned the baseline down to zero
/// and the UX_CANON_LINT_BASELINE ratchet was deleted): any violation fails,
/// and the old baseline env var must have no effect.
final class UxCanonLintTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var script: URL {
        repoRoot.appendingPathComponent("scripts/diagnostics/ux-canon-lint.sh")
    }

    func test_uxCanonLintFailsOnTranslucentAccentFill() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Chip: View {
            let accent: Color
            var body: some View {
                Text("A").background(accent.opacity(0.2), in: Capsule())
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("translucent accent fill"), result.output)
    }

    func test_uxCanonLintAllowsOpaqueAccentFillToken() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Chip: View {
            let accent: Color
            var body: some View {
                Text("A").background(accent.opacity(StudioOpacity.accentFill), in: Capsule())
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_uxCanonLintFailsOnSystemGreyEscape() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Row: View {
            var body: some View {
                Text("Meta").foregroundStyle(.secondary)
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("system grey"), result.output)
    }

    func test_uxCanonLintFailsOnMemberSyntaxGrayEscape() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Row: View {
            var body: some View {
                Text("Meta").foregroundStyle(.gray)
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("system grey"), result.output)
    }

    func test_uxCanonLintFailsOnExplainerProse() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Panel: View {
            var body: some View {
                Text("Press play to record live history into the buffer.")
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Rule 3"), result.output)
    }

    func test_uxCanonLintIgnoresShortNonSentenceText() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Panel: View {
            var body: some View {
                Text("No inserts yet.")
                Text("STEPS / CLIP")
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_uxCanonLintHonoursReasonedAllowAnnotation() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Row: View {
            var body: some View {
                // ux-canon-allow: system settings sheet uses platform secondary text.
                Text("Meta").foregroundStyle(.secondary)
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_uxCanonLintRejectsBareAllowAnnotation() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Row: View {
            var body: some View {
                // ux-canon-allow
                Text("Meta").foregroundStyle(.secondary)
            }
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("must include a reason"), result.output)
    }

    /// The baseline ratchet was removed when the lint went strict: the env
    /// var must be ignored and a planted violation must fail regardless.
    func test_uxCanonLintIsStrictAndIgnoresRemovedBaselineEnvVar() throws {
        let fixture = try makeFixture("""
        import SwiftUI
        struct Row: View {
            var body: some View {
                Text("Meta").foregroundStyle(.secondary)
            }
        }
        """)

        let failing = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(failing.status, 0)
        XCTAssertTrue(failing.output.contains("grey-escape=1"), failing.output)
        XCTAssertTrue(failing.output.contains("zero tolerance"), failing.output)

        let withRemovedEnvVar = try runLint(
            arguments: [fixture.path],
            environment: ["UX_CANON_LINT_BASELINE": "1"]
        )
        XCTAssertNotEqual(withRemovedEnvVar.status, 0, withRemovedEnvVar.output)
        XCTAssertFalse(withRemovedEnvVar.output.contains("baseline="), withRemovedEnvVar.output)
    }

    private func makeFixture(_ source: String, fileName: String = "InjectedCanonSurface.swift") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ux-canon-lint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runLint(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

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
