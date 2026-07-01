import AVFoundation
import Foundation

/// The single audio-derived master clock (Audio Engine Hard Rule 1).
///
/// All musical-time → sample-time conversion goes through this one object plus
/// the tempo map. Nothing else in the engine derives a *sounding* time from
/// `ProcessInfo.systemUptime`, `Date`, `DispatchTime`, or a `DispatchSourceTimer`
/// deadline. A wall-clock timer may *pace* the lookahead pump (decide when we
/// wake and how far ahead we commit), but the frame an event sounds on is
/// computed here from the event's musical position and the audio render origin.
///
/// # The two pieces it composes
///
/// 1. **A musical tempo map.** Musical position is tracked as a monotonic step
///    index. `advance(toStep:bpm:)` accumulates one step's musical duration at
///    the BPM in effect for that step, so the cumulative musical seconds for any
///    prepared step is exact and *independent of the pump's wake jitter*. This
///    is the property the offline frame-accuracy gate asserts: stamping derives
///    from musical position, never from `now`.
///
/// 2. **An audio render origin.** `sampleTime(atMusicalSeconds:)` maps a musical
///    seconds value onto an absolute render frame using the render position read
///    from the engine (`MainAudioGraph.renderPosition`). The origin is captured
///    once at transport start (`captureOrigin`) so that musical second 0 maps to
///    the render frame that was current when playback began; subsequent stamps
///    are `originFrame + musicalSeconds * sampleRate`.
///
/// # Offline determinism
///
/// Under offline manual rendering the render position is
/// `engine.manualRenderingSampleTime` (deterministic), so the origin and every
/// stamp are exact integers — that is what lets the gate assert 0 frames. The
/// gate harness drives the controller without ever rendering, so the origin
/// stays at the captured (typically 0) frame and the stamp is purely
/// `musicalSeconds * sampleRate`.
///
/// # Threading
///
/// Mutated only on the tick/pump queue (`captureOrigin`, `advance`, `reset`).
/// The conversion reads (`sampleTime(atMusicalSeconds:)`, `hostSeconds`,
/// `audioTime`, `musicalSeconds`) are likewise tick-queue calls today; the first
/// of them may also UPGRADE the origin from the pre-render fallback to the
/// render-derived value (`refreshOriginIfAvailable`), but that mutation is on the
/// same tick queue, so there is no cross-thread write. `renderPositionProvider`
/// is a pure read of engine state (no alloc/locks). No render-thread work is
/// added — the engine's render `sampleTime` is merely *read*.
final class AudioMasterClock {
    /// Phase 3 look-ahead lead (seconds). Gate-1 LOCKED at 100 ms
    /// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`: "Look-ahead
    /// lead: 100 ms."). This is a pump/dispatch horizon, not a master-clock
    /// origin offset. Musical second 0 must remain anchored to transport start.
    static let lookAheadLeadSeconds: TimeInterval = 0.100

    /// Reads the live audio-render position. Returns nil until the engine has a
    /// valid render time (before first render / live-HAL warmup), in which case
    /// the clock falls back to its musical accumulator with a zero frame origin.
    private let renderPositionProvider: () -> (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)?

    /// Sample rate used for musical-seconds → frame conversion. Seeded from the
    /// first render position (or a sensible default) and refreshed whenever a
    /// render position is available.
    private(set) var sampleRate: Double

    /// Absolute render frame that musical second 0 maps to. Captured at
    /// transport start.
    private var originSampleTime: AVAudioFramePosition = 0
    /// Host-time (mach timebase) seconds that musical second 0 maps to. Captured
    /// from the render position's `hostTime` at transport start (Rule 1 origin),
    /// or `systemUptime` at start before the first render exists — both share the
    /// mach timebase, so an `AVAudioTime(hostTime:)` built from either is a valid
    /// future host time the engine correlates to its render. This is what live
    /// playback schedules against (an `AVAudioPlayerNode`'s sampleTime reference
    /// differs from the output node's, so a raw output `sampleTime` cannot be
    /// handed to `scheduleSegment/Buffer(at:)`; a host time can).
    private var originHostSeconds: TimeInterval = 0
    /// True once any origin is captured (render-derived OR the pre-render
    /// `systemUptime`/`now` fallback). While false the converters use a 0 origin.
    private var hasOrigin = false

