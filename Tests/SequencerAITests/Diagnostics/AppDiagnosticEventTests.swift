import XCTest
@testable import SequencerAI

final class AppDiagnosticEventTests: XCTestCase {
    func test_launch_event_carries_build_identity_and_defaults_context_to_private() throws {
        let identity = BuildIdentity(gitCommit: "abcdef12", gitBranch: "feature", gitDirty: "clean")
        let event = try AppDiagnosticEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 0),
            severity: .warning,
            subsystem: .app,
            category: .lifecycle,
            eventCode: "app.test",
            messageTemplate: "Test event",
            contextFields: [
                "publicField": "ok",
                "privateField": "secret",
            ],
            privacyLabels: [
                "publicField": .safe,
            ],
            buildIdentity: identity,
            runtimeIdentity: RuntimeIdentity(processID: 7, operatingSystemVersion: "14.0.0", sessionID: "session")
        )

        XCTAssertEqual(event.buildIdentity, identity)
        XCTAssertEqual(event.privacyLabels["publicField"], .safe)
        XCTAssertEqual(event.privacyLabels["privateField"], .private)
    }

    func test_requires_event_code() {
        XCTAssertThrowsError(
            try AppDiagnosticEvent(
                severity: .error,
                subsystem: .app,
                category: .lifecycle,
                eventCode: " ",
                messageTemplate: "Missing code",
                buildIdentity: BuildIdentity()
            )
        ) { error in
            XCTAssertEqual(error as? AppDiagnosticEventError, .missingEventCode)
        }
    }

    func test_lifecycle_and_bootstrap_failure_events_use_typed_safe_context_without_raw_error_details() throws {
        let identity = BuildIdentity(gitCommit: "abcdef12", gitBranch: "feature", gitDirty: "clean")
        let runtime = RuntimeIdentity(processID: 7, operatingSystemVersion: "14.0.0", sessionID: "session")

        let lifecycle = try AppDiagnosticEvent.appLifecycle(
            phase: "willTerminate",
            eventCode: "app.lifecycle.willTerminate",
            buildIdentity: identity,
            runtimeIdentity: runtime
        )
        let bootstrap = try AppDiagnosticEvent.appBootstrapFailure(
            component: "sampleLibrary",
            errorType: "SampleInstallError",
            buildIdentity: identity,
            runtimeIdentity: runtime
        )

        XCTAssertEqual(lifecycle.subsystem, .app)
        XCTAssertEqual(lifecycle.category, .lifecycle)
        XCTAssertEqual(lifecycle.contextFields["phase"], "willTerminate")
        XCTAssertEqual(lifecycle.privacyLabels["phase"], .safe)
        XCTAssertEqual(bootstrap.severity, .error)
        XCTAssertEqual(bootstrap.subsystem, .app)
        XCTAssertEqual(bootstrap.category, .bootstrap)
        XCTAssertEqual(bootstrap.eventCode, "app.bootstrap.sampleLibrary.failed")
        XCTAssertEqual(bootstrap.contextFields["component"], "sampleLibrary")
        XCTAssertEqual(bootstrap.contextFields["errorType"], "SampleInstallError")
        XCTAssertFalse(bootstrap.contextFields.values.joined().contains("/Users/"))
    }
}
