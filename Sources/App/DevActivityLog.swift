import Foundation
import os

/// Debug-build activity trace for post-mortem debugging. Events land in the
/// unified log and survive hangs and crashes, so the path to a problem can be
/// reconstructed afterwards with:
///
///   log show --last 10m --predicate 'subsystem == "ai.sequencer.SequencerAI.activity"'
///
/// or watched live with `log stream` and the same predicate. Traces compile
/// away in release builds.
enum DevActivity {
    static let subsystem = "ai.sequencer.SequencerAI.activity"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let clock = Logger(subsystem: subsystem, category: "clock")
    static let audioGraph = Logger(subsystem: subsystem, category: "audio-graph")
    static let harness = Logger(subsystem: subsystem, category: "harness")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let library = Logger(subsystem: subsystem, category: "library")

    /// One-line activity trace. The autoclosure keeps message construction
    /// out of release builds entirely.
    static func trace(_ logger: Logger, _ message: @autoclosure () -> String) {
        #if DEBUG
        let resolved = message()
        logger.info("\(resolved, privacy: .public)")
        #endif
    }
}

/// Opt-in trace for debugging whether sample-backed tracks are actually being
/// dispatched. This is intentionally separate from DevActivity so per-step
/// playback diagnostics stay off unless a developer asks for them.
enum SampleTriggerTrace {
    private static let logger = Logger(subsystem: DevActivity.subsystem, category: "sample-trigger")

    #if DEBUG
    private static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["SEQUENCERAI_SAMPLE_TRIGGER_TRACE"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "SampleTriggerTraceEnabled")
    }()
    #endif

    static func dispatch(
        trackID: UUID,
        sampleID: UUID,
        sampleURL: URL,
        scheduledHostTime: TimeInterval,
        gain: Double
    ) {
        #if DEBUG
        guard enabled else { return }
        logger.info("sample dispatch track=\(trackID.uuidString, privacy: .public) sample=\(sampleID.uuidString, privacy: .public) file=\(sampleURL.lastPathComponent, privacy: .public) host=\(scheduledHostTime, privacy: .public) gain=\(gain, privacy: .public)")
        #endif
    }

    static func schedule(
        trackID: UUID,
        sampleURL: URL,
        scheduledHostTime: TimeInterval?,
        mode: String
    ) {
        #if DEBUG
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let scheduled = scheduledHostTime ?? -1
        let lateBy = scheduledHostTime.map { now - $0 } ?? -1
        logger.info("sample schedule track=\(trackID.uuidString, privacy: .public) file=\(sampleURL.lastPathComponent, privacy: .public) scheduled=\(scheduled, privacy: .public) now=\(now, privacy: .public) late=\(lateBy, privacy: .public) mode=\(mode, privacy: .public)")
        #endif
    }

    static func drop(trackID: UUID, sampleID: UUID, reason: String) {
        #if DEBUG
        guard enabled else { return }
        logger.info("sample drop track=\(trackID.uuidString, privacy: .public) sample=\(sampleID.uuidString, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }
}
