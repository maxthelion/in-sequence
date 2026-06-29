import XCTest
@testable import SequencerAI

final class AppDiagnosticsTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("seqai-app-diagnostics-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func test_emit_launch_event_uses_injected_build_identity_and_writer() throws {
        let writer = CapturingDiagnosticWriter()
        let identity = BuildIdentity(gitCommit: "abcdef12", gitBranch: "feature", gitDirty: "dirty")
        let diagnostics = AppDiagnostics(
            writer: writer,
            buildIdentityProvider: { identity },
            runtimeIdentityProvider: {
                RuntimeIdentity(processID: 12, operatingSystemVersion: "14.0.0", sessionID: "session")
            },
            mirrorLog: { _ in }
        )

        let event = try diagnostics.emitLaunchEvent()

        XCTAssertEqual(writer.events, [event])
        XCTAssertEqual(event.eventCode, "app.launch")
        XCTAssertEqual(event.buildIdentity, identity)
    }

    func test_emit_lifecycle_and_bootstrap_failure_events_use_injected_identity_and_writer() throws {
        let writer = CapturingDiagnosticWriter()
        let identity = BuildIdentity(gitCommit: "abcdef12", gitBranch: "feature", gitDirty: "clean")
        let diagnostics = AppDiagnostics(
            writer: writer,
            buildIdentityProvider: { identity },
            runtimeIdentityProvider: {
                RuntimeIdentity(processID: 12, operatingSystemVersion: "14.0.0", sessionID: "session")
            },
            mirrorLog: { _ in }
        )

        let lifecycle = try diagnostics.emitLifecycleEvent(
            phase: "didResignActive",
            eventCode: "app.lifecycle.didResignActive"
        )
        let bootstrap = try diagnostics.emitBootstrapFailure(
            component: "appSupport",
            error: LocalBootstrapError()
        )

        XCTAssertEqual(writer.events, [lifecycle, bootstrap])
        XCTAssertEqual(lifecycle.eventCode, "app.lifecycle.didResignActive")
        XCTAssertEqual(lifecycle.buildIdentity, identity)
        XCTAssertEqual(bootstrap.eventCode, "app.bootstrap.appSupport.failed")
        XCTAssertEqual(bootstrap.contextFields["errorType"], "LocalBootstrapError")
        XCTAssertEqual(bootstrap.buildIdentity, identity)
    }

    /// Conformity guard: the diagnostics facade must stay a leaf — no document,
    /// audio, engine, or external-service dependencies (the events/evidence
    /// channel does not reach into the app's runtime).
    func test_diagnostics_pipeline_source_stays_local_without_disallowed_dependencies() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("Sources/Diagnostics/AppDiagnostics.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".seqai"))
        XCTAssertFalse(source.contains("SeqAIDocument"))
        XCTAssertFalse(source.contains("Playback"))
        XCTAssertFalse(source.contains("EngineController"))
        XCTAssertFalse(source.contains("AVAudio"))
        XCTAssertFalse(source.contains("CoreMIDI"))
        XCTAssertFalse(source.contains("GitHub"))
        XCTAssertFalse(source.contains("Linear"))
        XCTAssertFalse(source.contains("Console"))
    }
}

private final class CapturingDiagnosticWriter: DiagnosticEventWriting {
    var events: [AppDiagnosticEvent] = []

    func write(_ event: AppDiagnosticEvent) throws {
        events.append(event)
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct LocalBootstrapError: Error {}
