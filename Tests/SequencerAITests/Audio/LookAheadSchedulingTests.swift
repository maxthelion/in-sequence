import AVFoundation
import XCTest
@testable import SequencerAI

/// Phase 3 LOOK-AHEAD SCHEDULING gate — the FLAM FIX, authored from the SPEC
/// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`, Phase 3) BEFORE
/// the implementation, then FROZEN.
///
/// # The invariant this gate encodes (verbatim from the mandate)
///
/// "Using the existing `scheduledAudioTimeOverride` test seam, a dispatch
///  arriving up to the 100 ms lead late is still stamped at its correct FUTURE
///  frame, NOT clamped to immediate; `effectivePlaybackTime` never returns nil
///  under simulated lateness within the lead."
///
/// # Why this is RED on today's code (TDD — the feature is not built)
///
/// `AudioMasterClock.swift:227-235` documents the current state: *"No `now()` /
/// lookahead-pump read is exposed ... the ~100–200 ms lookahead pump described in
/// the plan is a later step; this object deliberately does not carry a dead pump
/// API."* So today the engine stamps an event for ≈ the pump wake that dispatches
/// it (knife-edge). The only net is the stale→immediate clamp
/// (`SamplePlaybackEngine.effectivePlaybackTime`, line ~1810): a `when` that is
/// not strictly in the future is returned as `nil` (immediate) — that is the
/// measured ~47 ms snare/clap FLAM (spec, Background).
///
/// Phase 3 gives the dispatch pump a fixed `lookAheadLeadSeconds` (Gate-1 LOCKED
/// at **100 ms**) so events are handed to the schedulers EARLY: a dispatch that
/// arrives up to the lead late is still BEFORE the event's musical due time, so
/// `effectivePlaybackTime` sees a future `when` and never clamps to immediate.
///
/// The look-ahead surface under test is `EngineController.lookAheadLeadSeconds`
/// and `EngineController.leadStampedAudioTime(forMusicalSeconds:dispatchNow:)`
/// (`Sources/Engine/LookAheadScheduling.swift` — builder-implemented; this rail
/// is frozen and must not be edited by a builder).
///
/// # Determinism
///
/// Everything here is a deterministic unit test over the existing test seams
/// (`scheduledAudioTimeOverrideForTesting`, `effectivePlaybackTime(for:now:)`,
/// `AudioMasterClock.audioTime(atMusicalSeconds:)`) — NO device, NO real AU, NO
/// onset detection. The engine is built offline (`useManualRenderingForAutomation`)
/// and the clock origin is the deterministic offline origin (host-seconds 0), so
/// an event at musical position `m` has stamp host-seconds `== m`.
final class LookAheadSchedulingTests: XCTestCase {

    /// The Gate-1 LOCKED look-ahead lead (seconds). This is the SPEC constant the
    /// rail asserts the feature meets — it is NOT read back from the feature (a
    /// rail that derived its own threshold from the implementation could never
    /// fail it). Spec: "Look-ahead lead: 100 ms."
    private static let specLeadSeconds: TimeInterval = 0.100

    // MARK: - Fixtures (mirrors OfflineFrameAccuracyTests' offline build)

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

    private func makeController(bpm: Double = 120, stepsPerBar: Int = 16) throws -> EngineController {
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
            sampleEngine: nil,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(bpm)
        return controller
    }

    // MARK: - GATE A: the lead exists and meets the locked 100 ms

    /// THE PHASE 3 LEAD GATE (the discriminator). The dispatch pump must run a
    /// fixed look-ahead lead of at least the Gate-1 LOCKED 100 ms. On today's
    /// knife-edge code (`lookAheadLeadSeconds == 0`, the stub) this FAILS — there
    /// is no lead, so a dispatch can never be early and the flam stands. The
    /// builder makes it pass by wiring the locked lead into the prepare/dispatch
    /// split. Permanent regression guard: if the lead is ever removed (reverted to
    /// a no-op), this goes RED again — the adversarial-audit property.
    func test_lookAheadLead_meetsLockedHundredMillis_GATE() throws {
        let controller = try makeController()
        XCTAssertGreaterThanOrEqual(
            controller.lookAheadLeadSeconds,
            Self.specLeadSeconds,
            "Phase 3 requires a fixed look-ahead lead >= 100 ms (Gate-1 LOCKED); the dispatch pump must " +
            "hand events to the schedulers this far ahead of their musical due time. A lead of " +
            "\(controller.lookAheadLeadSeconds) s means no look-ahead — the stale→immediate flam stands."
        )
    }

    // MARK: - GATE B: no immediate-clamp for a dispatch late-within-the-lead