    /// Whether the authoritative render-derived origin has been established.
    /// The AU note path uses this to decide between a sample-stamped note
    /// (`sampleTime(atMusicalSeconds:)`) and an immediate fallback: the
    /// pre-render host-time fallback is valid for host-time scheduling, but it
    /// is NOT a valid AU render-frame base. Treating that fallback as render
    /// origin stamps first-play AU notes at frame 0, which real plugins may
    /// drop. `refreshOriginIfAvailable` is called first so a just-available
    /// render position upgrades the answer.
    var hasRenderOrigin: Bool {
        refreshOriginIfAvailable()
        return originIsRenderDerived
    }
    /// True only once the origin is the render-derived host time (the authoritative
    /// Rule-1 origin). When the origin is still the pre-render fallback this stays
    /// false, so `refreshOriginIfAvailable` UPGRADES the fallback to the render
    /// host time the first time a render position becomes available — the fallback
    /// is provisional, the render origin is the real one.
    private var originIsRenderDerived = false

    /// Legacy isolated-verifier offset. Production transport start must pass zero:
    /// the look-ahead lead is realized by dispatching before the event's due time,
    /// not by moving the master-clock origin.
    private var originLeadSeconds: TimeInterval = 0

    /// Cumulative musical seconds at the most recently advanced step, and the
    /// step index it corresponds to. The tempo map is expressed incrementally:
    /// each `advance(toStep:bpm:)` adds the duration of the steps between the
    /// last advanced step and `toStep` at `bpm`.
    private(set) var lastAdvancedStep: UInt64 = 0
    private var cumulativeMusicalSecondsByStep: [UInt64: TimeInterval] = [0: 0]

    private let stepsPerBar: Int

    init(
        stepsPerBar: Int,
        defaultSampleRate: Double = 48_000,
        renderPositionProvider: @escaping () -> (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)?
    ) {
        self.stepsPerBar = max(1, stepsPerBar)
        self.sampleRate = defaultSampleRate > 0 ? defaultSampleRate : 48_000
        self.renderPositionProvider = renderPositionProvider
    }

    // MARK: - Origin

