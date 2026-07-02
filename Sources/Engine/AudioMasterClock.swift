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
///    the render frame that was current when playback began plus the fixed
///    `startupAnchorLeadSeconds` (live transport; harnesses may pass zero), so
///    even step 0's stamp is a schedulable FUTURE frame; subsequent stamps are
///    `originFrame + musicalSeconds * sampleRate`.
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

    /// Startup anchor lead (seconds) — G2 gate amendment, OWNER-APPROVED
    /// 2026-07-02 (locked thresholds: anchor = 50 ms, rail cap = 60 ms).
    ///
    /// At LIVE transport start the transport grid (musical second 0) is
    /// anchored this far AFTER the render position captured at start — BOTH the
    /// sample-frame origin and the host-seconds origin advance together, so
    /// every converter view of the origin stays one correlation.
    ///
    /// Why (2026-07-02 rig physics): step 0's due time IS the origin, so with a
    /// zero anchor its stamp is knife-edge — inside the engine's
    /// schedule-visibility horizon (~2 render quanta ≈ 23 ms @ 512/44.1 kHz)
    /// plus the ~20 ms of cold first-tick dispatch work — and the first hit
    /// landed "as soon as possible" (+41 ms ± 1 quantum via the old 30 ms
    /// stamp-lift floor), non-deterministically. With a 50 ms anchor the step-0
    /// stamp is born 50 ms ahead of the render position (visibility ~23 ms +
    /// cold dispatch ~20 ms < 50 ms), so it is schedulable sample-accurately
    /// and lands ON the grid like every other step. Verified dead ends before
    /// this mechanism: a larger stamp-lift floor (45 ms → landing +55.8 ms) and
    /// pre-starting player nodes (no change).
    ///
    /// This is NOT the legacy `captureOrigin(leadSeconds:)` parameter (kept
    /// only for old isolated-verifier coverage; production passes zero there)
    /// and it must NEVER be `lookAheadLeadSeconds` (0.100): the look-ahead lead
    /// is a pump/dispatch horizon and paying it as an origin shift is the
    /// rejected round-1 first-play-latency defect. The amended first-play rails
    /// (`LookAheadEarlyDispatchTests` / `LookAheadStartCallSiteGuardTests`) pin
    /// this constant ≤ 0.060 (the owner-locked cap) and
    /// `lookAheadLeadSeconds > 0.060`, so the lead can never masquerade as the
    /// anchor.
    static let startupAnchorLeadSeconds: TimeInterval = 0.050

    /// Clock-domain skew slack added to the pump's dispatch horizon (NOT to any
    /// sounding stamp). The pump's wake times come from `systemUptime`
    /// (TickClock / DispatchSource deadlines) while musical time is anchored to
    /// the render-derived origin host time; the two share the mach timebase but
    /// the origin lands a render cycle or so away from the tick-0 wake. The
    /// 2026-07-02 capture-rig run measured ~11-14 ms of skew — with a 1 µs
    /// horizon epsilon every steady-state wake missed the next step by that
    /// margin, dispatched it a wake later (~14 ms past due), and every trigger
    /// clamped to immediate (one-render-quantum flams between coincident
    /// voices). The slack only lets the pump hand events to sinks slightly
    /// EARLIER than the nominal lead; stamps remain the true musical due time.
    static let lookAheadClockSkewSlackSeconds: TimeInterval = 0.025

    /// LAST-RESORT scheduling floor (seconds past the CURRENT render position)
    /// for the LIVE dispatch path — the earliest stamp a sink can still honour
    /// sample-accurately. It lifts an already-past-due EVENT STAMP up to
    /// `renderPositionAtDispatch + floor` (`max(due, floor)`); it never moves
    /// the master-clock origin and it is NOT the primary first-hit mechanism.
    ///
    /// Since the G2-approved `startupAnchorLeadSeconds` (50 ms) anchor, step
    /// 0's due stamp is born 50 ms ahead of the start render position, so on a
    /// NORMAL start this floor must NOT fire — firing would lift step 0 a
    /// couple of ms off the grid. The floor fires only when the cold dispatch
    /// delay (render-position advance between origin capture and dispatch)
    /// exceeds `startupAnchorLeadSeconds - floor`.
    ///
    /// Value tradeoff (2026-07-02 rig measurements): schedule visibility is
    /// ~2 render quanta (23.2 ms @ 512/44.1 kHz, 21.3 ms @ 48 kHz) and the
    /// measured cold first-tick dispatch delay is ~20 ms (1–2 quanta, i.e. up
    /// to ~23 ms observed). At the previous 30 ms the rescue threshold was
    /// "delay > 20 ms" — INSIDE the measured normal range, so a routine slow
    /// cold start would trip the floor and lift step 0 off-grid by up to
    /// ~3 ms. At 25 ms the threshold is "delay > 25 ms", clearing the measured
    /// normal range (max ~23 ms) while a rescued stamp still sits at/just past
    /// the schedule-visibility horizon (25 ms ≥ 23.2 ms) — a genuine pathology
    /// is rescued slightly late but sounding, instead of clamped to immediate.
    /// That is the accepted tradeoff: deterministic on-grid normal starts,
    /// rare best-effort (possibly ~a-quantum-late) rescues.
    static let liveDispatchSchedulingFloorSeconds: TimeInterval = 0.025

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

    /// The startup anchor lead captured with the origin (see
    /// `startupAnchorLeadSeconds`). Stored so the fallback→render-derived
    /// upgrade (`refreshOriginIfAvailable`) applies the SAME anchor the
    /// transport start requested — production can never run unanchored just
    /// because the engine had not rendered at `captureOrigin` time. Stays 0
    /// when no `captureOrigin` ran at all (the offline frame-accuracy harness
    /// establishes its origin purely through `refreshOriginIfAvailable`), so
    /// the deterministic 0-frame gate's stamps remain exactly
    /// `musicalSeconds * sampleRate`.
    private var originStartupAnchorLeadSeconds: TimeInterval = 0

    /// Highest render `sampleTime` observed on the CURRENT output render
    /// timeline. Used to detect a render-timeline RESET: a live-engine
    /// stop()/start() (e.g. `installMasterChains` rebuilding the master chain
    /// for a scene-FX insert while the transport runs, or a device switch)
    /// restarts the output node's sample counter near 0 (measured 2026-07-02:
    /// pre-stop frame 48128 → post-restart frame 24576 after +0.55 s of wall
    /// time). Host time and the AU's own render counter CONTINUE across the
    /// restart, so only the FRAME view of the origin goes stale — see
    /// `rebaseFrameOriginIfRenderTimelineReset`.
    private var maxObservedRenderSampleTime: AVAudioFramePosition?

    /// Regression slack for the timeline-reset detector, in seconds of render
    /// frames. Must be far above per-quantum jitter (~23 ms) and far below any
    /// real reset gap (the whole engine-session duration). A STALE frozen
    /// render pair (read in the stopped window) never regresses — the counter
    /// is frozen, not rewound — so this only fires on a genuine new timeline.
    static let renderTimelineResetToleranceSeconds: TimeInterval = 0.5

    /// Cumulative musical seconds at the most recently advanced step, and the
    /// step index it corresponds to. The tempo map is expressed incrementally:
    /// each `advance(toStep:bpm:)` adds the duration of the steps between the
    /// last advanced step and `toStep` at `bpm`.
    private(set) var lastAdvancedStep: UInt64 = 0
    private var cumulativeMusicalSecondsByStep: [UInt64: TimeInterval] = [0: 0]

    /// Swing currently applied to the in-flight 2-step pair. A new swing value
    /// passed to `advance` is LATCHED only when the crossing enters an odd
    /// (off-beat) step — the start of a swung pair — so both halves of every
    /// pair are charged with the same offset and the pair-sum invariant
    /// (`2 * perStep`) holds across mid-stream `setSwing` changes, whatever
    /// step parity the command happens to drain at.
    private var latchedSwing: Double = 0

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
    /// `startupAnchorLeadSeconds` is the G2-approved transport-start anchor (see
    /// the static constant): live transport start passes
    /// `AudioMasterClock.startupAnchorLeadSeconds` so musical second 0 lands the
    /// anchor lead AFTER the captured render position (frame and host origins
    /// advance together); harnesses that need an unanchored origin pass the
    /// default zero. It must never carry `lookAheadLeadSeconds`.
    func captureOrigin(
        fallbackHostSeconds: TimeInterval,
        leadSeconds: TimeInterval = 0,
        startupAnchorLeadSeconds: TimeInterval = 0
    ) {
        reset()
        let lead = max(0, leadSeconds)
        let anchor = max(0, startupAnchorLeadSeconds)
        originLeadSeconds = lead
        originStartupAnchorLeadSeconds = anchor
        let offset = lead + anchor
        if let position = renderPositionProvider() {
            sampleRate = position.sampleRate
            originSampleTime = position.sampleTime + AVAudioFramePosition((offset * position.sampleRate).rounded())
            originHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime) + offset
            originIsRenderDerived = true
            maxObservedRenderSampleTime = position.sampleTime
        } else {
            // No render position yet (engine not rendering at transport start):
            // anchor provisionally on the supplied fallback host time. This is
            // NOT the authoritative origin — `refreshOriginIfAvailable` upgrades
            // it to the render-derived host time on the first render (carrying
            // the same anchor/lead). The sample-frame origin has no valid render
            // base yet, so it stays 0 until the upgrade.
            originSampleTime = 0
            originHostSeconds = fallbackHostSeconds + offset
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
        originStartupAnchorLeadSeconds = 0
        maxObservedRenderSampleTime = nil
        lastAdvancedStep = 0
        cumulativeMusicalSecondsByStep = [0: 0]
        latchedSwing = 0
    }

    // MARK: - Tempo map

    /// Maximum swing displacement as a fraction of one step: at `swing == 1`
    /// every off-beat (odd-index) step is delayed by 1/3 of a step, i.e. each
    /// even/odd pair splits 4/3 : 2/3 — the classic 2:1 "triplet" feel.
    /// Product decision recorded 2026-07-02 (transport-swing): linear 0…1 UI
    /// range mapped onto this cap, not the MPC-style 50–75% convention.
    static let swingMaxStepFraction: Double = 1.0 / 3.0

    /// Advance the musical accumulator to `step`, charging each newly-crossed
    /// step the musical duration at `bpm`. Idempotent for an already-recorded
    /// step. `bpm` is the tempo *in effect for the interval leaving the prior
    /// step*, matching how the executor consumes a `setBPM` command at the step
    /// it is prepared. `swing` (0…1, drained via `setSwing`) delays every
    /// off-beat (odd-index) step: the interval ARRIVING at an odd step is
    /// lengthened by `swing * perStep * swingMaxStepFraction` and the interval
    /// arriving at the following even (down-beat) step is shortened by the
    /// same amount, so at constant tempo every 2-step pair sums to exactly
    /// `2 * perStep` — down-beats and bar boundaries never drift, and
    /// `swing == 0` is byte-identical to the unswung accumulator.
    ///
    /// A mid-stream swing CHANGE is latched at the next odd (off-beat) arrival
    /// — the start of the next swung pair — never mid-pair: if the drained
    /// value were applied to an interval arriving at an even step, that pair
    /// would mix an old-swing delay with a new-swing shortening and every
    /// subsequent down-beat would be permanently offset by
    /// `(old − new) * perStep * swingMaxStepFraction` relative to the
    /// pre-change grid. Latching keeps the pair-sum invariant exact across
    /// changes at any drain parity, at the cost of the change taking effect at
    /// most one step later.
    @discardableResult
    func advance(toStep step: UInt64, bpm: Double, swing: Double = 0) -> TimeInterval {
        if let existing = cumulativeMusicalSecondsByStep[step] {
            return existing
        }
        let perStep = Self.secondsPerStep(bpm: bpm, stepsPerBar: stepsPerBar)
        let clampedSwing = min(max(swing, 0), 1)
        var seconds = cumulativeMusicalSecondsByStep[lastAdvancedStep] ?? 0
        var cursor = lastAdvancedStep
        while cursor < step {
            cursor &+= 1
            // Parity is the ABSOLUTE step index (odd = off-beat 16th), so the
            // swung grid is stable across bars and across mid-stream swing
            // changes — an interval is swung by the parity of the step it
            // arrives at, never by how many steps this call happened to cross.
            if cursor % 2 == 1 {
                // Pair boundary: adopt the (possibly changed) swing for this
                // pair — the odd delay and the following even shortening are
                // charged with the SAME offset.
                latchedSwing = clampedSwing
            }
            let swingOffset = latchedSwing * perStep * Self.swingMaxStepFraction
            seconds += cursor % 2 == 1 ? perStep + swingOffset : perStep - swingOffset
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

    /// The earliest musical position (cumulative seconds) a LIVE dispatch can
    /// still hand a sink as a sample-accurately schedulable stamp: the CURRENT
    /// render position plus `liveDispatchSchedulingFloorSeconds`, expressed on
    /// the musical timeline. Returns nil while no render-derived origin exists
    /// (cold fallback — the dispatch path keeps its aligned immediate
    /// behaviour there).
    ///
    /// This is a DISPATCH-floor read, not a stamping source: the caller lifts
    /// an already-past-due event's stamp UP to this value (`max(due, floor)`),
    /// so on-time events (dispatched ~lead ahead) are never moved. Like the
    /// other converters this is a pure read of the render position plus the
    /// captured origin (Rule 1) — no wall clock is consulted.
    func liveDispatchSchedulingFloorMusicalSeconds() -> TimeInterval? {
        refreshOriginIfAvailable()
        guard originIsRenderDerived, hasOrigin,
              let position = renderPositionProvider()
        else {
            return nil
        }
        let renderHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime)
        return musicalSeconds(
            atHostSeconds: renderHostSeconds + Self.liveDispatchSchedulingFloorSeconds
        )
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
    /// Once the origin is render-derived it is stable for the rest of transport
    /// — EXCEPT that its FRAME view is rebased when the output render timeline
    /// itself resets (see `rebaseFrameOriginIfRenderTimelineReset`).
    private func refreshOriginIfAvailable() {
        guard let position = renderPositionProvider() else { return }
        sampleRate = position.sampleRate
        guard !originIsRenderDerived else {
            rebaseFrameOriginIfRenderTimelineReset(position)
            return
        }
        // Upgrade preserves the captured startup anchor (production transport
        // start anchors by `startupAnchorLeadSeconds`; the anchor must survive
        // the fallback→render upgrade or a cold start would run unanchored) and
        // any legacy isolated-verifier lead offset. When no `captureOrigin` ran
        // (offline frame-accuracy harness), both stored offsets are 0 and the
        // origin is exactly the render position — the 0-frame gate's stamps
        // stay `musicalSeconds * sampleRate`.
        let offset = originLeadSeconds + originStartupAnchorLeadSeconds
        originSampleTime = position.sampleTime + AVAudioFramePosition((offset * position.sampleRate).rounded())
        originHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime) + offset
        hasOrigin = true
        originIsRenderDerived = true
        maxObservedRenderSampleTime = position.sampleTime
    }

    /// Rebase the FRAME origin after an output render-timeline RESET, keeping
    /// the host-seconds origin (musical second 0) untouched.
    ///
    /// The scene-FX attenuation bug (docs/bugs/20260702-143000-scene-fx-
    /// attenuates-au-track-until-restart): adding/removing a master-bus scene
    /// insert while the transport runs rebuilds the master chain via
    /// `MainAudioGraph.installMasterChains`, which stop()/start()s the LIVE
    /// engine. On live HAL that restart RESETS the output node's render
    /// `sampleTime` (measured 2026-07-02), while host time and the AU node's
    /// own render counter continue. The frame origin captured at transport
    /// start then sits on the DEAD timeline, so every subsequent
    /// `sampleTime(atMusicalSeconds:)` stamp lands the whole pre-restart
    /// elapsed time in the NEW timeline's future. Sample sinks are immune
    /// (they schedule against host time — `audioTime(atMusicalSeconds:)`),
    /// but the AU note path consumes these frame stamps
    /// (`scheduledAUNoteSampleTime` → `AudioInstrumentHost.play`), so AU
    /// notes stop landing (heard as the AU track dropping way down / notes
    /// chopped to a buffer, drums unchanged), stay broken across the FX
    /// removal (another restart, same dead origin), and heal only on
    /// transport Stop→Play (`captureOrigin` re-anchors). This rebase is the
    /// missing restorer: it re-derives the frame origin ON THE NEW TIMELINE
    /// from the still-valid host-seconds origin through the fresh
    /// (sampleTime, hostTime) correlation pair — the same correlation
    /// `CapturedOriginCorrelation.frame(forHostSeconds:)` documents. Musical
    /// time never jumps: the host anchor is unchanged (Rule 1 — both values
    /// still derive from render positions, never a free-running wall clock).
    ///
    /// Detection is a REGRESSION of the render `sampleTime` against the
    /// highest frame observed on the current timeline (beyond
    /// `renderTimelineResetToleranceSeconds`). A frozen stale pair read in
    /// the stopped window never regresses (the counter freezes, it does not
    /// rewind), and offline manual rendering's `manualRenderingSampleTime`
    /// is continuous across stop()/start() (measured), so the deterministic
    /// 0-frame gate can never trigger a rebase.
    private func rebaseFrameOriginIfRenderTimelineReset(
        _ position: (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)
    ) {
        guard let maxObserved = maxObservedRenderSampleTime else {
            maxObservedRenderSampleTime = position.sampleTime
            return
        }
        let toleranceFrames = AVAudioFramePosition(
            (Self.renderTimelineResetToleranceSeconds * position.sampleRate).rounded()
        )
        guard position.sampleTime + toleranceFrames < maxObserved else {
            maxObservedRenderSampleTime = max(maxObserved, position.sampleTime)
            return
        }

        let positionHostSeconds = AVAudioTime.seconds(forHostTime: position.hostTime)
        let staleOriginSampleTime = originSampleTime
        originSampleTime = position.sampleTime
            - AVAudioFramePosition(((positionHostSeconds - originHostSeconds) * position.sampleRate).rounded())
        maxObservedRenderSampleTime = position.sampleTime
        DevActivity.trace(
            DevActivity.audioGraph,
            "master-clock frame origin REBASED after render-timeline reset: " +
            "renderFrame=\(position.sampleTime) maxObserved=\(maxObserved) " +
            "staleOrigin=\(staleOriginSampleTime) rebasedOrigin=\(originSampleTime)"
        )
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
