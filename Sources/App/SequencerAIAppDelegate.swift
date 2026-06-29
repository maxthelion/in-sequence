import AppKit
import Foundation

struct BuildIdentity: Codable, Equatable {
    var version: String
    var bundleBuild: String
    var gitCommit: String
    var gitBranch: String
    var gitDirty: String
    var attributionID: String
    var attributionVersion: String

    static var current: BuildIdentity {
        BuildIdentity(bundle: .main)
    }

    init(
        version: String = "unknown",
        bundleBuild: String = "unknown",
        gitCommit: String = "unknown",
        gitBranch: String = "unknown",
        gitDirty: String = "unknown",
        attributionID: String = "unknown",
        attributionVersion: String = "unknown"
    ) {
        self.version = Self.clean(version)
        self.bundleBuild = Self.clean(bundleBuild)
        self.gitCommit = Self.clean(gitCommit)
        self.gitBranch = Self.clean(gitBranch)
        self.gitDirty = Self.clean(gitDirty)
        self.attributionID = Self.clean(attributionID)
        self.attributionVersion = Self.clean(attributionVersion)
    }

    init(bundle: Bundle) {
        self.init(
            version: Self.bundleValue("CFBundleShortVersionString", bundle: bundle),
            bundleBuild: Self.bundleValue("CFBundleVersion", bundle: bundle),
            gitCommit: Self.bundleValue("GitCommit", bundle: bundle),
            gitBranch: Self.bundleValue("GitBranch", bundle: bundle),
            gitDirty: Self.bundleValue("GitDirty", bundle: bundle),
            attributionID: Self.bundleValue("BuildAttributionID", bundle: bundle),
            attributionVersion: Self.bundleValue("BuildAttributionVersion", bundle: bundle)
        )
    }

    /// Top-bar pill text. Fields that were never stamped ("unknown") are
    /// omitted rather than printed verbatim into chrome (ux-canon rule 3);
    /// `logSummary` keeps them for diagnostics.
    var compactDisplay: String {
        let known = [gitBranch, gitCommit, gitDirty, attributionVersion]
            .filter { $0 != "unknown" }
        guard !known.isEmpty else {
            return "unknown"
        }
        return known.joined(separator: " ")
    }

    var logSummary: String {
        "version=\(version) build=\(bundleBuild) gitCommit=\(gitCommit) gitBranch=\(gitBranch) gitDirty=\(gitDirty) attributionID=\(attributionID) attributionVersion=\(attributionVersion)"
    }

    private static func bundleValue(_ key: String, bundle: Bundle) -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return "unknown"
        }
        return clean(value)
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return "unknown"
        }
        return trimmed
    }
}

@MainActor
protocol EngineLifecycleControlling: AnyObject {
    func shutdown()
}

@MainActor
final class SequencerAIAppDelegate: NSObject, NSApplicationDelegate {
    var windowHost: any AUWindowHosting = AUWindowHost.shared
    var shutdownDrainInterval: TimeInterval = 0.15
    var drainRunLoop: (TimeInterval) -> Void = { interval in
        guard interval > 0 else {
            return
        }
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private func log(_ message: String) {
        NSLog("[SequencerAIAppDelegate] \(message)")
    }

    private var buildMetadataSummary: String {
        BuildIdentity.current.logSummary
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start warming the AU component cache on a background queue.
        // This fires before SwiftUI begins constructing App/Scene/View objects, so by the
        // time AudioInstrumentHost.init evaluates AudioInstrumentChoice.defaultChoices the
        // scan is either already done (fast machines) or in-flight (slow machines; the first
        // actual read will block only until the background task finishes, not for a full
        // duplicate scan).
        log("launch \(buildMetadataSummary)")
        configureDiagnostics()
        NSLog("[U2] SequencerAIAppDelegate: beginWarmingIfNeeded")
        AudioInstrumentChoiceCache.shared.beginWarmingIfNeeded()
    }

    /// Point the diagnostic-event channel at Application Support and record a
    /// structured launch event (observability harvest — events/evidence only).
    /// Best-effort: a diagnostics failure must never disrupt launch.
    private func configureDiagnostics() {
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SequencerAI/Diagnostics", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("SequencerAI/Diagnostics", isDirectory: true)
        AppDiagnostics.configure(storageRoot: root)
        do {
            try AppDiagnostics.shared.emitLaunchEvent()
        } catch {
            log("diagnostics launch event failed: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("applicationWillTerminate start")
        SequencerDocumentSessionRegistry.flushAll()
        windowHost.closeAll()
        SequencerDocumentSessionRegistry.shutdownAll()
        drainRunLoop(shutdownDrainInterval)
        log("applicationWillTerminate complete")
    }

    func applicationDidResignActive(_ notification: Notification) {
        log("applicationDidResignActive: flushing all sessions")
        SequencerDocumentSessionRegistry.flushAll()
    }
}