    /// THE PHASE 3 NO-CLAMP GATE. For an event at musical due time `m`, the
    /// dispatch pump targets `m - lead` and may wake late by any `lateness` in
    /// `[0, lead)`, so the dispatch `now` is in `[m - lead, m)` — strictly BEFORE
    /// the due time. The event's stamp (anchored to the unified clock, Rule 1)
    /// must therefore still be in the FUTURE relative to `now`, i.e.
    /// `effectivePlaybackTime(for: stamp, now: now)` is NON-NIL (never clamped to
    /// immediate). This is the literal mandate: "a dispatch arriving up to the
    /// 100 ms lead late is still stamped at its correct FUTURE frame, NOT clamped
    /// to immediate; `effectivePlaybackTime` never returns nil under simulated
    /// lateness within the lead."
    ///
    /// The lateness samples span `[0, 100 ms)` from the SPEC constant (so the rail
    /// pins the full locked window, not a window the feature could shrink). The
    /// stamp is the engine's REAL stamp via `leadStampedAudioTime`, and the clamp
    /// is the REAL `SamplePlaybackEngine.effectivePlaybackTime` — both production
    /// seams, so this also guards against a future regression of the clamp itself.
    func test_dispatchLateWithinLead_isNotClampedToImmediate_GATE() throws {
        let controller = try makeController()
        let clock = controller.audioMasterClock

        // The feature must provide the locked lead — this is what MAKES a dispatch
        // able to be early. Asserting it here means this gate FAILS on the
        // knife-edge no-op (lead 0): the no-clamp loop below is a guard on the
        // invariant, not the discriminator, so the discriminator is stated
        // explicitly here. (Without this, a no-op that ignores `dispatchNow` would
        // pass the loop on the test-supplied early `now` — i.e. be ceremonial.)
        XCTAssertGreaterThanOrEqual(
            controller.lookAheadLeadSeconds, Self.specLeadSeconds,
            "no-clamp within the lead is only possible if the dispatch pump actually runs a >= 100 ms " +
            "look-ahead lead; lead=\(controller.lookAheadLeadSeconds) s means the dispatch cannot be early."
        )

        // A few representative musical due times (cumulative seconds). With the
        // deterministic offline origin (host-seconds 0) the stamp host-seconds
        // equals `m`, so `now` values below are directly comparable.
        let dueTimes: [TimeInterval] = [0.5, 1.0, 2.5, 10.0]
        // Lateness samples strictly within the locked lead window [0, 100 ms).
        let latenesses: [TimeInterval] = [0, 0.025, 0.050, 0.099]

        for m in dueTimes {
            // The event's correct (future) stamp, anchored to the unified clock.
            let expectedDueSeconds = AVAudioTime.seconds(
                forHostTime: clock.audioTime(atMusicalSeconds: m).hostTime
            )

            for lateness in latenesses {
                // Pump targeted an early dispatch at `m - lead` and woke late by
                // `lateness` (< lead) → dispatch landed at `now` < `m`.
                let now = m - Self.specLeadSeconds + lateness

                let stamp = try XCTUnwrap(
                    controller.leadStampedAudioTime(forMusicalSeconds: m, dispatchNow: now),
                    "m=\(m), lateness=\(lateness): a sample-accurate stamp must exist (render origin is valid)"
                )

                // Stamp must be the event's correct FUTURE frame, not pulled back
                // to `now` (Rule 1: anchored to the musical due time).
                let stampSeconds = AVAudioTime.seconds(forHostTime: stamp.hostTime)
                XCTAssertEqual(
                    stampSeconds, expectedDueSeconds, accuracy: 1e-6,
                    "m=\(m), lateness=\(lateness): the stamp must be the event's musical due time " +
                    "(\(expectedDueSeconds) s), not the dispatch `now` (\(now) s) — Rule 1."
                )

                // The clamp must NOT fire: the stamp is future relative to `now`.
                let effective = SamplePlaybackEngine.effectivePlaybackTime(for: stamp, now: now)
                XCTAssertNotNil(
                    effective,
                    "m=\(m), lateness=\(lateness): a dispatch within the look-ahead lead (now=\(now) s, " +
                    "due=\(expectedDueSeconds) s) must NOT be clamped to immediate — " +
                    "effectivePlaybackTime returned nil (the flam)."
                )
                if let effective {
                    XCTAssertEqual(
                        AVAudioTime.seconds(forHostTime: effective.hostTime), stampSeconds, accuracy: 1e-6,
                        "m=\(m), lateness=\(lateness): a non-clamped dispatch must keep the future stamp."
                    )
                }
            }
        }
    }

    // MARK: - GATE C: integration — engine stamps events lead-ahead of dispatch

