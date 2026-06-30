import Foundation

// MARK: - Phase 2 off-thread bar-precompute contract (RAIL STUBS — frozen)
//
// This file is the COMPILE-TIME CONTRACT for Phase 2 of
// `docs/plans/2026-06-30-precompute-lookahead-recording.md`:
//
//   "extend the prepare horizon from 1 step to 1 bar ... and move generative
//    evaluation to a background queue. Publish the precomputed bar's notes
//    (tempo-independent) via the existing snapshot lock-swap. ... Immediate
//    controls (mute/fill/macro/velocity) stay applied at dispatch."
//
//   Executable gate: "realtime-path-lint shows no RNG/alloc on the tick path; a
//    recorded run *with* precompute == a recorded run *without* (same notes —
//    equivalence)."
//
// These declarations are intentionally a NO-OP so the rail
// (`Tests/.../PrecomputeBarEquivalenceTests.swift`) COMPILES and runs RED on the
// current code (the feature is not built yet). The BUILDER replaces the bodies —
// the public surface (types, member names, signatures) is the contract the
// frozen rail asserts against and must remain stable. The builder MUST NOT edit
// the rail test file; they implement the bodies below (and may move/extend these
// declarations as long as the rail keeps compiling and passes honestly).
//
// # Why a precompute SEAM, not the live generator, is the contract
//
// Today generation runs LIVE on the tick path: `EngineController.prepareTick`
// evaluates each step with a fresh `SystemRandomNumberGenerator()` per track per
// tick (`EngineController:2110`). Phase 2 moves that whole evaluation OFF the
// tick path: a bar's worth of steps is generated up-front (on a background
// queue) into a `PrecomputedBar`, which the tick path then merely CONSUMES (a
// dictionary read — no RNG, no generator evaluation). The equivalence gate pins
// that the precomputed bar carries the SAME notes the live per-step evaluation
// would produce for the same inputs.

/// A bar's worth of pre-generated notes, keyed by output step → block id →
/// notes, exactly the shape the tick path hands to the executor
/// (`preparedNotesByBlockID`). The tick path consumes this with a pure
/// dictionary read — NO RNG, NO generator evaluation, NO allocation of the
/// generative pipeline on the realtime path. Building it is Phase 2's whole
/// point: generation moved off the tick.
struct PrecomputedBar: Equatable, Sendable {
    /// The first output step (inclusive) this bar covers.
    let startStep: Int
    /// Number of output steps this bar covers (the prepare horizon — one bar).
    let stepCount: Int

    /// The pre-generated dispatch map per output step, byte-identical to what a
    /// live per-step evaluation would have produced. Keyed by output step, then
    /// by generator block id (`EngineController.generatorBlockID(for:)`).
    private let notesByStep: [Int: [BlockID: [NoteEvent]]]

    init(
        startStep: Int,
        stepCount: Int,
        notesByStep: [Int: [BlockID: [NoteEvent]]]
    ) {
        self.startStep = startStep
        self.stepCount = stepCount
        self.notesByStep = notesByStep
    }

    /// An empty precomputed bar (covers no steps). This is what a no-op /
    /// not-yet-implemented precompute produces — the adversarial-audit baseline.
    static func empty(startStep: Int = 0, stepCount: Int = 0) -> PrecomputedBar {
        PrecomputedBar(startStep: startStep, stepCount: stepCount, notesByStep: [:])
    }

    /// The prepared-notes dispatch map for one output step, keyed by block id —
    /// exactly what the live engine hands the executor
    /// (`preparedNotesByBlockID`). The tick path reads this instead of
    /// evaluating the generator live. A step outside the bar yields an empty
    /// map (no spurious triggers).
    ///
    /// Reading the same step twice MUST return the same map (a precomputed bar
    /// is immutable on the tick path — consumption does no RNG/generation).
    func preparedNotesByBlockID(forStep step: Int) -> [BlockID: [NoteEvent]] {
        notesByStep[step] ?? [:]
    }
}

/// Generates a whole bar of notes OFF the realtime tick path (on a background
/// queue) so the tick path only consumes a `PrecomputedBar`. This is the seam
/// the spec moves `GeneratedSourceEvaluator` evaluation into
/// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`, Phase 2, call
/// sites).
///
/// STUB: returns an empty bar so the rail compiles and runs RED. The builder
/// implements the real per-step evaluation (in step order, threading the
/// `GeneratedSourceEvaluationState` across the bar exactly as the live tick
/// path does) so that a precomputed run == a live run (same notes).
enum BarPrecomputeEvaluator {

