import AVFoundation
import XCTest
@testable import SequencerAI

/// Offline frame-accuracy + no-stop/no-reconnect harness — the VERIFICATION
/// GATE for the sample-accurate timing phase
/// (`docs/plans/2026-06-24-sample-accurate-timing.md`, Phase 0 acceptance).
///
/// # What this gate asserts
///
/// Phase 0's acceptance criterion, verbatim: *"drive the engine in
/// `enableManualRenderingMode(.offline)`, schedule events at known musical
/// positions, assert each lands within 0 frames of its target sample, and that
/// the mapping stays exact across a mid-stream tempo change."*
///
/// # How it measures the scheduled frame (deterministic stamp-capture)
///
/// We do NOT detect onsets in the rendered buffer (slow, fuzzy, needs a
/// transient detector + tolerance window — see `OfflineRenderHarness`, which is
/// the audibility/cost rig, not a sample-accuracy gate). Instead we capture the
/// EXACT frame each event is stamped at, deterministically:
///
///   1. The engine's only stamping seam is
///      `EngineController.scheduledAudioTime(for: scheduledHostTime)`
///      (EngineController.swift). Every sample/slice trigger is handed the
///      `AVAudioTime` it returns. The existing
///      `scheduledAudioTimeOverrideForTesting` hook lets a test substitute the
///      seconds→`AVAudioTime` conversion.
///   2. We install an override that mirrors P0's TARGET conversion —
///      `AVAudioTime(sampleTime:atRate:)` — mapping the engine's
///      `scheduledHostTime` onto a sample clock with a known origin, and
///      RECORDS the resulting frame keyed by the scheduled seconds.
///   3. A `CapturingSampleSink` records the `AVAudioTime` actually handed to
///      `play(...at:)` / `playSlice(...at:)`, so the captured frame is the real
///      end-to-end stamped frame, not a re-derivation.
///
/// This is preferred over onset detection because the gate must assert EXACTLY
/// 0 frames: a deterministic stamp read is exact; an onset detector is not.
///
/// # Why the strict gate fails on TODAY's code (expected, by design — TDD)
///
/// Today the master clock is WALL-CLOCK derived: `EngineController` stamps each
/// step's events with the pump's wake time (`eventScheduledHostTime = now` /
/// `now + stepDuration`, EngineController.swift), where `now` is the
/// `TickClock` `ProcessInfo.systemUptime` value. So the sounding frame tracks
/// the PUMP's jitter, not the musical grid. When we drive `processTick` with a
/// JITTERED pump timeline (a late/early wake), the stamped frame drifts off the
/// musical target by exactly the jitter — a strict 0-frame assert FAILS.
///
/// P0 makes the sounding frame come from the audio render clock, independent of
/// pump jitter, so the same assert will PASS. We mark those gate tests with
/// `XCTExpectFailure(strict: true)`: the suite stays GREEN now, and the marker
/// FAILS LOUDLY the moment P0 makes the gate pass (signalling "remove me").
///
/// The ideal-timeline conversion (pump wakes exactly on the grid) DOES hit
/// 0-frame today — that proves the seconds→frame math is already exact; the
/// only defect P0 fixes is the wall-clock ORIGIN of the seconds value.
///
/// # Phase 1 extension (BUILT — the zero-flam gate)
///
/// `OfflineFrameAccuracyHarness` is reused by the Phase 1 zero-flam gate
/// (`test_auNoteStamp_equalsProductionSliceFrame_viaOriginCorrelation_zeroFlam`).
/// A real AU is human-tier/TCC, so the gate does NOT instantiate one: the AU
/// note-on `AUEventSampleTime` is computed by the PURE
/// `AudioInstrumentHost.noteStamps` from the unified clock's
/// `sampleTime(atMusicalSeconds:)`, and the slice frame is derived from the
/// slice's PRODUCTION host-time stamp (`audioTime(atMusicalSeconds:)`) mapped
/// through the captured origin correlation (`capturedOriginCorrelation`). What is
/// machine-verified is "AU sampleTime stamp == production-slice-derived frame
/// under the captured-origin correlation" — NOT acoustic. Whether a REAL AU
/// honours the absolute frame on the device (render-clock base equality) remains
/// the documented HUMAN acoustic check.
final class OfflineFrameAccuracyTests: XCTestCase {