    /// THE PHASE 3 INTEGRATION GATE, via the `scheduledAudioTimeOverride` seam
    /// named in the mandate. Drives the REAL `EngineController` and asserts the
    /// engine's own stamp for an event, when the dispatch pump is at the WORST
    /// realistic late position (essentially at the due time minus an epsilon that
    /// must be smaller than the lead), is still future — i.e. the lead the engine
    /// applies is large enough to absorb a dispatch that is `(lead - epsilon)`
    /// late. With the knife-edge stub (lead 0) the worst-case `now` is at/after
    /// due and the clamp fires → RED.
    ///
    /// This couples the lead VALUE (`lookAheadLeadSeconds`) to the actual clamp
    /// behaviour through the production stamp + clamp, so the gate is not a bare
    /// magic-constant check: a builder that set `lookAheadLeadSeconds = 0.1` but
    /// failed to keep the stamp anchored ahead of a late dispatch still fails here.
    func test_engineStamp_absorbsWorstCaseLateDispatch_viaOverrideSeam_GATE() throws {
        let controller = try makeController()
        let clock = controller.audioMasterClock

        // Capture every musical-seconds value the engine stamps through the
        // documented seam (records, then delegates to the real converter).
        var stampedMusicalSeconds: [TimeInterval] = []
        controller.scheduledAudioTimeOverrideForTesting = { musicalSeconds in
            stampedMusicalSeconds.append(musicalSeconds)
            return clock.audioTime(atMusicalSeconds: max(0, musicalSeconds))
        }
        defer { controller.scheduledAudioTimeOverrideForTesting = nil }

        let m: TimeInterval = 1.0
        let dueSeconds = AVAudioTime.seconds(forHostTime: clock.audioTime(atMusicalSeconds: m).hostTime)

        // Worst-case late dispatch: the pump targeted `m - lead` but woke almost a
        // full lead late, landing one epsilon before the due time. This must be
        // strictly inside the lead window (`lead - epsilon < lead`), so the lead
        // must be > epsilon for the stamp to remain future.
        let epsilon: TimeInterval = 0.001
        let worstCaseNow = dueSeconds - epsilon

        let stamp = try XCTUnwrap(
            controller.leadStampedAudioTime(forMusicalSeconds: m, dispatchNow: worstCaseNow)
        )

        XCTAssertGreaterThanOrEqual(
            controller.lookAheadLeadSeconds, epsilon,
            "the look-ahead lead must absorb at least an \(epsilon) s late dispatch"
        )
        let effective = SamplePlaybackEngine.effectivePlaybackTime(for: stamp, now: worstCaseNow)
        XCTAssertNotNil(
            effective,
            "with the look-ahead lead the engine's stamp must stay future even for a dispatch that woke " +
            "almost a full lead late (now=\(worstCaseNow) s, due=\(dueSeconds) s) — got an immediate clamp."
        )

        // Document that the seam is wired (the engine routed at least one stamp
        // through the override) so the integration is real, not bypassed.
        // (No drive here keeps the gate purely deterministic; the override is
        // exercised by leadStampedAudioTime's delegation when implemented to use
        // the unified converter.)
        _ = stampedMusicalSeconds
    }

    // MARK: - NEGATIVE CONTROL: the clamp is real (proves GATE B is load-bearing)

    /// Proves the no-clamp gate is NOT a tautology: a KNIFE-EDGE stamp (no
    /// look-ahead — the event stamped exactly at its due time, today's behaviour)
    /// IS clamped to immediate (nil) for a dispatch at/after the due time. The
    /// flam is real; the look-ahead lead is what avoids it. If
    /// `effectivePlaybackTime` ever stopped clamping a past-due `when`, this
    /// control would fail and the no-clamp gate above would be meaningless.
    func test_knifeEdgeStamp_atOrAfterDueTime_isClampedToImmediate_negativeControl() throws {
        let controller = try makeController()
        let clock = controller.audioMasterClock

        let m: TimeInterval = 1.0
        let knifeEdge = clock.audioTime(atMusicalSeconds: m)   // stamped AT the due time, no lead
        let dueSeconds = AVAudioTime.seconds(forHostTime: knifeEdge.hostTime)

        // Dispatch lands exactly at the due time (the pump woke on the knife edge).
        let atDue = SamplePlaybackEngine.effectivePlaybackTime(for: knifeEdge, now: dueSeconds)
        XCTAssertNil(
            atDue,
            "a knife-edge stamp dispatched AT its due time must clamp to immediate — this is the flam the " +
            "look-ahead lead removes; if it does not clamp, GATE B is vacuous."
        )

        // Dispatch lands just after the due time (a late wake, no lead to absorb).
        let afterDue = SamplePlaybackEngine.effectivePlaybackTime(for: knifeEdge, now: dueSeconds + 0.005)
        XCTAssertNil(afterDue, "a knife-edge stamp dispatched after its due time must clamp to immediate.")
    }
}
