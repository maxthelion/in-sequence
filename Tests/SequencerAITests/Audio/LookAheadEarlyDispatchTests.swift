import AVFoundation
import XCTest
@testable import SequencerAI

/// FROZEN RAIL — ROUND-2 P3 "real early dispatch, not an origin delay".
///
/// Authored from the SPEC
/// (`docs/plans/2026-07-01-round2-integration-spec.md`, "P3 — real early
/// dispatch, not an origin delay"; `docs/plans/2026-06-30-precompute-lookahead-
/// recording.md`, Phase 3 + Gate-1 first-play criterion), NEVER from the
/// implementation, then FROZEN. Matches the fleet brief's frozen-rail glob
/// ("any `Tests/.../*LookAhead*` test"): builders must NOT edit, weaken,
/// `XCTSkip`, delete, or stub this file.
///
/// # Why round-1's Phase-3 rails did not catch the wrong mechanism
///
/// Round-1 realised the 100 ms look-ahead lead by SHIFTING the captured
/// master-clock origin forward by the lead (`EngineController.start()` →
/// `AudioMasterClock.captureOrigin(..., leadSeconds:)`). Its rails
/// (`LookAheadSchedulingTests`, `LookAheadOriginShiftGuardTests`,
/// `LookAheadStartCallSiteGuardTests`) actively ASSERT that shift is present —
/// they encode the origin-delay as "the shipped flam fix". But an origin shift
/// pays the lead as ~100 ms of ABSOLUTE first-play latency (musical second 0
/// sounds 100 ms after the transport-start render position), which DEFEATS the
/// Gate-1 ≤ 10 ms first-play criterion. And the real early-dispatch surface
/// `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)` is DEAD in production:
/// the live `dispatchTick` loop stamps via `dispatchSampleAudioTime` /
/// `scheduledAUNoteSampleTime` and never calls it.
///
/// # The two invariants this rail encodes
///
/// A. THE MUSICAL-ZERO ANCHOR IS THE SMALL NAMED STARTUP ANCHOR, NEVER THE
///    LOOK-AHEAD LEAD. G2-gate amendment, OWNER-APPROVED 2026-07-02 (per the
///    plan's "adjust on return and re-gate" provision; locked thresholds:
///    startup anchor lead = 50 ms, rail cap = 60 ms). The original ≤ 10 ms
///    first-play window is superseded: the rig proved a zero-anchored origin
///    makes step 0's stamp unschedulable (knife-edge inside the ~23 ms
///    schedule-visibility horizon + ~20 ms cold dispatch), landing the first
///    hit +41 ms off-grid non-deterministically. The amended contract, driving
///    the REAL production `EngineController.start()` over an offline
///    `MainAudioGraph`:
///      (a) musical second 0 is anchored EXACTLY
///          `AudioMasterClock.startupAnchorLeadSeconds` after the
///          transport-start render position (frame-domain exact);
///      (b) `startupAnchorLeadSeconds` ≤ 0.060 — the owner-locked rail cap;
///      (c) `AudioMasterClock.lookAheadLeadSeconds` > 0.060 — so the 100 ms
///          look-ahead lead can never masquerade as the startup anchor (the
///          original anti-origin-delay property, encoded directly).
///    The round-1 origin shift (origin + lookAheadLeadSeconds) violates (a)
///    and blows the (b) cap → RED, exactly as the old 10 ms window made it.
///
/// B. `leadStampedAudioTime` IS THE LIVE DISPATCH PATH, invoked with the
///    configured lead. Driving a firing track through `start()` + `processTick`,
///    the live `dispatchTick` loop must route each sample/AU event's stamp
///    through `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)` and report
///    it through the `leadStampedAudioTimeDispatchProbeForTesting` seam with the
///    configured lead (>= 100 ms). Round-1's dispatch never calls it → the probe
///    stays silent → RED.
///
/// # Adversarial audit (informed — see the accompanying report)
///
/// The KNOWN-hollow round-1 form (fixed origin-shift at start + a lead-less /
/// dead `leadStampedAudioTime`) MUST make this rail RED: invariant A fails on the
/// origin shift (100 ms lead ≠ the exact 50 ms anchor, and 100 ms > the 60 ms
/// cap), invariant B fails on the silent probe. The negative controls below
/// prove each invariant is load-bearing, not a tautology.
///
/// # Determinism
///
/// Like `OfflineFrameAccuracyTests` / `WarmEnginePhase1Tests`: a real
/// `EngineController` over a real `MainAudioGraph` in offline manual-rendering
/// mode, driven on a synthetic timeline. No device, no real AU, no onset
/// detection — only the deterministic stamp/probe seams.
final class LookAheadEarlyDispatchTests: XCTestCase {

