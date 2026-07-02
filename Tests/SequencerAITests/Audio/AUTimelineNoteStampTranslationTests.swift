import AVFoundation
import AudioToolbox
import XCTest

@testable import SequencerAI

/// Bug 20260630-143852 — AU instrument track silent for the whole first
/// transport run; audio appeared when the user pressed Stop.
///
/// Root cause (measured in the 2026-07-02 user session unified log): AU note
/// stamps were OUTPUT-node render frames handed raw to
/// `scheduleMIDIEventBlock`, which interprets them on the AU's OWN render
/// timeline. The AU (native 44.1 kHz output format behind a converter in a
/// 48 kHz engine) advanced its render counter at 44,100 f/s vs the output's
/// 48,000 f/s, so after ~112 s of warm session every stamp sat ~441,000 frames
/// (~10 s) in the AU's future — scheduled, inaudible, and finally sounding
/// right around the user's Stop when the AU counter caught up.
///
/// The fix translates the stamp through the two "now" values read at dispatch
/// (`AudioInstrumentHost.auTimelineNoteOnFrame`):
///
///     auFrame = auNow + (outputFrame − outputNow) × auRate / outputRate
///
/// These tests pin the pure translation math, and the gold rail below rebuilds
/// the exact production skew offline (DLS synth's native 44.1 kHz format inside
/// a 48 kHz manual-rendering engine — same shape as the user's session, no
/// permissions needed) and asserts the FIRST-RUN note-on renders audibly at its
/// due time instead of sliding into the AU's far future.
final class AUTimelineNoteStampTranslationTests: XCTestCase {

    // MARK: - Pure translation math

    /// When the AU and output timelines genuinely coincide (equal rates AND
    /// equal counters — the assumption the pre-fix code baked in), translation
    /// must be the identity so the offline zero-flam number-equality rails are
    /// untouched in that regime.
    func test_translation_isIdentity_whenTimelinesCoincide() {
        let frame = AudioInstrumentHost.auTimelineNoteOnFrame(
            outputFrame: 252_000,
            outputNowFrame: 240_000,
            outputSampleRate: 48_000,
            auNowFrame: 240_000,
            auSampleRate: 48_000
        )
        XCTAssertEqual(frame, 252_000)
    }

    /// Same rate, different base (attach-later / reset skew): the relative
    /// offset from "now" is preserved onto the AU's counter.
    func test_translation_appliesBaseOffset_sameRate() {
        let frame = AudioInstrumentHost.auTimelineNoteOnFrame(
            outputFrame: 1_048_000,
            outputNowFrame: 1_000_000,
            outputSampleRate: 48_000,
            auNowFrame: 100_000,
            auSampleRate: 48_000
        )
        // 48,000 output frames ahead of now → 48,000 AU frames ahead of auNow.
        XCTAssertEqual(frame, 148_000)
    }

    /// The measured user-session shape (2026-07-02 log): output timeline at
    /// 48 kHz ~441k frames ahead of the AU's 44.1 kHz counter. A stamp 0.25 s
    /// ahead of output-now must land 0.25 s ahead of the AU's OWN counter
    /// (11,025 AU frames), not ~10 s in its future.
    func test_translation_appliesRateConversion_userSessionShape() {
        let outputNow: AVAudioFramePosition = 5_404_000 - 12_000 // stamp was 0.25 s ahead
        let auNow: AVAudioFramePosition = 4_962_604
        let frame = AudioInstrumentHost.auTimelineNoteOnFrame(
            outputFrame: 5_404_000,
            outputNowFrame: outputNow,
            outputSampleRate: 48_000,
            auNowFrame: auNow,
            auSampleRate: 44_100
        )
        // 12,000 output frames = 0.25 s = 11,025 AU frames.
        XCTAssertEqual(frame, auNow + 11_025)
        // The pre-fix behaviour (raw output frame) sat ~10 s in the AU future;
        // the translated stamp is within one bar (2 s at 120 bpm) of AU-now.
        XCTAssertLessThan(frame - auNow, AVAudioFramePosition(2.0 * 44_100))
    }

    /// Degenerate rates never divide by zero; the raw frame passes through.
    func test_translation_guardsNonPositiveRates() {
        XCTAssertEqual(
            AudioInstrumentHost.auTimelineNoteOnFrame(
                outputFrame: 42,
                outputNowFrame: 10,
                outputSampleRate: 0,
                auNowFrame: 5,
                auSampleRate: 44_100
            ),
            42
        )
        XCTAssertEqual(
            AudioInstrumentHost.auTimelineNoteOnFrame(
                outputFrame: 42,
                outputNowFrame: 10,
                outputSampleRate: 48_000,
                auNowFrame: 5,
                auSampleRate: 0
            ),
            42
        )
    }