    /// Precompute one bar of generated notes for the given tracks.
    ///
    /// Contract (what the frozen rail asserts):
    /// - Evaluates output steps `startStep ..< startStep + stepCount` IN ORDER,
    ///   threading each track's `GeneratedSourceEvaluationState` across the bar
    ///   (so Markov / last-pitch generators match a live sequential run).
    /// - For each step it produces the SAME notes the live tick path would
    ///   (`EngineController.resolvedStepNotes`) given the SAME per-step RNG seed
    ///   from `seedForStep`. The result is keyed by the track's generator block
    ///   id (`blockIDForTrack`), byte-identical to `preparedNotesByBlockID`.
    /// - Runs entirely off the tick path (no realtime constraints here); the
    ///   tick path later only reads `PrecomputedBar.preparedNotesByBlockID`.
    ///
    /// - Parameters:
    ///   - snapshot: the compiled playback snapshot (generation inputs).
    ///   - phraseID: the active phrase the bar belongs to.
    ///   - trackIDs: the tracks to generate, in iteration order.
    ///   - blockIDForTrack: maps a track id to its generator block id (the
    ///     dispatch-map key); mirrors `EngineController.generatorBlockID(for:)`.
    ///   - startStep: first output step of the bar (inclusive).
    ///   - stepCount: number of output steps in the bar (the prepare horizon).
    ///   - chordContext: the harmonic-sidechain chord for the bar, if any.
    ///   - seedForStep: a deterministic per-step RNG seed. The live tick path
    ///     uses a fresh RNG per (track, step); the precompute MUST reproduce the
    ///     SAME stream, so the test injects a deterministic seed per step and
    ///     the builder must seed each step's evaluation identically.
    /// - Returns: a `PrecomputedBar` the tick path can consume without any RNG.
    static func precompute(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackIDs: [UUID],
        blockIDForTrack: (UUID) -> BlockID,
        startStep: Int,
        stepCount: Int,
        chordContext: Chord?,
        seedForStep: (Int) -> UInt64
    ) -> PrecomputedBar {
        // Evaluate the whole bar OFF the realtime tick path, exactly mirroring the
        // live per-step evaluation in `EngineController.prepareTick`:
        // - one `GeneratedSourceEvaluationState` per track, threaded across the bar
        //   IN STEP ORDER (so last-pitch / Markov generators reproduce a live run);
        // - a FRESH per-step RNG, seeded deterministically from `seedForStep` so the
        //   precomputed stream is byte-identical to the live one for the same inputs;
        // - the resulting `GeneratedNote`s mapped to `NoteEvent`s via
        //   `EngineController.noteEvent(from:)`, keyed by the track's generator block id.
        //
        // The result is consumed by the tick path with a pure dictionary read (no RNG,
        // no generator evaluation, no generative allocation on the realtime path).

        // Per-track evaluation state, threaded across the whole bar in step order.
        var stateByTrack: [UUID: GeneratedSourceEvaluationState] = [:]
        for trackID in trackIDs {
            stateByTrack[trackID] = GeneratedSourceEvaluationState()
        }

        var notesByStep: [Int: [BlockID: [NoteEvent]]] = [:]
        for step in startStep..<(startStep + stepCount) {
            var perStep: [BlockID: [NoteEvent]] = [:]
            for trackID in trackIDs {
                // Fresh per-step RNG, seeded identically to the live tick path's
                // per-(track, step) RNG via the injected deterministic seed.
                var rng = PrecomputeSplitMix64(seed: seedForStep(step))
                var state = stateByTrack[trackID] ?? GeneratedSourceEvaluationState()
                let notes = EngineController.resolvedStepNotes(
                    for: trackID,
                    in: snapshot,
                    phraseID: phraseID,
                    stepIndex: step,
                    chordContext: chordContext,
                    state: &state,
                    rng: &rng
                )
                stateByTrack[trackID] = state
                let events = notes.map(EngineController.noteEvent(from:))
                if !events.isEmpty {
                    perStep[blockIDForTrack(trackID)] = events
                }
            }
            if !perStep.isEmpty {
                notesByStep[step] = perStep
            }
        }

        return PrecomputedBar(
            startStep: startStep,
            stepCount: stepCount,
            notesByStep: notesByStep
        )
    }
}

/// A deterministic splitmix64 RNG used to seed off-thread bar precompute so the
/// precomputed stream is byte-identical to a live per-step evaluation seeded with
/// the same per-step seed. (Same algorithm and constants as the seeded RNG the
/// equivalence rail injects into the live reference route.)
private struct PrecomputeSplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
