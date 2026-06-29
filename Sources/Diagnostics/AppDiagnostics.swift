import Foundation

/// App-level diagnostic event emission.
///
/// Observability harvest from the parked `roadmap-21-observability-log-issues`
/// branch — the EVENTS + EVIDENCE half only. The branch's issue-candidate /
/// ledger / review-writer pipeline (the "second coordination system" the owner
/// parked) was deliberately left behind; this facade emits structured
/// launch / lifecycle / bootstrap-failure events to a release-safe NDJSON
/// channel via `DiagnosticEventWriter`, and nothing else.
final class AppDiagnostics {
    static var shared = AppDiagnostics.disabled(buildIdentity: .current)

    private let writer: (any DiagnosticEventWriting)?
    private let buildIdentityProvider: () -> BuildIdentity
    private let runtimeIdentityProvider: () -> RuntimeIdentity
    private let mirrorLog: (String) -> Void

    init(
        writer: (any DiagnosticEventWriting)?,
        buildIdentityProvider: @escaping () -> BuildIdentity,
        runtimeIdentityProvider: @escaping () -> RuntimeIdentity = { .current() },
        mirrorLog: @escaping (String) -> Void = { NSLog("[AppDiagnostics] \($0)") }
    ) {
        self.writer = writer
        self.buildIdentityProvider = buildIdentityProvider
        self.runtimeIdentityProvider = runtimeIdentityProvider
        self.mirrorLog = mirrorLog
    }

    /// Point the shared instance at a real NDJSON event channel rooted at
    /// `storageRoot`. Called once at launch.
    static func configure(storageRoot: URL, buildIdentity: BuildIdentity = .current) {
        let paths = DiagnosticStoragePaths(root: storageRoot)
        shared = AppDiagnostics(
            writer: DiagnosticEventWriter(paths: paths),
            buildIdentityProvider: { buildIdentity }
        )
    }

    /// A no-op instance (no writer) — the default before `configure` runs and
    /// the shape used by tests that don't want a file channel.
    static func disabled(buildIdentity: BuildIdentity) -> AppDiagnostics {
        AppDiagnostics(
            writer: nil,
            buildIdentityProvider: { buildIdentity },
            mirrorLog: { _ in }
        )
    }

    @discardableResult
    func emitLaunchEvent() throws -> AppDiagnosticEvent {
        let event = try AppDiagnosticEvent.launch(
            buildIdentity: buildIdentityProvider(),
            runtimeIdentity: runtimeIdentityProvider()
        )
        try emit(event)
        return event
    }

    func emit(_ event: AppDiagnosticEvent) throws {
        try writer?.write(event)
        mirrorLog("\(event.severity.rawValue) \(event.eventCode) \(event.messageTemplate)")
    }

    @discardableResult
    func emitLifecycleEvent(
        phase: String,
        eventCode: String,
        severity: DiagnosticSeverity = .info
    ) throws -> AppDiagnosticEvent {
        let event = try AppDiagnosticEvent.appLifecycle(
            phase: phase,
            eventCode: eventCode,
            severity: severity,
            buildIdentity: buildIdentityProvider(),
            runtimeIdentity: runtimeIdentityProvider()
        )
        try emit(event)
        return event
    }

    @discardableResult
    func emitBootstrapFailure(
        component: String,
        error: any Error
    ) throws -> AppDiagnosticEvent {
        let event = try AppDiagnosticEvent.appBootstrapFailure(
            component: component,
            errorType: String(describing: type(of: error)),
            buildIdentity: buildIdentityProvider(),
            runtimeIdentity: runtimeIdentityProvider()
        )
        try emit(event)
        return event
    }
}