    // MARK: - Gold rail: first-run audibility with a skewed AU timeline

    /// Rebuilds the user-session skew offline and asserts the first note of a
    /// "transport run" RENDERS at its due instant.
    ///
    /// Fixture physics (verified by spike before writing this test): the Apple
    /// DLS synth (`appl aumu dls`, permission-free) vends a native 44.1 kHz
    /// output format; `MainAudioGraph.connect(_:to:)` connects with `format:
    /// nil`, so inside a 48 kHz manual-rendering engine the AU renders behind a
    /// converter and its `lastRenderTime` counts 44.1k frames — exactly the
    /// user's Arturia session shape. After a 5 s warmup the output counter
    /// leads the AU counter by ~19,500 frames; pre-fix, a stamp 0.25 s ahead of
    /// output-now sounded ~0.71 s late (measured 0.7148 s in the spike), i.e.
    /// warmupSkew/auRate later than due — the same mechanism that made the
    /// user's ~112 s-warm session silent for ~10 s (their whole first run).
    func test_firstRun_auNoteOn_rendersAtDueInstant_despiteSkewedAUTimeline() throws {
        let outputRate: Double = 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2) else {
            XCTFail("cannot build 48 kHz render format")
            return
        }
        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        } catch {
            throw XCTSkip("manual rendering unavailable: \(error)")
        }
        let graph = MainAudioGraph(engine: engine)

        // Manual-rendering wiring lifecycle (same recipe as OfflineRenderHarness):
        // one start/stop cycle, wire everything while STOPPED, restart once —
        // connects made on a running manual-mode engine park as pending forever.
        try graph.start()
        graph.engine.stop()

        let host = AudioInstrumentHost(
            instrumentChoices: [.builtInSynth],
            initialInstrument: .builtInSynth,
            audioGraph: graph,
            autoStartEngine: false
        )
        defer { host.shutdown() }
        host.prepareIfNeeded()

        // The host instantiates + connects the DLS synth across its own queue
        // and main; pump until it reports available.
        let deadline = Date().addingTimeInterval(15)
        while !host.isAvailable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard host.isAvailable, let synth = host.currentAudioUnit else {
            throw XCTSkip("DLS synth did not become available (component load environment issue)")
        }

        // Manual-rendering routing canonicalization (same reason as
        // OfflineRenderHarness.canonicalizeMixTopology): the host's dynamic
        // mixer/dry-destination connects can park as pending in manual mode and
        // never pull the AU. Re-issue a direct AU-downstream → mainMixer edge
        // while STOPPED. This rail is about note STAMPING on the AU's timeline,
        // not the production routing topology.
        let auDownstream = engine.outputConnectionPoints(for: synth, outputBus: 0).first?.node ?? synth
        engine.disconnectNodeOutput(auDownstream)
        engine.connect(auDownstream, to: engine.mainMixerNode, format: nil)

        graph.engine.prepare()
        try graph.engine.start()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: 512
        ) else {
            XCTFail("cannot allocate render buffer")
            return
        }

        // Empirical manual-rendering quirk (spiked before writing this test):
        // node `lastRenderTime` observers stay dormant for the first couple of
        // engine starts after wiring; short render passes with stop/restart
        // cycles wake them (nodes attached after a prior engine cycle needed
        // two restarts in the spike). Without this the AU timeline — which the
        // production translation reads — is unobservable in manual mode.
        var activationCycles = 0
        while synth.lastRenderTime?.isSampleTimeValid != true, activationCycles < 5 {
            for _ in 0..<20 {
                _ = try engine.renderOffline(512, to: renderBuffer)
            }
            engine.stop()
            engine.prepare()
            try engine.start()
            activationCycles += 1
        }

        var rendered: [Float] = []
        func render(seconds: Double, collect: Bool) throws {
            var remaining = Int(seconds * outputRate)
            while remaining > 0 {
                let chunk = AVAudioFrameCount(min(remaining, 512))
                let status = try engine.renderOffline(chunk, to: renderBuffer)
                guard status == .success else {
                    XCTFail("renderOffline returned \(status)")
                    return
                }
                let frames = Int(renderBuffer.frameLength)
                if collect, let data = renderBuffer.floatChannelData?[0] {
                    rendered.append(contentsOf: UnsafeBufferPointer(start: data, count: frames))
                }
                remaining -= frames
            }
        }

        // Warm the session WITHOUT transport — this is what accumulates the
        // output-vs-AU counter skew the user hit (their graph was warm ~112 s
        // before the first run; 5 s is plenty to push the note visibly late).
        try render(seconds: 5.0, collect: false)

        // The fixture must actually express a skewed AU timeline, or this rail
        // is vacuous. (If a future macOS makes the DLS synth follow the engine
        // rate, this fails loudly so the fixture can be rebuilt.)
        guard let auNowTime = synth.lastRenderTime, auNowTime.isSampleTimeValid else {
            print("FIXTURE-DEBUG engine.isRunning=\(engine.isRunning) manualSampleTime=\(engine.manualRenderingSampleTime)")
            print("FIXTURE-DEBUG synth.engine=\(String(describing: synth.engine !== nil))")
            print("FIXTURE-DEBUG synth.lastRenderTime=\(String(describing: synth.lastRenderTime))")
            print("FIXTURE-DEBUG synth outputFormat=\(synth.outputFormat(forBus: 0))")
            print("FIXTURE-DEBUG synth outPoints=\(engine.outputConnectionPoints(for: synth, outputBus: 0).map { String(describing: $0.node) })")
            print("FIXTURE-DEBUG auDownstream=\(auDownstream) outPoints=\(engine.outputConnectionPoints(for: auDownstream, outputBus: 0).map { String(describing: $0.node) })")
            print("FIXTURE-DEBUG mainMixer inputFormat=\(engine.mainMixerNode.inputFormat(forBus: 0)) lastRender=\(String(describing: engine.mainMixerNode.lastRenderTime))")
            XCTFail("AU lastRenderTime not valid after 5 s of rendering — fixture cannot measure the AU timeline")
            return
        }
        XCTAssertNotEqual(
            auNowTime.sampleRate, outputRate,
            "fixture precondition: the DLS synth should render on its own 44.1 kHz timeline inside the 48 kHz engine"
        )
        guard let outputNow = graph.renderPosition else {
            XCTFail("no output render position after warmup")
            return
        }
        XCTAssertGreaterThan(
            outputNow.sampleTime - auNowTime.sampleTime, AVAudioFramePosition(0.25 * outputRate),
            "fixture precondition: warmup should have skewed the two render counters apart by well over the due lead"
        )

        // FIRST RUN: one note stamped 0.25 s ahead on the OUTPUT timeline —
        // exactly what EngineController.scheduledAUNoteSampleTime hands the
        // host in production.
        let dueLeadSeconds = 0.25
        let stampOutputFrame = outputNow.sampleTime + AVAudioFramePosition(dueLeadSeconds * outputRate)
        host.play(
            noteEvents: [NoteEvent(pitch: 60, velocity: 127, length: 4, gate: true, voiceTag: nil)],
            bpm: 120,
            stepsPerBar: 16,
            noteOnSampleTime: stampOutputFrame,
            sampleRate: outputRate
        )
        // play() hops onto the host queue; give it time to schedule before the
        // block containing the due frame is rendered.
        let scheduled = expectation(description: "note scheduled on host queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { scheduled.fulfill() }
        wait(for: [scheduled], timeout: 5)

        try render(seconds: 1.5, collect: true)

        var firstLoudFrame = -1
        for (index, sample) in rendered.enumerated() where abs(sample) > 0.005 {
            firstLoudFrame = index
            break
        }
        XCTAssertGreaterThanOrEqual(
            firstLoudFrame, 0,
            "first-run AU note never rendered — the stamp sat in the AU's far future " +
            "(bug 20260630-143852 shape: silent run, audio only after the AU counter catches up)"
        )
        if firstLoudFrame >= 0 {
            let onsetSeconds = Double(firstLoudFrame) / outputRate
            // Pre-fix this measured ~0.71 s (due + warmupSkew/auRate); the user's
            // session pushed it past the whole run. Post-fix the note lands at
            // its due instant (± scheduling visibility of a couple render quanta).
            XCTAssertEqual(
                onsetSeconds, dueLeadSeconds, accuracy: 0.06,
                "first-run AU note must sound at its DUE instant on the AU's own timeline, " +
                "not displaced by the output-vs-AU counter skew (bug 20260630-143852)"
            )
        }
    }
}
