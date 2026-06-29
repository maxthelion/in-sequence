import Foundation

enum DiagnosticSeverity: String, Codable, CaseIterable, Equatable {
    case debug
    case info
    case warning
    case error
    case critical
}

enum DiagnosticSubsystem: String, Codable, CaseIterable, Equatable {
    case app
    case documentSession
    case engine
    case audio
    case midi
    case ui
    case persistence
    case pluginAU
    case automation
    case collectorHealth
}

enum DiagnosticCategory: String, Codable, CaseIterable, Equatable {
    case lifecycle
    case bootstrap
    case document
    case engine
    case audio
    case midi
    case ui
    case persistence
    case pluginAU
    case automation
    case collectorHealth
    case general
}

enum DiagnosticPrivacyClass: String, Codable, Equatable {
    case `private`
    case safe
    case redacted
    case needsReview
    case blocked
}

enum DiagnosticSourceKind: String, Codable, Equatable {
    case appRuntime
    case compatibilityLog
    case collectorHealth
}

struct RuntimeIdentity: Codable, Equatable {
    var processID: Int32
    var operatingSystemVersion: String
    var sessionID: String

    static func current(sessionID: String = UUID().uuidString) -> RuntimeIdentity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return RuntimeIdentity(
            processID: ProcessInfo.processInfo.processIdentifier,
            operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            sessionID: sessionID
        )
    }
}

struct AppDiagnosticEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    var severity: DiagnosticSeverity
    var subsystem: DiagnosticSubsystem
    var category: DiagnosticCategory
    var eventCode: String
    var messageTemplate: String
    var contextFields: [String: String]
    var privacyLabels: [String: DiagnosticPrivacyClass]
    var stackSignature: String?
    var buildIdentity: BuildIdentity
    var runtimeIdentity: RuntimeIdentity
    var sourceKind: DiagnosticSourceKind

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        severity: DiagnosticSeverity,
        subsystem: DiagnosticSubsystem,
        category: DiagnosticCategory,
        eventCode: String,
        messageTemplate: String,
        contextFields: [String: String] = [:],
        privacyLabels: [String: DiagnosticPrivacyClass] = [:],
        stackSignature: String? = nil,
        buildIdentity: BuildIdentity,
        runtimeIdentity: RuntimeIdentity = .current(),
        sourceKind: DiagnosticSourceKind = .appRuntime
    ) throws {
        let normalizedEventCode = eventCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEventCode.isEmpty else {
            throw AppDiagnosticEventError.missingEventCode
        }

        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.subsystem = subsystem
        self.category = category
        self.eventCode = normalizedEventCode
        self.messageTemplate = messageTemplate
        self.contextFields = contextFields
        self.privacyLabels = Self.privacyLabels(for: contextFields, explicitLabels: privacyLabels)
        self.stackSignature = stackSignature
        self.buildIdentity = buildIdentity
        self.runtimeIdentity = runtimeIdentity
        self.sourceKind = sourceKind
    }

    static func launch(
        buildIdentity: BuildIdentity,
        id: UUID = UUID(),
        timestamp: Date = Date(),
        runtimeIdentity: RuntimeIdentity = .current()
    ) throws -> AppDiagnosticEvent {
        try AppDiagnosticEvent(
            id: id,
            timestamp: timestamp,
            severity: .info,
            subsystem: .app,
            category: .lifecycle,
            eventCode: "app.launch",
            messageTemplate: "Application launch",
            contextFields: [
                "phase": "willFinishLaunching",
            ],
            privacyLabels: [
                "phase": .safe,
            ],
            buildIdentity: buildIdentity,
            runtimeIdentity: runtimeIdentity,
            sourceKind: .appRuntime
        )
    }

    static func appLifecycle(
        phase: String,
        eventCode: String,
        severity: DiagnosticSeverity = .info,
        buildIdentity: BuildIdentity,
        id: UUID = UUID(),
        timestamp: Date = Date(),
        runtimeIdentity: RuntimeIdentity = .current()
    ) throws -> AppDiagnosticEvent {
        try AppDiagnosticEvent(
            id: id,
            timestamp: timestamp,
            severity: severity,
            subsystem: .app,
            category: .lifecycle,
            eventCode: eventCode,
            messageTemplate: "Application lifecycle transition",
            contextFields: [
                "phase": phase,
            ],
            privacyLabels: [
                "phase": .safe,
            ],
            buildIdentity: buildIdentity,
            runtimeIdentity: runtimeIdentity,
            sourceKind: .appRuntime
        )
    }

    static func appBootstrapFailure(
        component: String,
        errorType: String,
        buildIdentity: BuildIdentity,
        id: UUID = UUID(),
        timestamp: Date = Date(),
        runtimeIdentity: RuntimeIdentity = .current()
    ) throws -> AppDiagnosticEvent {
        try AppDiagnosticEvent(
            id: id,
            timestamp: timestamp,
            severity: .error,
            subsystem: .app,
            category: .bootstrap,
            eventCode: "app.bootstrap.\(component).failed",
            messageTemplate: "Application bootstrap component failed",
            contextFields: [
                "component": component,
                "errorType": errorType,
            ],
            privacyLabels: [
                "component": .safe,
                "errorType": .safe,
            ],
            buildIdentity: buildIdentity,
            runtimeIdentity: runtimeIdentity,
            sourceKind: .appRuntime
        )
    }

    private static func privacyLabels(
        for contextFields: [String: String],
        explicitLabels: [String: DiagnosticPrivacyClass]
    ) -> [String: DiagnosticPrivacyClass] {
        var labels = explicitLabels
        for key in contextFields.keys where labels[key] == nil {
            labels[key] = .private
        }
        return labels
    }
}

enum AppDiagnosticEventError: Error, Equatable {
    case missingEventCode
}
