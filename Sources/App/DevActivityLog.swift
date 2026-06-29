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
    static let timingProbe = Logger(subsystem: subsystem, category: "timing-probe")

    /// One-line activity trace. The autoclosure keeps message construction
    /// out of release builds entirely.
    static func trace(_ logger: Logger, _ message: @autoclosure () -> String) {
        #if DEBUG
        let resolved = message()
        logger.info("\(resolved, privacy: .public)")
        #endif
    }
}

/// Opt-in correlation trace for diagnosing playback lag during UI activity.
/// Enable with `SEQUENCERAI_TIMING_PROBE=1` or
/// `defaults write ai.sequencer.SequencerAI TimingProbeEnabled -bool YES`.
enum SequencerTimingProbe {
    #if DEBUG
    private static let logger = Logger(subsystem: DevActivity.subsystem, category: "timing-probe")

    private static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["SEQUENCERAI_TIMING_PROBE"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "TimingProbeEnabled")
    }()
    #endif

    static var isEnabled: Bool {
        #if DEBUG
        enabled
        #else
        false
        #endif
    }

    static func activity(_ name: String, detail: String = "") {
        #if DEBUG
        guard enabled else { return }
        log("activity name=\(name)\(suffix(detail))")
        #endif
    }

    static func viewSwitch(from: String, to: String, mode: String) {
        #if DEBUG
        guard enabled else { return }
        log("view-switch from=\(from) to=\(to) mode=\(mode)")
        #endif
    }

    static func tickClock(
        tickIndex: UInt64,
        expected: TimeInterval,
        actual: TimeInterval,
        interval: TimeInterval,
        bpm: Double
    ) {
        #if DEBUG
        guard enabled else { return }
        let lateMs = latenessMs(actual: actual, scheduled: expected)
        log(
            "tick-clock tick=\(tickIndex) expected=\(format(expected)) actual=\(format(actual)) " +
            "lateMs=\(format(lateMs)) intervalMs=\(format(interval * 1_000)) bpm=\(format(bpm))"
        )
        #endif
    }

    static func processTick(tickIndex: UInt64, duration: TimeInterval, eventCount: Int) {
        #if DEBUG
        guard enabled else { return }
        log(
            "process-tick tick=\(tickIndex) durationMs=\(format(duration * 1_000)) " +
            "events=\(eventCount)"
        )
        #endif
    }

    static func eventDispatch(kind: String, trackID: UUID?, scheduled: TimeInterval, actual: TimeInterval) {
        #if DEBUG
        guard enabled else { return }
        let trackText = trackID.map { " track=\($0.uuidString)" } ?? ""
        log(
            "event-dispatch kind=\(kind)\(trackText) scheduled=\(format(scheduled)) " +
            "actual=\(format(actual)) lateMs=\(format(latenessMs(actual: actual, scheduled: scheduled)))"
        )
        #endif
    }

    static func sampleSchedule(
        trackID: UUID,
        file: String,
        scheduled: TimeInterval?,
        actual: TimeInterval,
        mode: String,
        start: Double,
        length: Double,
        gain: Double,
        startFrame: Int64,
        endFrame: Int64
    ) {
        #if DEBUG
        guard enabled else { return }
        log(
            "sample-schedule track=\(trackID.uuidString) file=\(file) scheduled=\(scheduledText(scheduled)) " +
            "actual=\(format(actual)) lateMs=\(format(optionalLatenessMs(actual: actual, scheduled: scheduled))) mode=\(mode) " +
            "start=\(format(start)) length=\(format(length)) gain=\(format(gain)) " +
            "startFrame=\(startFrame) endFrame=\(endFrame)"
        )
        #endif
    }

    static func sampleAssetCacheLookup(sampleID: UUID, trackID: UUID? = nil, result: String) {
        #if DEBUG
        guard enabled else { return }
        let trackText = trackID.map { " track=\($0.uuidString)" } ?? ""
        log("sample-cache phase=lookup sample=\(sampleID.uuidString)\(trackText) result=\(result)")
        #endif
    }

    static func sampleAssetCacheLoad(
        sampleID: UUID,
        file: String,
        duration: TimeInterval,
        frames: Int64,
        result: String
    ) {
        #if DEBUG
        guard enabled else { return }
        log(
            "sample-cache phase=load sample=\(sampleID.uuidString) file=\(file) " +
            "durationMs=\(format(duration * 1_000)) frames=\(frames) result=\(result)"
        )
        #endif
    }

    static func sampleAssetCacheEviction(sampleID: UUID, bytes: Int, reason: String) {
        #if DEBUG
        guard enabled else { return }
        log("sample-cache phase=evict sample=\(sampleID.uuidString) bytes=\(bytes) reason=\(reason)")
        #endif
    }

    static func sampleMainHopQueued(
        trackID: UUID,
        scheduled: TimeInterval?,
        enqueued: TimeInterval,
        reason: String
    ) {
        #if DEBUG
        guard enabled else { return }
        let scheduledValue = scheduled ?? -1
        log(
            "sample-main-hop phase=queued track=\(trackID.uuidString) " +
            "scheduled=\(format(scheduledValue)) enqueued=\(format(enqueued)) reason=\(reason)"
        )
        #endif
    }

    static func sampleMainHopStarted(
        trackID: UUID,
        scheduled: TimeInterval?,
        enqueued: TimeInterval,
        actual: TimeInterval,
        reason: String
    ) {
        #if DEBUG
        guard enabled else { return }
        let scheduledValue = scheduled ?? -1
        log(
            "sample-main-hop phase=started track=\(trackID.uuidString) " +
            "scheduled=\(format(scheduledValue)) enqueued=\(format(enqueued)) " +
            "actual=\(format(actual)) waitMs=\(format((actual - enqueued) * 1_000)) reason=\(reason)"
        )
        #endif
    }

    static func sampleFastPath(
        trackID: UUID,
        scheduled: TimeInterval?,
        actual: TimeInterval,
        result: String
    ) {
        #if DEBUG
        guard enabled else { return }
        let scheduledValue = scheduled ?? -1
        log(
            "sample-fast-path track=\(trackID.uuidString) scheduled=\(format(scheduledValue)) " +
            "actual=\(format(actual)) result=\(result)"
        )
        #endif
    }

    static func graphRepair(
        subsystem: String,
        trackID: UUID?,
        cause: String,
        duration: TimeInterval,
        mutationCount: Int
    ) {
        #if DEBUG
        guard enabled else { return }
        let trackText = trackID.map { " track=\($0.uuidString)" } ?? ""
        log(
            "graph-repair subsystem=\(subsystem)\(trackText) cause=\(cause) " +
            "durationMs=\(format(duration * 1_000)) mutations=\(mutationCount)"
        )
        #endif
    }

    static func sliceSchedule(
        trackID: UUID,
        file: String,
        scheduled: TimeInterval?,
        actual: TimeInterval,
        mode: String,
        startFrame: Int64,
        endFrame: Int64,
        voiceMode: String,
        reverse: Bool,
        choke: Bool
    ) {
        #if DEBUG
        guard enabled else { return }
        log(
            "slice-schedule track=\(trackID.uuidString) file=\(file) scheduled=\(scheduledText(scheduled)) " +
            "actual=\(format(actual)) lateMs=\(format(optionalLatenessMs(actual: actual, scheduled: scheduled))) mode=\(mode) " +
            "startFrame=\(startFrame) endFrame=\(endFrame) voiceMode=\(voiceMode) " +
            "reverse=\(reverse) choke=\(choke)"
        )
        #endif
    }

    static func voiceSelected(trackID: UUID, voiceMode: String, voiceIndex: Int, stoppedPriorVoice: Bool) {
        #if DEBUG
        guard enabled else { return }
        log(
            "voice-selected track=\(trackID.uuidString) voiceMode=\(voiceMode) " +
            "voiceIndex=\(voiceIndex) stoppedPriorVoice=\(stoppedPriorVoice)"
        )
        #endif
    }

    #if DEBUG
    private static func log(_ message: String) {
        logger.info("t=\(ProcessInfo.processInfo.systemUptime, privacy: .public) \(message, privacy: .public)")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func latenessMs(actual: TimeInterval, scheduled: TimeInterval) -> Double {
        max(0, (actual - scheduled) * 1_000)
    }

    private static func optionalLatenessMs(actual: TimeInterval, scheduled: TimeInterval?) -> Double {
        scheduled.map { latenessMs(actual: actual, scheduled: $0) } ?? 0
    }

    private static func scheduledText(_ scheduled: TimeInterval?) -> String {
        scheduled.map(format) ?? "unscheduled"
    }

    private static func suffix(_ detail: String) -> String {
        detail.isEmpty ? "" : " \(detail)"
    }
    #endif
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
        let scheduled = scheduledHostTime.map { String(format: "%.6f", $0) } ?? "unscheduled"
        let lateBy = scheduledHostTime.map { max(0, now - $0) } ?? 0
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

/// Opt-in trace for debugging whether AU-backed tracks are receiving and
/// scheduling MIDI note events. This is intentionally off by default because it
/// can log once per sounding step while the transport runs.
enum AUNoteTriggerTrace {
    private static let logger = Logger(subsystem: DevActivity.subsystem, category: "au-note-trigger")

    #if DEBUG
    private static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["SEQUENCERAI_AU_NOTE_TRACE"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "AUNoteTraceEnabled")
    }()
    #endif

    static func dispatch(
        kind: String,
        trackID: UUID,
        noteCount: Int,
        scheduledMusicalSeconds: TimeInterval,
        noteOnSampleTime: Int64?,
        sampleRate: Double?
    ) {
        #if DEBUG
        guard enabled else { return }
        let stamp = noteOnSampleTime.map(String.init) ?? "nil"
        let rate = sampleRate.map { String(format: "%.1f", $0) } ?? "nil"
        logger.info("au dispatch kind=\(kind, privacy: .public) track=\(trackID.uuidString, privacy: .public) notes=\(noteCount, privacy: .public) musical=\(scheduledMusicalSeconds, privacy: .public) sampleTime=\(stamp, privacy: .public) sampleRate=\(rate, privacy: .public)")
        #endif
    }

    static func schedule(
        choice: String,
        gateCount: Int,
        firstPitch: UInt8?,
        requestedSampleTime: Int64?,
        currentRenderFrame: Int64?,
        firstNoteOn: Int64?,
        firstNoteOff: Int64?
    ) {
        #if DEBUG
        guard enabled else { return }
        logger.info("au schedule choice=\(choice, privacy: .public) gates=\(gateCount, privacy: .public) firstPitch=\(format(firstPitch), privacy: .public) requested=\(format(requestedSampleTime), privacy: .public) currentRenderFrame=\(format(currentRenderFrame), privacy: .public) firstOn=\(format(firstNoteOn), privacy: .public) firstOff=\(format(firstNoteOff), privacy: .public)")
        #endif
    }

    static func drop(choice: String, reason: String, noteCount: Int) {
        #if DEBUG
        guard enabled else { return }
        logger.info("au drop choice=\(choice, privacy: .public) notes=\(noteCount, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }

    #if DEBUG
    private static func format(_ value: UInt8?) -> String {
        value.map(String.init) ?? "nil"
    }

    private static func format(_ value: Int64?) -> String {
        value.map(String.init) ?? "nil"
    }
    #endif
}
