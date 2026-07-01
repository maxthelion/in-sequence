import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER work-product (NOT a frozen rail) for the P3/P1 prosecutor charge:
///
///   "Cold-start fallback: MIDI-out events get the +100 ms look-ahead lead while
///    AU and sample go immediate — first-play MIDI-vs-audio flam."
///   (EngineController.swift:2310-2312 + AudioMasterClock.swift fallback branch)
///
/// The cold-start AU-vs-drum flam fix (`ColdStartFallbackFlamVerifierTests`) gates
/// BOTH audio paths on `hasRenderOrigin`:
///   - `dispatchSampleAudioTime(for:)` returns nil  (EngineController.swift:600-606)
///   - `scheduledAUNoteSampleTime(for:)` returns nil (EngineController.swift:629)
/// so in the pre-render fallback window both schedule IMMEDIATE (no lead) and stay
/// aligned with each other. GOOD — that is what the audio verifier proves.
///
/// BUT the direct-MIDI-out path is NOT gated. The `resolveNow` closure at
/// `EngineController.swift:2310-2312` calls `audioMasterClock.hostSeconds(atMusicalSeconds:)`
/// UNCONDITIONALLY:
///
///     resolveNow: { [audioMasterClock] bpm in
///         let musicalSeconds = audioMasterClock.advance(toStep: upcomingStep, bpm: bpm)
///         return audioMasterClock.hostSeconds(atMusicalSeconds: musicalSeconds)
///     }
///
/// In the fallback branch `captureOrigin` sets
/// `originHostSeconds = fallbackHostSeconds + lead` (AudioMasterClock.swift:165), so
/// `hostSeconds(atMusicalSeconds: m)` returns `fallback + lead + m` EVEN WHEN
/// `hasRenderOrigin` is false. A direct-MIDI track's first-bar events are therefore
/// stamped ~100 ms in the future while the AU and sample voices on the SAME step
/// play immediate — a ~100 ms MIDI-vs-audio onset split on first play in the cold
/// window. That contradicts the Gate-1 first-play criterion (AU AND drum/MIDI within
/// 10 ms of the grid).
///
/// `ColdStartFallbackFlamVerifierTests` only models the two AUDIO paths and never
/// exercises the MIDI host-seconds path, so it cannot catch this. This file drives
/// all three paths exactly as `prepareTick`'s dispatch does in the cold fallback and
/// measures the MIDI-vs-audio split.
final class ColdStartFallbackMIDIFlamVerifierTests: XCTestCase {

    private static let specLeadSeconds: TimeInterval = AudioMasterClock.lookAheadLeadSeconds

    func test_coldStartFallback_midiVsAudioOnsetSplit() {
        // Live cold start: engine not yet rendering, render position never appears
        // before the first dispatch (the live cold-start window the offline rails
        // never take — offline manual rendering always has a render position).
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { nil })

        // Transport start in LIVE mode passes the locked look-ahead lead.
        let fallbackHost: TimeInterval = 1_000.0
        clock.captureOrigin(fallbackHostSeconds: fallbackHost, leadSeconds: Self.specLeadSeconds)

        // The dispatch pump fires around transport start.
        let dispatchNow = fallbackHost

        // Step 0, first event of the first bar. Record the musical position via the
        // SAME tempo-map advance the dispatch uses.
        let upcomingStep: UInt64 = 0
        let bpm: Double = 120.0
        let musicalSeconds = clock.advance(toStep: upcomingStep, bpm: bpm)

        // --- MIDI-OUT path (EngineController.swift:2310-2312, `resolveNow`) ---
        // UNCONDITIONAL — no `hasRenderOrigin` gate. This is exactly the closure
        // body the executor invokes to stamp a direct-MIDI-out block's MIDITimeStamp.
        let midiStampHostSeconds = clock.hostSeconds(atMusicalSeconds: musicalSeconds)
        let midiOnsetRelativeToDispatch = midiStampHostSeconds - dispatchNow

        // --- SAMPLE path (EngineController.dispatchSampleAudioTime) ---
        // Gated on hasRenderOrigin → nil in the cold fallback → immediate (no lead).
        let sampleAudioTime: AVAudioTime? = clock.hasRenderOrigin
            ? clock.audioTime(atMusicalSeconds: max(0, musicalSeconds))
            : nil
        let sampleOnsetRelativeToDispatch: TimeInterval = sampleAudioTime
            .map { AVAudioTime.seconds(forHostTime: $0.hostTime) - dispatchNow } ?? 0.0

        // --- AU path (EngineController.scheduledAUNoteSampleTime) ---
        // Gated on hasRenderOrigin → nil in the cold fallback → AUEventSampleTimeImmediate.
        let auHasSampleStamp = clock.hasRenderOrigin
        let auOnsetRelativeToDispatch: TimeInterval = auHasSampleStamp
            ? (midiStampHostSeconds - dispatchNow)
            : 0.0

        let midiVsSampleSplit = abs(midiOnsetRelativeToDispatch - sampleOnsetRelativeToDispatch)
        let midiVsAUSplit = abs(midiOnsetRelativeToDispatch - auOnsetRelativeToDispatch)

        print("[cold-start-fallback-midi] isRenderDerived=\(clock.capturedOriginCorrelation().isRenderDerived) " +
              "midiOnset=+\(midiOnsetRelativeToDispatch * 1000)ms " +
              "sampleOnset=+\(sampleOnsetRelativeToDispatch * 1000)ms " +
              "auOnset=+\(auOnsetRelativeToDispatch * 1000)ms " +
              "midiVsSampleSplit=\(midiVsSampleSplit * 1000)ms " +
              "midiVsAUSplit=\(midiVsAUSplit * 1000)ms")

        // Gate-1 first-play criterion: AU AND drum/MIDI must all be within 10 ms of
        // each other (on the grid). If the charge is REAL, the MIDI path got +lead
        // (~100 ms) while AU + sample went immediate, so the split ≈ lead and this
        // fails.
        XCTAssertLessThan(
            midiVsAUSplit, 0.010,
            "Cold-start fallback: MIDI-out onset is +\(midiOnsetRelativeToDispatch * 1000) ms " +
            "(hostSeconds path got the look-ahead lead, UNGATED) but the AU onset is " +
            "+\(auOnsetRelativeToDispatch * 1000) ms (scheduledAUNoteSampleTime returned nil → " +
            "immediate). That is a \(midiVsAUSplit * 1000) ms MIDI-vs-AU first-play flam."
        )
        XCTAssertLessThan(
            midiVsSampleSplit, 0.010,
            "Cold-start fallback: MIDI-out onset is +\(midiOnsetRelativeToDispatch * 1000) ms " +
            "but the sample onset is +\(sampleOnsetRelativeToDispatch * 1000) ms (immediate). " +
            "That is a \(midiVsSampleSplit * 1000) ms MIDI-vs-sample first-play flam."
        )
    }
}