    // MARK: - Reusable harness

    /// Reusable offline frame-accuracy scaffold. Drives a real
    /// `EngineController` + `MainAudioGraph` (offline manual rendering) through
    /// `processTick` with a caller-supplied `now` timeline, and captures the
    /// exact frame each sample/slice trigger was stamped at.
    final class OfflineFrameAccuracyHarness {
        let sampleRate: Double
        let stepsPerBar: Int
        let controller: EngineController
        let sink: CapturingSampleSink

        /// Frame the override mapped each scheduled-seconds value onto, in
        /// chronological capture order.
        private(set) var capturedFrames: [(scheduledSeconds: Double, frame: AVAudioFramePosition)] = []
        /// Per-step capture: the frame the trigger fired on step N was stamped
        /// at. Index == musical step. (P1 extension reads this.)
        private(set) var capturedFrameByStep: [AVAudioFramePosition] = []

        private let originSeconds: Double

        init(
            sampleRate: Double = 48_000,
            stepsPerBar: Int = 16,
            originSeconds: Double = 0,
            controller: EngineController,
            sink: CapturingSampleSink
        ) {
            self.sampleRate = sampleRate
            self.stepsPerBar = stepsPerBar
            self.originSeconds = originSeconds
            self.controller = controller
            self.sink = sink

            // Stamp-capture seam — exercises the REAL production conversion, not
            // a re-derivation. The override DELEGATES to the engine's own
            // `AudioMasterClock.sampleTime(atMusicalSeconds:)` (the render-derived
            // frame API): it converts the upcoming step's MUSICAL-seconds value
            // (the unit the engine now enqueues) onto an absolute render frame
            // using the clock's captured origin, sampleRate, and rounding. Under
            // offline manual rendering the render position is deterministic
            // (`manualRenderingSampleTime`, typically 0 since the harness never
            // renders), so the conversion is exact — and if `AudioMasterClock`'s
            // math is wrong the captured frame diverges from `targetFrame` and
            // the 0-frame gate FAILS. (Previously this re-implemented
            // `musicalSeconds * sampleRate` inline, which made the gate assert
            // its own arithmetic and never touched `AudioMasterClock` — a
            // tautology.) The returned `AVAudioTime(sampleTime:)` is what the
            // sink records, so the captured frame is the genuine end-to-end stamp.
            controller.scheduledAudioTimeOverrideForTesting = { [weak self] scheduledMusicalSeconds in
                guard let self else { return nil }
                let frame = self.controller.audioMasterClock.sampleTime(
                    atMusicalSeconds: scheduledMusicalSeconds
                )
                self.capturedFrames.append((scheduledMusicalSeconds, frame))
                return AVAudioTime(sampleTime: frame, atRate: self.sampleRate)
            }
        }

        deinit {
            controller.scheduledAudioTimeOverrideForTesting = nil
        }

        /// The frame the trigger on `step` was stamped at, read from the
        /// capturing sink's recorded `AVAudioTime` (the real end-to-end stamp).
        func capturedFrame(forStep step: Int) -> AVAudioFramePosition? {
            guard step >= 0, step < capturedFrameByStep.count else { return nil }
            return capturedFrameByStep[step]
        }

        /// Drive one tick at a supplied wall-clock `now` (the pump wake time),
        /// then snapshot the frame stamped for that step.
        func drive(step: Int, now: TimeInterval) {
            let before = sink.lastStampedFrame(sampleRate: sampleRate)
            _ = before
            sink.markBoundary()
            controller.processTick(tickIndex: UInt64(step), now: now)
            if let frame = sink.lastStampedFrameSinceBoundary(sampleRate: sampleRate) {
                ensureCapacity(step)
                capturedFrameByStep[step] = frame
            }
        }

        private func ensureCapacity(_ step: Int) {
            while capturedFrameByStep.count <= step {
                capturedFrameByStep.append(-1)
            }
        }