    /// The G2 OWNER-LOCKED rail cap on the startup anchor (seconds). SPEC
    /// constant — NOT read back from the feature (a rail that derived its own
    /// threshold from the implementation could never fail it). Owner approval
    /// 2026-07-02: startup anchor lead = 50 ms, rail cap = 60 ms. Any origin
    /// anchored MORE than this past the transport-start render position —
    /// notably one shifted by the 100 ms look-ahead lead — fails the rail.
    private static let specStartupAnchorRailCapSeconds: TimeInterval = 0.060

    /// The Gate-1 LOCKED look-ahead lead (seconds). SPEC constant. Spec:
    /// "Look-ahead lead: 100 ms."
    private static let specLeadSeconds: TimeInterval = 0.100

    // MARK: - Fixtures (mirror WarmEnginePhase1Tests' offline build)

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

    /// A one-sample-per-step drum project that fires a sample trigger every step.
    private func makeProject(stepsPerBar: Int = 16) throws -> (Project, AudioSampleLibrary) {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))

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
                    slots: (0..<stepsPerBar).map {
                        TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id))
                    }
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, library)
    }

    /// Counts `play(...)` dispatches so the live-path invariant can prove the
    /// dispatch loop actually ran. All other sink surface is a no-op.
    private final class CapturingPlaySink: SamplePlaybackSink {
        private(set) var playCount = 0

        func start() throws {}
        func stop() {}
        func prepareTrack(trackID: UUID) {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCount += 1; return nil
        }
        func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCount += 1; return nil
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
            playCount += 1; return nil
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

    // MARK: - INVARIANT A: musical zero anchored EXACTLY startupAnchorLeadSeconds

    /// THE STARTUP-ANCHOR GATE (G2 amendment, owner-approved 50 ms / 60 ms cap).
    /// Drives the REAL production `EngineController.start()` over an offline
    /// `MainAudioGraph` and asserts:
    ///
    ///   (a) musical second 0 is anchored EXACTLY
    ///       `AudioMasterClock.startupAnchorLeadSeconds` after the
    ///       transport-start render position. Frame-domain exact: in manual
    ///       rendering the render `sampleTime` is static until frames are
    ///       rendered (none are here), so the captured origin frame must equal
    ///       renderFrame + round(anchor × sampleRate) to the frame.
    ///   (b) the anchor constant is within the owner-locked 60 ms rail cap.
    ///   (c) `lookAheadLeadSeconds` is ABOVE the cap — the 100 ms look-ahead
    ///       lead structurally cannot pose as the startup anchor.
    ///
    /// The round-1 origin-delay mechanism (origin + lookAheadLeadSeconds) fails
    /// (a) exactly and blows the (b) cap in the host-domain window below → RED,
    /// preserving the original rail's discriminating power.
    func test_firstPlay_musicalZero_anchoredExactlyAtStartupAnchorLead_GATE() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )
        // Empty document: live session active, no firing tracks, so start() brings
        // the transport up without scheduling any sample voices.
        controller.apply(documentModel: .empty)
        controller.setBPM(120)

        // (b) + (c): the constants contract. SPEC cap, not read back from the
        // feature; the lead must sit strictly ABOVE the cap so no origin that
        // passes this rail can have been anchored by the lead.
        XCTAssertGreaterThan(
            AudioMasterClock.startupAnchorLeadSeconds, 0,
            "the startup anchor must be a real positive lead — a zero anchor is the knife-edge " +
            "unschedulable step-0 stamp the 2026-07-02 rig measured landing +41 ms off-grid."
        )
        XCTAssertLessThanOrEqual(
            AudioMasterClock.startupAnchorLeadSeconds, Self.specStartupAnchorRailCapSeconds,
            "startupAnchorLeadSeconds must respect the owner-locked \(Self.specStartupAnchorRailCapSeconds * 1000) ms " +
            "rail cap (G2 amendment, 2026-07-02)."
        )
        XCTAssertGreaterThan(
            AudioMasterClock.lookAheadLeadSeconds, Self.specStartupAnchorRailCapSeconds,
            "lookAheadLeadSeconds must exceed the \(Self.specStartupAnchorRailCapSeconds * 1000) ms anchor rail " +
            "cap — otherwise the look-ahead lead could masquerade as the startup anchor (the round-1 " +
            "origin-delay defect this rail exists to block)."
        )

        // The render frame at transport start: static in manual rendering mode
        // (no frames are rendered by this test), so it is the exact frame
        // `captureOrigin` reads inside `start()`.
        let renderFrameAtStart = try XCTUnwrap(
            graph.renderPosition,
            "offline manual rendering must expose a render position for start() to anchor against"
        ).sampleTime

        let before = ProcessInfo.processInfo.systemUptime
        controller.start()
        defer { controller.stop() }

        XCTAssertTrue(
            controller.isRunning,
            "start() must take the transport live for this startup-anchor gate to be meaningful"
        )

        // (a) frame-domain EXACT: origin frame == render frame + anchor frames.
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(
            correlation.isRenderDerived,
            "start() over an offline graph must capture a render-derived origin — a fallback origin " +
            "here would mean the anchor was not measured against the render position at all"
        )
        let expectedAnchorFrames = AVAudioFramePosition(
            (AudioMasterClock.startupAnchorLeadSeconds * correlation.sampleRate).rounded()
        )
        XCTAssertEqual(
            correlation.sampleTime, renderFrameAtStart + expectedAnchorFrames,
            "musical second 0 must be anchored EXACTLY startupAnchorLeadSeconds " +
            "(\(AudioMasterClock.startupAnchorLeadSeconds * 1000) ms = \(expectedAnchorFrames) frames) after " +
            "the transport-start render position — measured origin frame \(correlation.sampleTime) vs " +
            "render frame \(renderFrameAtStart). An excess near " +
            "\(Self.specLeadSeconds * 1000) ms means the look-ahead lead was paid as an origin shift " +
            "(the rejected round-1 mechanism); zero excess means the anchor was dropped and step 0 is " +
            "back on the unschedulable knife edge."
        )

        // Host-domain window: the origin host-seconds for musical second 0 sits
        // the anchor past the start instant (plus only start() overhead, well
        // under the cap headroom). Bounds the ABSOLUTE first-play latency by the
        // owner-locked cap: an origin shifted by the 100 ms lead lands ~100 ms
        // here and fails.
        let firstPlayHostSeconds = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)
        let absoluteLatency = firstPlayHostSeconds - before
        XCTAssertGreaterThanOrEqual(
            absoluteLatency, AudioMasterClock.startupAnchorLeadSeconds - 1e-6,
            "musical second 0 must not precede renderStart + anchor (\(absoluteLatency * 1000) ms " +
            "measured) — a smaller value means the anchor was not applied to the host origin."
        )
        XCTAssertLessThanOrEqual(
            absoluteLatency, Self.specStartupAnchorRailCapSeconds,
            "first-play ABSOLUTE latency (\(absoluteLatency * 1000) ms) must stay within the owner-locked " +
            "\(Self.specStartupAnchorRailCapSeconds * 1000) ms rail cap. A value near " +
            "\(Self.specLeadSeconds * 1000) ms means the master-clock origin was shifted by the " +
            "look-ahead lead — the lead must be realised by dispatching EARLY, never by the origin."
        )
    }

    /// NEGATIVE CONTROL for invariant A (proves the cap gate is load-bearing,
    /// not vacuously true for any origin): the KNOWN-hollow round-1 mechanism — a
    /// captured origin shifted forward by the LOOK-AHEAD LEAD — DOES exceed the
    /// owner-locked startup-anchor rail cap. Exercised directly on
    /// `AudioMasterClock.captureOrigin(..., leadSeconds:)` (round-1's shipped fix)
    /// with the render-position fallback, so this fails IFF the origin shift is
    /// present. If invariant A's gate ever passed for a lead-shifted origin, this
    /// control would flag the gate as vacuous.
    func test_originShiftedByLead_exceedsStartupAnchorRailCap_negativeControl() {
        // Round-1's mechanism in isolation: capture the origin shifted forward by
        // the lead (fallback branch: no render position).
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { nil })
        let fallback: TimeInterval = 1000.0
        clock.captureOrigin(fallbackHostSeconds: fallback, leadSeconds: Self.specLeadSeconds)

        let firstPlayHostSeconds = clock.hostSeconds(atMusicalSeconds: 0)
        let absoluteLatency = firstPlayHostSeconds - fallback

        XCTAssertGreaterThan(
            absoluteLatency, Self.specStartupAnchorRailCapSeconds,
            "an origin shifted by the look-ahead lead (leadSeconds: \(Self.specLeadSeconds)) must push " +
            "musical second 0 MORE than the \(Self.specStartupAnchorRailCapSeconds * 1000) ms rail cap past " +
            "the origin (measured \(absoluteLatency * 1000) ms) — otherwise invariant A's cap gate is " +
            "vacuous and the lead could masquerade as the startup anchor."
        )
        XCTAssertEqual(
            absoluteLatency, Self.specLeadSeconds, accuracy: 1e-6,
            "the origin shift equals exactly the lead — confirming the shift IS the ~100 ms first-play " +
            "latency the startup anchor (≤ \(Self.specStartupAnchorRailCapSeconds * 1000) ms) must never reach."
        )
    }

    // MARK: - INVARIANT B: leadStampedAudioTime is the LIVE dispatch path

    /// THE LIVE-PATH GATE. Drives a firing track through the REAL production
    /// `start()` + `processTick` and asserts the live `dispatchTick` loop routed
    /// the event's stamp through `leadStampedAudioTime(forMusicalSeconds:
    /// dispatchNow:)` — reported via the `leadStampedAudioTimeDispatchProbeForTesting`
    /// seam — with the configured lead (>= the locked 100 ms).
    ///
    /// Round-1's dispatch loop stamps via `dispatchSampleAudioTime` /
    /// `scheduledAUNoteSampleTime` and NEVER calls `leadStampedAudioTime`, so the
    /// probe stays silent → RED. The builder makes early dispatch the live path
    /// (route every sample/AU stamp through `leadStampedAudioTime` and report it),
    /// after which the probe fires with the lead → GREEN.
    func test_dispatchLoop_invokesLeadStampedAudioTime_withConfiguredLead_GATE() throws {
        let (project, library) = try makeProject(stepsPerBar: 16)
        let sink = CapturingPlaySink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            sampleEngine: sink,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        var probeCalls: [(musicalSeconds: TimeInterval, dispatchNow: TimeInterval, lead: TimeInterval)] = []
        controller.leadStampedAudioTimeDispatchProbeForTesting = { musicalSeconds, dispatchNow, lead in
            probeCalls.append((musicalSeconds, dispatchNow, lead))
        }
        defer { controller.leadStampedAudioTimeDispatchProbeForTesting = nil }

        controller.start()
        defer { controller.stop() }
        // Pump one step so the dispatch loop runs at least once for the firing track.
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.125)

        // Sanity: the dispatch loop actually ran (voices were played). If it did
        // not, the probe-silence below would be a false RED (no dispatch at all).
        XCTAssertGreaterThan(
            sink.playCount, 0,
            "sanity: a firing track must dispatch at least one sample trigger through the live loop"
        )

        XCTAssertFalse(
            probeCalls.isEmpty,
            "the LIVE dispatchTick loop must route each sample/AU event's stamp through " +
            "leadStampedAudioTime(forMusicalSeconds:dispatchNow:) and report it through the " +
            "leadStampedAudioTimeDispatchProbeForTesting seam. The probe never fired — round-1's " +
            "dispatch path stamps via dispatchSampleAudioTime / scheduledAUNoteSampleTime and " +
            "never calls leadStampedAudioTime (the early-dispatch surface is dead in production)."
        )

        // Every live invocation must carry the configured look-ahead lead (>= the
        // locked 100 ms) — a lead-less call (0) is the round-1 knife-edge and
        // leaves the flam. This is the second half of the KNOWN-hollow form the
        // adversarial audit must make RED.
        for call in probeCalls {
            XCTAssertGreaterThanOrEqual(
                call.lead, Self.specLeadSeconds,
                "leadStampedAudioTime must be invoked with the configured look-ahead lead " +
                "(>= \(Self.specLeadSeconds * 1000) ms); the live dispatch reported lead " +
                "\(call.lead * 1000) ms for musicalSeconds=\(call.musicalSeconds). A lead-less call " +
                "means the early-dispatch surface is wired but carries no lead — the flam stands."
            )
        }
    }

    /// NEGATIVE CONTROL for invariant B (proves the probe reflects a REAL live
    /// invocation, not an always-firing hook): with NO probe installed the seam is
    /// a no-op, and — critically — the probe count is driven by the dispatch loop,
    /// not by the test. Here we assert that a controller whose transport is NEVER
    /// started records ZERO probe calls even though a probe IS installed: the
    /// probe only fires from the live dispatch path, so no dispatch ⇒ no calls.
    /// If the probe fired without the dispatch loop, invariant B would be a
    /// tautology.
    func test_noDispatch_probeNeverFires_negativeControl() throws {
        let (project, library) = try makeProject(stepsPerBar: 16)
        let sink = CapturingPlaySink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            sampleEngine: sink,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        var probeCallCount = 0
        controller.leadStampedAudioTimeDispatchProbeForTesting = { _, _, _ in probeCallCount += 1 }
        defer { controller.leadStampedAudioTimeDispatchProbeForTesting = nil }

        // Transport never started, no processTick pumped → the dispatch loop never
        // runs → the probe must never fire, and no voices are played.
        XCTAssertEqual(sink.playCount, 0, "no transport start / tick ⇒ no dispatch")
        XCTAssertEqual(
            probeCallCount, 0,
            "the probe must fire ONLY from the live dispatch loop — with no dispatch it must stay at " +
            "0, otherwise invariant B's live-path assertion would be a tautology."
        )
    }
}
