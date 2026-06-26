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
/// # Extension point (P1, not built here)
///
/// `OfflineFrameAccuracyHarness` is reusable. P1 will add an AU-note-vs-slice
/// zero-flam assertion (AU note-on and a slice on the same step land on the
/// same frame). AU is human-tier/TCC and out of unattended scope, so it is NOT
/// built now — the harness deliberately exposes `capturedFrame(forStep:)` so
/// the P1 test can compare an AU-stamped frame against a slice-stamped frame
/// without reworking the rig.
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

            // Stamp-capture seam: mirror P0's target conversion
            // (AVAudioTime(sampleTime:atRate:)) and record the frame. This is
            // the conversion the engine WILL use post-P0; feeding it the
            // engine's current `scheduledHostTime` faithfully exposes whatever
            // origin that seconds value came from (ideal grid vs jittered pump).
            controller.scheduledAudioTimeOverrideForTesting = { [weak self] scheduledHostTime in
                guard let self else { return nil }
                let frame = AVAudioFramePosition(
                    ((scheduledHostTime - self.originSeconds) * self.sampleRate).rounded()
                )
                self.capturedFrames.append((scheduledHostTime, frame))
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
        func targetFrame(forStep step: Int, bpmForStep: (Int) -> Double) -> AVAudioFramePosition {
            var seconds = 0.0
            for priorStep in 0..<step {
                seconds += secondsPerStep(bpm: bpmForStep(priorStep))
            }
            return AVAudioFramePosition(((seconds) * sampleRate).rounded())
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
    /// mid-stream tempo change"). Even on an IDEAL (jitter-free) timeline, the
    /// current scheduler does NOT keep the mapping exact to the pure musical grid
    /// across a mid-stream tempo change: `setBPM` enqueues a command consumed by
    /// `executor.tick` INSIDE `prepareTick`, but the next step's
    /// `scheduledHostTime` is computed from the BPM read BEFORE that consume
    /// (EngineController.swift `nextStepBPM` / `eventScheduledHostTime`), so the
    /// new step duration applies one tick late and the boundary step lands off
    /// the grid. That one-tick command/clock coupling is exactly what P0's
    /// unified audio clock removes, so this flips to PASS under P0.
    ///
    /// `XCTExpectFailure(strict: true)` keeps the suite green now and fails
    /// loudly when P0 makes it pass (remove the marker then).
    func test_idealTimeline_midStreamTempoChange_GATE_failsUntilP0() throws {
        XCTExpectFailure(
            "Phase 0 tempo-change gate: the mapping must stay exact to the musical grid across a " +
            "mid-stream tempo change. Today setBPM applies to the next step's stamp one tick late " +
            "(command-queue vs explicit-stepDur read in EngineController), so the boundary step lands " +
            "off-grid. P0's unified audio clock removes this coupling and the gate passes — strict " +
            "mode flags this marker for removal when it does.",
            strict: true
        )

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
    /// TODAY this FAILS: the engine stamps each step at the pump's wake time
    /// (`eventScheduledHostTime = now`), so the sounding frame drifts by the
    /// jitter. After P0 derives the sounding frame from the audio render clock
    /// (independent of pump jitter), it PASSES.
    ///
    /// `XCTExpectFailure(strict: true)` keeps the suite green now AND fails
    /// loudly the moment P0 makes it pass — signalling "remove this marker".
    func test_jitteredPump_stampsExactTargetFrame_GATE_failsUntilP0() throws {
        XCTExpectFailure(
            "Phase 0 gate: asserts the not-yet-true 0-frame target under a jittered pump. " +
            "Today the master clock is wall-clock derived (EngineController stamps each step at the " +
            "pump's `now`), so the stamped frame drifts by the pump jitter. P0 derives the sounding " +
            "frame from the audio render clock and this flips to PASS — when it does, strict mode " +
            "FAILS here so this marker is removed.",
            strict: true
        )

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

    /// THE PHASE 0 GATE across a mid-stream tempo change, under a jittered pump.
    /// Same fail-until-P0 contract as above.
    func test_jitteredPump_midStreamTempoChange_GATE_failsUntilP0() throws {
        XCTExpectFailure(
            "Phase 0 gate (tempo change): under a jittered pump the stamped frame must stay locked to " +
            "the musical grid across a mid-stream tempo change. Fails until P0 moves the sounding frame " +
            "onto the audio render clock; strict mode flags this marker for removal when it passes.",
            strict: true
        )

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

    /// Diagnostic (always green): records the ACTUAL measured frame error under
    /// the jittered pump on the CURRENT code, so the report can cite a concrete
    /// number rather than "fails". Confirms the wall-clock dependency is real
    /// and bounded by the injected jitter — i.e. the gate above fails for the
    /// documented reason, not some unrelated breakage.
    func test_jitteredPump_currentCode_measuredFrameError_isWallClockJitter() throws {
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

        // On current (wall-clock) code each step N is stamped during the PRIOR
        // tick's prepare at `now_{N-1} + stepDuration`
        // (EngineController.swift: step N's event carries the (N-1)-th pump
        // wake time). So the frame error for step N equals the PRIOR step's
        // injected pump jitter, in frames: error[N] = jitter[N-1] * sampleRate
        // (and step 0/1 both carry jitter[0]). This pins the defect precisely to
        // the wall-clock pump origin — exactly what P0 removes.
        func jitterForStampOf(step: Int) -> Double { jitter[max(0, step - 1)] }
        for step in 0..<jitter.count {
            let expectedError = AVAudioFramePosition((jitterForStampOf(step: step) * harness.sampleRate).rounded())
            XCTAssertEqual(
                errors[step], expectedError,
                "step \(step): current code stamps at the prior pump wake time, so the frame error must " +
                "equal the prior step's injected pump jitter (\(jitterForStampOf(step: step)) s = " +
                "\(expectedError) frames). Measured \(errors[step])."
            )
        }
        // At least one non-zero error proves the wall-clock dependency exists
        // (the gate is not passing vacuously).
        XCTAssertTrue(errors.contains { $0 != 0 }, "jittered pump must produce a non-zero frame error on current code")
    }
}