        /// The exact musical-target frame for `step` given a tempo map.
        /// `bpmForStep` returns the BPM in effect when `step` plays.
        ///
        /// The frame is computed at the SAME sample rate the production clock
        /// stamped against (`AudioMasterClock.sampleRate`, seeded from the engine's
        /// offline manual-rendering format), not a test-local rate — so target and
        /// actual cannot diverge merely because the harness assumed a different
        /// rate from the engine. The independently-computed `seconds` (tempo map
        /// here vs the clock's incremental accumulator in production) is the real
        /// check: if the clock's musical math is wrong the frames differ and the
        /// 0-frame gate fails.
        func targetFrame(forStep step: Int, bpmForStep: (Int) -> Double) -> AVAudioFramePosition {
            var seconds = 0.0
            for priorStep in 0..<step {
                seconds += secondsPerStep(bpm: bpmForStep(priorStep))
            }
            return AVAudioFramePosition(((seconds) * clockSampleRate).rounded())
        }

        /// The sample rate the production clock is using (offline: the manual-
        /// rendering format rate). Falls back to the harness's nominal rate before
        /// the clock has seen a render position.
        var clockSampleRate: Double {
            let rate = controller.audioMasterClock.sampleRate
            return rate > 0 ? rate : sampleRate
        }

        func secondsPerStep(bpm: Double) -> TimeInterval {
            (60.0 / bpm) * (4.0 / Double(stepsPerBar))
        }
    }

    /// Captures the `AVAudioTime` handed to each sample/slice trigger, plus the
    /// rest of the `SamplePlaybackSink` surface (no-op). Lets the harness read
    /// the real end-to-end stamped frame deterministically.
    final class CapturingSampleSink: SamplePlaybackSink {
        private(set) var stampedTimes: [AVAudioTime?] = []
        private var boundaryIndex = 0

        func markBoundary() { boundaryIndex = stampedTimes.count }

        func lastStampedFrame(sampleRate: Double) -> AVAudioFramePosition? {
            stampedTimes.last.flatMap { $0 }.map { frame(of: $0, sampleRate: sampleRate) }
        }

        func lastStampedFrameSinceBoundary(sampleRate: Double) -> AVAudioFramePosition? {
            guard stampedTimes.count > boundaryIndex else { return nil }
            for time in stampedTimes[boundaryIndex...].reversed() {
                if let time { return frame(of: time, sampleRate: sampleRate) }
            }
            return nil
        }

        private func frame(of time: AVAudioTime, sampleRate: Double) -> AVAudioFramePosition {
            if time.isSampleTimeValid { return time.sampleTime }
            // Host-time fallback (production default path, no override): convert
            // host seconds → frame at the harness rate.
            return AVAudioFramePosition((AVAudioTime.seconds(forHostTime: time.hostTime) * sampleRate).rounded())
        }