    /// Capture the render-position origin for the start of playback. Musical
    /// second 0 maps to the render frame / host time current now (Rule 1).
    /// Resets the tempo accumulator to step 0 / 0 seconds.
    ///
    /// `fallbackHostSeconds` is used as the host-time origin only when no render
    /// position is available yet (engine not yet rendering at transport start) —
    /// pass `ProcessInfo.processInfo.systemUptime`, which shares the mach
    /// timebase with `AVAudioTime` host time.
    /// `leadSeconds` is retained only for old isolated verifier coverage; live
    /// transport must use the default zero. Do not use it to implement look-ahead.
    func captureOrigin(fallbackHostSeconds: TimeInterval, leadSeconds: TimeInterval = 0) {
        reset()
        let lead = max(0, leadSeconds)
        originLeadSeconds = lead
        if let position = renderPositionProvider() {
            sampleRate = position.sampleRate
            originSampleTime = position.sampleTime + AVAudioFramePosition((lead * position.sampleRate).rounded())
            originHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime) + lead
            originIsRenderDerived = true
        } else {
            // No render position yet (engine not rendering at transport start):
            // anchor provisionally on the supplied fallback host time. This is
            // NOT the authoritative origin — `refreshOriginIfAvailable` upgrades
            // it to the render-derived host time on the first render. The
            // sample-frame origin has no valid render base yet, so it stays 0
            // until the upgrade.
            originSampleTime = 0
            originHostSeconds = fallbackHostSeconds + lead
            originIsRenderDerived = false
        }
        hasOrigin = true
    }

    /// Reset musical accumulation and origin. Called on stop / document replace.
    func reset() {
        originSampleTime = 0
        originHostSeconds = 0
        hasOrigin = false
        originIsRenderDerived = false
        originLeadSeconds = 0
        lastAdvancedStep = 0
        cumulativeMusicalSecondsByStep = [0: 0]
    }

    // MARK: - Tempo map

    /// Advance the musical accumulator to `step`, charging each newly-crossed
    /// step the musical duration at `bpm`. Idempotent for an already-recorded
    /// step. `bpm` is the tempo *in effect for the interval leaving the prior
    /// step*, matching how the executor consumes a `setBPM` command at the step
    /// it is prepared.
    @discardableResult
    func advance(toStep step: UInt64, bpm: Double) -> TimeInterval {
        if let existing = cumulativeMusicalSecondsByStep[step] {
            return existing
        }
        let perStep = Self.secondsPerStep(bpm: bpm, stepsPerBar: stepsPerBar)
        var seconds = cumulativeMusicalSecondsByStep[lastAdvancedStep] ?? 0
        var cursor = lastAdvancedStep
        while cursor < step {
            cursor &+= 1
            seconds += perStep
            cumulativeMusicalSecondsByStep[cursor] = seconds
        }
        lastAdvancedStep = max(lastAdvancedStep, step)
        // Bound the tempo map: only the current and immediately-prior steps are
        // ever read back (the prepare/dispatch split looks at most one step
        // behind). Prune older entries so long playback doesn't accumulate one
        // dictionary entry per step forever.
        if cumulativeMusicalSecondsByStep.count > 8 {
            let keepFrom = step >= 4 ? step - 4 : 0
            cumulativeMusicalSecondsByStep = cumulativeMusicalSecondsByStep.filter { $0.key >= keepFrom }
        }
        return cumulativeMusicalSecondsByStep[step] ?? seconds
    }

    /// Cumulative musical seconds for a step already recorded by `advance`.
    func musicalSeconds(forStep step: UInt64) -> TimeInterval? {
        cumulativeMusicalSecondsByStep[step]
    }

    // MARK: - Conversion (the one converter API)

    /// `sampleTime(at musicalPosition:)` — map a cumulative musical-seconds
    /// value onto an absolute render frame (output-node reference). Exposed for
    /// the offline/deterministic path and diagnostics; the live sink schedules
    /// against host time (see `audioTime(atMusicalSeconds:)`).
    func sampleTime(atMusicalSeconds musicalSeconds: TimeInterval) -> AVAudioFramePosition {
        refreshOriginIfAvailable()
        let origin = hasOrigin ? originSampleTime : 0
        return origin + AVAudioFramePosition((musicalSeconds * sampleRate).rounded())
    }

    /// Host-time (seconds) an event at `musicalSeconds` should sound: the render
    /// origin's host time plus the musical offset. Monotonic and independent of
    /// pump jitter (the origin is captured once at start; later wakes do not
    /// move it). Phase 3: this is the MIDI-out timestamp source — `MidiOut`
    /// converts the returned seconds to a mach `MIDITimeStamp`, so external gear
    /// shares the audio sinks' timeline.
    func hostSeconds(atMusicalSeconds musicalSeconds: TimeInterval) -> TimeInterval {
        refreshOriginIfAvailable()
        let origin = hasOrigin ? originHostSeconds : 0
        return origin + musicalSeconds
    }

    /// Build the future `AVAudioTime` an event is stamped with (Rule 2). The live
    /// AUDIO sink (`AVAudioPlayerNode.scheduleSegment/Buffer(at:)`) schedules
    /// against host time, which the engine correlates to its render clock; the
    /// frame is anchored to the render-derived origin and the event's musical
    /// position, so pump jitter never moves the sounding time (Rule 1).
    /// MIDI-out (Phase 3) is now ALSO on this clock: it derives its
    /// `MIDITimeStamp` from `hostSeconds(atMusicalSeconds:)` (same origin + the
    /// step's musical offset), so external gear shares this timeline. MIDI uses
    /// the host-SECONDS converter (it builds its own mach `MIDITimeStamp`), not
    /// this `AVAudioTime` builder.
    func audioTime(atMusicalSeconds musicalSeconds: TimeInterval) -> AVAudioTime {
        AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(0, hostSeconds(atMusicalSeconds: musicalSeconds))))
    }

    /// Convert a pump wake host-time into the musical position it corresponds to.
    /// This is for look-ahead WINDOW SELECTION only: it decides which already-
    /// due-soon steps the pump should prepare/hand to sinks. It never stamps an
    /// event; stamping still goes through `audioTime(atMusicalSeconds:)` /
    /// `sampleTime(atMusicalSeconds:)` using the event's due musical position.
    func musicalSeconds(atHostSeconds hostSeconds: TimeInterval) -> TimeInterval {
        refreshOriginIfAvailable()
        let origin = hasOrigin ? originHostSeconds : 0
        return max(0, hostSeconds - origin)
    }

    // MARK: - Helpers

    /// Adopt the render-derived origin as soon as a render position exists. This
    /// covers two cases:
    ///   1. No origin yet (no `captureOrigin` has run) — establish one.
    ///   2. A provisional fallback origin was captured at transport start before
    ///      the engine rendered — UPGRADE it to the authoritative render host
    ///      time on the first render. (Before this fix `hasOrigin` was set true
    ///      even for the fallback, so the upgrade never happened and the live
    ///      stamp stayed anchored to the pre-render `systemUptime` fallback.)
    /// Once the origin is render-derived it is stable for the rest of transport.
    private func refreshOriginIfAvailable() {
        guard let position = renderPositionProvider() else { return }
        sampleRate = position.sampleRate
        guard !originIsRenderDerived else { return }
        // Upgrade preserves any legacy isolated-verifier offset, but production
        // transport start captures with zero offset so musical second 0 stays at
        // the real render/fallback origin.
        originSampleTime = position.sampleTime + AVAudioFramePosition((originLeadSeconds * position.sampleRate).rounded())
        originHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime) + originLeadSeconds
        hasOrigin = true
        originIsRenderDerived = true
    }

    static func secondsPerStep(bpm: Double, stepsPerBar: Int) -> TimeInterval {
        (60.0 / max(1, bpm)) * (4.0 / Double(max(1, stepsPerBar)))
    }

    /// The captured origin correlation: the single (frame, host-seconds) pair
    /// that anchors BOTH conversions. `originSampleTime` and `originHostSeconds`
    /// are captured TOGETHER from the SAME render position in `captureOrigin`
    /// (Rule 1), so they describe one instant in two units. `sampleTime(
    /// atMusicalSeconds:)` adds the musical offset in FRAMES to `sampleTime`;
    /// `audioTime(atMusicalSeconds:)` adds it in SECONDS to `hostSeconds`. The
    /// host→frame map `originSampleTime + (H - originHostSeconds) * sampleRate`
    /// is therefore the real correlation the engine relies on to land a
    /// host-time-stamped slice and a frame-stamped AU note on the same frame.
    ///
    /// Exposed for the offline zero-flam gate (DEFECT 3 rework): the gate
    /// converts a slice's PRODUCTION host-time stamp back to a frame through this
    /// correlation and asserts it equals the AU's `sampleTime` stamp — exercising
    /// `audioTime` (production path) + the origin correlation + `sampleTime`, not
    /// `sampleTime == sampleTime` (the prior tautology).
    struct CapturedOriginCorrelation: Equatable {
        let sampleTime: AVAudioFramePosition
        let hostSeconds: TimeInterval
        let sampleRate: Double
        let hasOrigin: Bool
        let isRenderDerived: Bool

        /// Map an absolute host-time (seconds) onto a render frame through this
        /// captured correlation — the real host→frame mapping the engine relies
        /// on (a host-stamped slice and a frame-stamped AU note land here).
        func frame(forHostSeconds host: TimeInterval) -> AVAudioFramePosition {
            sampleTime + AVAudioFramePosition(((host - hostSeconds) * sampleRate).rounded())
        }
    }

    /// The captured origin correlation (see `CapturedOriginCorrelation`). Calls
    /// `refreshOriginIfAvailable` first so a just-available render position is
    /// reflected, matching the live converters.
    func capturedOriginCorrelation() -> CapturedOriginCorrelation {
        refreshOriginIfAvailable()
        return CapturedOriginCorrelation(
            sampleTime: hasOrigin ? originSampleTime : 0,
            hostSeconds: hasOrigin ? originHostSeconds : 0,
            sampleRate: sampleRate,
            hasOrigin: hasOrigin,
            isRenderDerived: originIsRenderDerived
        )
    }
}