        func start() throws {}
        func stop() {}
        func prepareTrack(trackID: UUID) {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            stampedTimes.append(when); return nil
        }
        func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            stampedTimes.append(when); return nil
        }
        func playSlice(
            sampleURL: URL,
            startFrame: AVAudioFramePosition,
            endFrame: AVAudioFramePosition,
            settings: SlicerSettings,
            trackID: UUID,
            at when: AVAudioTime?,
            reverse: Bool,
            stepParameters: SliceTriggerStepParameters?
        ) -> VoiceHandle? {
            stampedTimes.append(when); return nil
        }
        func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
        func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {}
        func removeTrack(trackID: UUID) {}
        func audition(sampleURL: URL) {}
        func stopAudition() {}
        func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
        func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
        func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
    }

    // MARK: - Fixtures

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: libraryRoot.appendingPathComponent("kick"),
            withIntermediateDirectories: true
        )
        try writeSilentWAV(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"), sampleRate: 48_000)
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func writeSilentWAV(to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makeAlwaysOnGenerator(id: UUID, trackType: TrackType) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: "Always On",
            trackType: trackType,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [DrumKitNoteMap.baselineNote], pickMode: .sequential)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
    }

    /// A one-sample-per-step drum project + a harness wired to capture stamps.
    private func makeSampleHarness(
        bpm: Double = 120,
        sampleRate: Double = 48_000,
        stepsPerBar: Int = 16
    ) throws -> OfflineFrameAccuracyHarness {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let sink = CapturingSampleSink()

        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: (0..<stepsPerBar).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id)) }
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: stepsPerBar,
            sampleEngine: sink,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(bpm)

        return OfflineFrameAccuracyHarness(
            sampleRate: sampleRate,
            stepsPerBar: stepsPerBar,
            controller: controller,
            sink: sink
        )
    }

    // MARK: - 0-frame gate: ideal timeline (math is exact today)

    /// CONTROL: when the pump wakes EXACTLY on the musical grid
    /// (`now == step * stepDuration`), the stamped frame equals the musical
    /// target frame to 0 frames TODAY. This proves the seconds→frame conversion
    /// math is already exact — the only defect P0 fixes is the wall-clock ORIGIN
    /// of the seconds value (see the jittered-pump gate below).
    func test_idealTimeline_stampsExactTargetFrame_zeroError() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let stepDuration = harness.secondsPerStep(bpm: bpm)

        let steps = 8
        for step in 0..<steps {
            harness.drive(step: step, now: Double(step) * stepDuration)
        }

        XCTAssertEqual(harness.capturedFrameByStep.count, steps, "every step must stamp exactly one trigger")
        for step in 0..<steps {
            let target = harness.targetFrame(forStep: step, bpmForStep: { _ in bpm })
            let actual = try XCTUnwrap(harness.capturedFrame(forStep: step))
            XCTAssertEqual(
                actual, target,
                "step \(step): ideal-timeline stamp must be 0 frames off the musical grid (was off by \(actual - target) frames)"
            )
        }
    }

    /// THE PHASE 0 TEMPO-CHANGE GATE (mandate: "the mapping stays exact across a
    /// mid-stream tempo change"). The mapping stays exact to the pure musical
    /// grid across a mid-stream tempo change. P0's unified audio clock
    /// (`AudioMasterClock`) advances the musical-position accumulator AFTER
    /// `executor.tick` drains the `setBPM` command, so the new step duration
    /// applies to the boundary step's interval with no one-tick lag and every
    /// stamp lands on its exact frame. (Pre-P0 this failed: the next step's
    /// stamp was computed from `now + stepDuration(BPM read before the consume)`,
    /// so the boundary step landed off-grid.) Permanent 0-frame regression guard.
    func test_idealTimeline_midStreamTempoChange_GATE() throws {
        let firstBPM = 120.0
        let secondBPM = 90.0
        let harness = try makeSampleHarness(bpm: firstBPM)

        let steps = 8
        let tempoChangeStep = 4
        func bpmForStep(_ step: Int) -> Double { step < tempoChangeStep ? firstBPM : secondBPM }

        var now = 0.0
        for step in 0..<steps {
            if step == tempoChangeStep {
                harness.controller.setBPM(secondBPM)
            }
            harness.drive(step: step, now: now)
            now += harness.secondsPerStep(bpm: bpmForStep(step))
        }

        XCTAssertEqual(harness.capturedFrameByStep.count, steps)
        for step in 0..<steps {
            let target = harness.targetFrame(forStep: step, bpmForStep: bpmForStep)
            let actual = try XCTUnwrap(harness.capturedFrame(forStep: step))
            XCTAssertEqual(
                actual, target,
                "step \(step) (bpm \(bpmForStep(step))): mapping must stay exact across the tempo change (off by \(actual - target))"
            )
        }
    }

    // MARK: - 0-frame gate: jittered pump (FAILS until P0 — the real gate)

    /// THE PHASE 0 GATE. Drives `processTick` with a JITTERED pump timeline (the
    /// pump wakes late/early, as a real `DispatchSourceTimer` does), and asserts
    /// every event still lands on its exact musical-grid frame.
    ///
    /// P0 derives each step's stamp from the unified audio clock's musical
    /// position (`AudioMasterClock.advance(toStep:bpm:)`), independent of the
    /// pump's wake `now`, so pump jitter no longer moves the sounding frame —
    /// every step lands at 0 frames. (Pre-P0 this failed: the engine stamped
    /// each step at the pump's wake time `now`, so the frame drifted by the
    /// injected jitter.) Permanent 0-frame regression guard.
    func test_jitteredPump_stampsExactTargetFrame_GATE() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let stepDuration = harness.secondsPerStep(bpm: bpm)

        // Deterministic pump jitter: alternate the wake early/late by a few ms
        // around the ideal grid time. A real pump's jitter is bounded by its
        // leeway; we model a worst-case bounded wobble.
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]

        let steps = jitter.count
        for step in 0..<steps {
            let idealNow = Double(step) * stepDuration
            harness.drive(step: step, now: idealNow + jitter[step])
        }

        XCTAssertEqual(harness.capturedFrameByStep.count, steps)
        for step in 0..<steps {
            let target = harness.targetFrame(forStep: step, bpmForStep: { _ in bpm })
            let actual = try XCTUnwrap(harness.capturedFrame(forStep: step))
            XCTAssertEqual(
                actual, target,
                "step \(step): the sounding frame must stay locked to the musical grid regardless of " +
                "pump jitter (off by \(actual - target) frames)"
            )
        }
    }

    /// THE PHASE 0 GATE across a mid-stream tempo change, under a jittered pump —
    /// the combined worst case (pump jitter AND a tempo change). Every stamp
    /// stays locked to the musical grid at 0 frames because P0 derives it from
    /// the unified clock's musical position, not the pump `now`. Permanent
    /// 0-frame regression guard.
    func test_jitteredPump_midStreamTempoChange_GATE() throws {
        let firstBPM = 120.0
        let secondBPM = 90.0
        let harness = try makeSampleHarness(bpm: firstBPM)

        let steps = 8
        let tempoChangeStep = 4
        func bpmForStep(_ step: Int) -> Double { step < tempoChangeStep ? firstBPM : secondBPM }
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]

        var now = 0.0
        for step in 0..<steps {
            if step == tempoChangeStep { harness.controller.setBPM(secondBPM) }
            harness.drive(step: step, now: now + jitter[step])
            now += harness.secondsPerStep(bpm: bpmForStep(step))
        }

        for step in 0..<steps {
            let target = harness.targetFrame(forStep: step, bpmForStep: bpmForStep)
            let actual = try XCTUnwrap(harness.capturedFrame(forStep: step))
            XCTAssertEqual(actual, target, "step \(step): off by \(actual - target) frames under jitter+tempo-change")
        }
    }

    /// Diagnostic: records the ACTUAL measured frame error under the jittered
    /// pump, so the report can cite a concrete number. Post-P0 the measured
    /// error is EXACTLY 0 at every step — the sounding frame no longer depends
    /// on the pump's wake time. (Pre-P0 this diagnostic measured a non-zero
    /// error equal to the prior step's injected pump jitter, pinning the defect
    /// to the wall-clock pump origin; P0 removed that origin.) Asserting an
    /// exact 0 here keeps the diagnostic a meaningful guard rather than a stale
    /// "fails for the right reason" probe.
    func test_jitteredPump_measuredFrameError_isZero() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let stepDuration = harness.secondsPerStep(bpm: bpm)
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]

        var errors: [AVAudioFramePosition] = []
        for step in 0..<jitter.count {
            harness.drive(step: step, now: Double(step) * stepDuration + jitter[step])
            let target = harness.targetFrame(forStep: step, bpmForStep: { _ in bpm })
            let actual = try XCTUnwrap(harness.capturedFrame(forStep: step))
            errors.append(actual - target)
        }

        // P0: every stamp derives from the unified clock's musical position, not
        // the pump's wake `now`, so the injected jitter contributes 0 frames.
        for step in 0..<jitter.count {
            XCTAssertEqual(
                errors[step], 0,
                "step \(step): under P0 the sounding frame is independent of pump jitter, so the frame " +
                "error must be exactly 0 (measured \(errors[step]); injected pump jitter for this step " +
                "was \(jitter[step]) s)."
            )
        }
    }

    // MARK: - Phase 1 zero-flam: AU sampleTime stamp == PRODUCTION slice frame

    /// THE PHASE 1 STAMP-LEVEL ZERO-FLAM GATE (mandate #36), DEFECT-3 REWORK.
    ///
    /// What "machine-verified" means here (precisely): the AU note-on
    /// `AUEventSampleTime` (`sampleTime(atMusicalSeconds:)`-derived) lands on the
    /// SAME render frame as a slice on the same step *derived from the slice's
    /// PRODUCTION host-time stamp through the captured-origin correlation*. It is
    /// NOT an acoustic claim — that a real AU honours the absolute frame on the
    /// device (render-clock base equality) is the documented HUMAN acoustic check.
    ///
    /// Why this is NOT the prior tautology: the previous gate compared the AU's
    /// `sampleTime(m)` against a "slice frame" the HARNESS fabricated with the
    /// SAME `sampleTime(m)` — i.e. `sampleTime(m) == sampleTime(m)`. Production
    /// slices are NOT stamped with `sampleTime`; they are stamped with a HOST TIME
    /// `audioTime(atMusicalSeconds: m)` = `AVAudioTime(hostTime: originHostSeconds
    /// + m)`. This rework derives the slice frame from that PRODUCTION host time:
    ///   sliceFrame = originSampleTime + (H − originHostSeconds) × sampleRate
    /// using the origin correlation captured from the SAME render position
    /// (`capturedOriginCorrelation`). The assertion `auSampleTime == sliceFrame`
    /// therefore exercises `audioTime` (the production host-time path) + the
    /// origin correlation + the AU `sampleTime` — three different functions/
    /// origins. If `audioTime` and `sampleTime` used inconsistent origins it would
    /// FAIL. (`test_originCorrelation_*` below perturbs an origin to prove that.)
    func test_auNoteStamp_equalsProductionSliceFrame_viaOriginCorrelation_zeroFlam() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let stepDuration = harness.secondsPerStep(bpm: bpm)
        let clock = harness.controller.audioMasterClock
        let steps = 8

        for step in 0..<steps {
            harness.drive(step: step, now: Double(step) * stepDuration)
        }

        let correlation = clock.capturedOriginCorrelation()

        for step in 0..<steps {
            // The unified-clock musical seconds the engine enqueued for this step.
            let musicalSeconds = harness.capturedFrames[step].scheduledSeconds

            // PRODUCTION slice stamp: a HOST TIME, NOT a sampleTime. This is the
            // exact value the live sample sink receives (`scheduledAudioTime` →
            // `audioMasterClock.audioTime(atMusicalSeconds:)`).
            let sliceHostTime = clock.audioTime(atMusicalSeconds: musicalSeconds)
            let sliceHostSeconds = AVAudioTime.seconds(forHostTime: sliceHostTime.hostTime)
            // Convert the production host time to a render frame through the
            // captured origin correlation — the real host→frame mapping the
            // engine relies on to land a host-stamped slice on a frame.
            let sliceFrame = correlation.frame(forHostSeconds: sliceHostSeconds)

            // PRODUCTION AU note-on stamp: the engine's `scheduledAUNoteSampleTime`
            // (sampleTime view) → `noteStamps`.
            let auStamp = try XCTUnwrap(
                harness.controller.scheduledAUNoteSampleTime(for: musicalSeconds)
            )
            let stamps = AudioInstrumentHost.noteStamps(
                noteOnSampleTime: auStamp.sampleTime,
                length: 4,
                bpm: bpm,
                stepsPerBar: harness.stepsPerBar,
                sampleRate: auStamp.sampleRate
            )

            XCTAssertEqual(
                stamps.noteOn, AUEventSampleTime(sliceFrame),
                "step \(step): AU note-on sampleTime stamp must equal the PRODUCTION slice frame " +
                "(slice's host-time stamp mapped through the captured-origin correlation) — " +
                "AU \(stamps.noteOn) vs slice \(sliceFrame)"
            )
            // Note-off is strictly after note-on (gate length > 0 frames).
            XCTAssertGreaterThan(
                stamps.noteOff, stamps.noteOn,
                "step \(step): note-off must be stamped after note-on (sample-accurate gate length)"
            )
        }
    }

    /// DEFECT-3 origin-correlation gate (the property the rework actually rests
    /// on): the captured `originSampleTime` and `originHostSeconds` (captured
    /// TOGETHER from one render position) map a musical second to the SAME instant
    /// in both units — i.e. converting `audioTime(m).hostTime` back to a frame
    /// through the correlation equals `sampleTime(m)`, across steps AND a tempo
    /// change. Then it PROVES the property is meaningful by perturbing ONE origin
    /// (the host-seconds half) and showing the equality breaks.
    func test_originCorrelation_hostTimeAndSampleTime_agree_andPerturbationBreaksIt() throws {
        let firstBPM = 120.0
        let secondBPM = 90.0
        let harness = try makeSampleHarness(bpm: firstBPM)
        let clock = harness.controller.audioMasterClock

        let steps = 8
        let tempoChangeStep = 4
        var now = 0.0
        for step in 0..<steps {
            if step == tempoChangeStep { harness.controller.setBPM(secondBPM) }
            harness.drive(step: step, now: now)
            now += harness.secondsPerStep(
                bpm: step < tempoChangeStep ? firstBPM : secondBPM
            )
        }

        let correlation = clock.capturedOriginCorrelation()

        for step in 0..<steps {
            let musicalSeconds = harness.capturedFrames[step].scheduledSeconds

            // sampleTime view (frame directly).
            let sampleTimeFrame = clock.sampleTime(atMusicalSeconds: musicalSeconds)
            // host-time view → frame via the correlation.
            let hostSeconds = AVAudioTime.seconds(
                forHostTime: clock.audioTime(atMusicalSeconds: musicalSeconds).hostTime
            )
            let viaCorrelation = correlation.frame(forHostSeconds: hostSeconds)

            XCTAssertEqual(
                viaCorrelation, sampleTimeFrame,
                "step \(step): host-time stamp mapped through the origin correlation must equal the " +
                "sampleTime stamp — the two origins (captured together) describe one instant"
            )

            // Meaningfulness: perturb the host-seconds half of the origin by
            // +5 ms. The correlation now disagrees with the sampleTime view for a
            // non-zero musical offset — proving the equality above is load-bearing
            // (it depends on the two origins being consistent, not on identity).
            let perturbed = AudioMasterClock.CapturedOriginCorrelation(
                sampleTime: correlation.sampleTime,
                hostSeconds: correlation.hostSeconds + 0.005,
                sampleRate: correlation.sampleRate,
                hasOrigin: correlation.hasOrigin,
                isRenderDerived: correlation.isRenderDerived
            )
            let perturbedFrame = perturbed.frame(forHostSeconds: hostSeconds)
            if musicalSeconds > 0 {
                XCTAssertNotEqual(
                    perturbedFrame, sampleTimeFrame,
                    "step \(step): perturbing the host-seconds origin by 5 ms MUST break the " +
                    "host↔sampleTime agreement — otherwise the correlation gate is vacuous"
                )
            }
        }
    }

    /// NEGATIVE CONTROL for the zero-flam gate: if the AU note-on were stamped
    /// from a WALL-CLOCK value (the pre-P1 main-hop shape — the pump's jittered
    /// wake `now`) instead of the unified clock's musical seconds, its frame would
    /// NOT match the PRODUCTION slice frame (slice host-time stamp through the
    /// origin correlation) under pump jitter. Proves the equality gate is
    /// load-bearing, not a tautology — it pins the AU stamp to the unified clock.
    func test_auNoteStamp_fromWallClock_divergesFromProductionSliceFrame() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let stepDuration = harness.secondsPerStep(bpm: bpm)
        let clock = harness.controller.audioMasterClock
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]

        var anyDiverged = false
        for step in 0..<jitter.count {
            let wakeNow = Double(step) * stepDuration + jitter[step]
            harness.drive(step: step, now: wakeNow)
            let musicalSeconds = harness.capturedFrames[step].scheduledSeconds

            // Production slice frame: host-time stamp through the origin correlation.
            let correlation = clock.capturedOriginCorrelation()
            let sliceHostSeconds = AVAudioTime.seconds(
                forHostTime: clock.audioTime(atMusicalSeconds: musicalSeconds).hostTime
            )
            let sliceFrame = correlation.frame(forHostSeconds: sliceHostSeconds)

            // Wall-clock-style AU stamp: from the pump's jittered wake `now`, not
            // the unified clock's musical seconds (the defect Phase 1 removes).
            let wallClockStamps = AudioInstrumentHost.noteStamps(
                noteOnSampleTime: clock.sampleTime(atMusicalSeconds: wakeNow),
                length: 4,
                bpm: bpm,
                stepsPerBar: harness.stepsPerBar,
                sampleRate: clock.sampleRate
            )
            if wallClockStamps.noteOn != AUEventSampleTime(sliceFrame) {
                anyDiverged = true
            }
        }

        XCTAssertTrue(
            anyDiverged,
            "a wall-clock-derived AU stamp must diverge from the production slice frame under pump " +
            "jitter — if it did not, the zero-flam equality gate would be a tautology"
        )
    }

    /// Proves `noteStamps` is a PURE function usable with no AU / no engine — the
    /// reason the zero-flam gate can run unattended (a real AU is TCC/human-tier).
    /// Asserts the zero-flam invariant directly (`noteOn == input frame`) and the
    /// gate-length math (note-off = note-on + gate frames).
    func test_auNoteStamps_isPure_zeroFlamInvariant_andGateLength() throws {
        let sampleRate = 48_000.0
        let bpm = 120.0
        let stepsPerBar = 16
        let inputFrame: AVAudioFramePosition = 123_456

        let stamps = AudioInstrumentHost.noteStamps(
            noteOnSampleTime: inputFrame,
            length: 4,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            sampleRate: sampleRate
        )

        // Zero-flam invariant: note-on is EXACTLY the input frame.
        XCTAssertEqual(stamps.noteOn, AUEventSampleTime(inputFrame))

        // Gate length: 4 steps at 120 bpm / 16 spb = 4 × (0.5 s) = 0.5 s × 48k = 24000 frames.
        let secondsPerStep = (60.0 / bpm) * (4.0 / Double(stepsPerBar))
        let expectedGateFrames = AVAudioFramePosition((secondsPerStep * 4 * sampleRate).rounded())
        XCTAssertEqual(stamps.noteOff, AUEventSampleTime(inputFrame + expectedGateFrames))

        // Nil note-on time → immediate (fallback) for both stamps.
        let immediate = AudioInstrumentHost.noteStamps(
            noteOnSampleTime: nil,
            length: 4,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            sampleRate: sampleRate
        )
        XCTAssertEqual(immediate.noteOn, AUEventSampleTime(AUEventSampleTimeImmediate))
        XCTAssertEqual(immediate.noteOff, AUEventSampleTime(AUEventSampleTimeImmediate))
    }

    /// DEFECT 4 past-frame guard: a note-on frame BEHIND the AU's current render
    /// frame is clamped to immediate (never handed to the AU as a past frame); a
    /// frame at/after the current render frame is stamped exactly.
    func test_auNoteStamps_pastFrame_clampsToImmediate() throws {
        let sampleRate = 48_000.0
        let bpm = 120.0
        let stepsPerBar = 16

        // Note-on 1000 frames in the AU's PAST → both stamps immediate.
        let past = AudioInstrumentHost.noteStamps(
            noteOnSampleTime: 9_000,
            length: 4,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            sampleRate: sampleRate,
            currentRenderFrame: 10_000
        )
        XCTAssertEqual(past.noteOn, AUEventSampleTime(AUEventSampleTimeImmediate))
        XCTAssertGreaterThan(
            past.noteOff,
            AUEventSampleTime(10_000),
            "Past-frame fallback should keep a future note-off so the immediate note-on has an audible gate."
        )

        // Note-on at/after the current render frame → stamped exactly (no clamp).
        let future = AudioInstrumentHost.noteStamps(
            noteOnSampleTime: 12_000,
            length: 4,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            sampleRate: sampleRate,
            currentRenderFrame: 10_000
        )
        XCTAssertEqual(future.noteOn, AUEventSampleTime(12_000))
        XCTAssertGreaterThan(future.noteOff, future.noteOn)

        // No render frame (nil) → no floor, exact stamp (pre-render handled by
        // the nil-noteOnSampleTime fallback elsewhere).
        let noFloor = AudioInstrumentHost.noteStamps(
            noteOnSampleTime: 5,
            length: 4,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            sampleRate: sampleRate,
            currentRenderFrame: nil
        )
        XCTAssertEqual(noFloor.noteOn, AUEventSampleTime(5))
    }
}
