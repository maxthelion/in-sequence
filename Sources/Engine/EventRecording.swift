import Foundation

// MARK: - Phase 0 event-recording contract (RAIL STUBS — frozen)
//
// This file is the COMPILE-TIME CONTRACT for Phase 0 of
// `docs/plans/2026-06-30-precompute-lookahead-recording.md`:
//
//   "record the realized note stream as it's produced (track, step, pitch,
//    velocity, length, gate, the resolved generative choice) to an in-memory
//    ring + optional NDJSON. A replay source feeds the *same* dispatch path
//    from a recording."
//
//   Executable gate: "record→replay round-trips to a byte-identical event list;
//    the headless capture rig can replay a recording deterministically."
//
// These declarations are intentionally NO-OPS so the rail
// (`Tests/.../EventRecordingRoundTripTests.swift`) COMPILES and runs RED on the
// current code (the feature is not built yet). The BUILDER replaces the bodies
// — the public surface (types, member names, signatures) is the contract the
// frozen rail asserts against and must remain stable. The builder MUST NOT edit
// the rail test file; they implement the bodies below (and may move/extend these
// declarations as long as the rail keeps compiling and passes honestly).

/// One realized note event as it left the generative pipeline for the dispatch
/// path, captured per `(track-block, step)`. Carries the SPEC's required fields
/// — track (block id), step, pitch, velocity, length, gate, and the resolved
/// generative choice (voice tag + per-step slice parameters) — as primitive,
/// `Codable` values so an NDJSON line round-trips byte-identically.
///
/// `NoteEvent` itself is not `Codable`; this is the on-the-wire / on-the-ring
/// form. `noteEvent` rebuilds the exact `NoteEvent` that feeds the dispatch path
/// so a replay is indistinguishable from a live realization.
struct RealizedEvent: Codable, Equatable, Hashable, Sendable {
    /// The generator block whose prepared notes this event belongs to
    /// (`EngineController.generatorBlockID(for:)`), i.e. the track identity on
    /// the dispatch path (`preparedNotesByBlockID` key).
    var blockID: BlockID
    /// The musical step the event was realized for (`upcomingStep`).
    var step: Int
    var pitch: UInt8
    var velocity: UInt8
    var length: UInt16
    var gate: Bool
    /// The resolved generative choice's voice tag (drum lane / voicing tag).
    var voiceTag: String?
    /// The resolved per-step slice parameters, when the realized note is a slice
    /// trigger (part of the resolved generative choice).
    var sliceParameters: SliceTriggerStepParameters?

    init(
        blockID: BlockID,
        step: Int,
        pitch: UInt8,
        velocity: UInt8,
        length: UInt16,
        gate: Bool,
        voiceTag: String?,
        sliceParameters: SliceTriggerStepParameters? = nil
    ) {
        self.blockID = blockID
        self.step = step
        self.pitch = pitch
        self.velocity = velocity
        self.length = length
        self.gate = gate
        self.voiceTag = voiceTag
        self.sliceParameters = sliceParameters
    }

    /// Build a `RealizedEvent` from a realized `NoteEvent` on the dispatch path.
    init(blockID: BlockID, step: Int, noteEvent: NoteEvent) {
        self.init(
            blockID: blockID,
            step: step,
            pitch: noteEvent.pitch,
            velocity: noteEvent.velocity,
            length: noteEvent.length,
            gate: noteEvent.gate,
            voiceTag: noteEvent.voiceTag,
            sliceParameters: noteEvent.sliceParameters
        )
    }

    /// Reconstruct the exact `NoteEvent` that feeds the dispatch path, so a
    /// replay source produces a byte-identical realized event list.
    var noteEvent: NoteEvent {
        NoteEvent(
            pitch: pitch,
            velocity: velocity,
            length: length,
            gate: gate,
            voiceTag: voiceTag,
            sliceParameters: sliceParameters
        )
    }
}

/// Records the realized note stream into a bounded in-memory ring and serializes
/// it to NDJSON (one `RealizedEvent` JSON object per line). The recorder sink is
/// fed from `EngineController.prepareTick` where each realized `GeneratedNote` →
/// `NoteEvent` is prepared for the dispatch path.
///
/// STUB: a no-op recorder so the rail compiles and runs RED. The builder
/// implements the ring + NDJSON serialization.
final class EventRecorder {
    /// Maximum events retained in the in-memory ring.
    let capacity: Int

    init(capacity: Int = 8192) {
        self.capacity = capacity
    }

    /// The events recorded so far, in realization order.
    /// STUB: always empty until the builder implements recording.
    var recordedEvents: [RealizedEvent] { [] }

    /// Record one realized event as it is prepared for the dispatch path.
    /// STUB: no-op.
    func record(_ event: RealizedEvent) {
        _ = event
    }

    /// Record all realized note events for a single `(block, step)` slice of the
    /// prepared dispatch map (`preparedNotesByBlockID`).
    /// STUB: no-op.
    func record(blockID: BlockID, step: Int, notes: [NoteEvent]) {
        _ = (blockID, step, notes)
    }

    /// Serialize the recorded stream to NDJSON (one `RealizedEvent` per line),
    /// the optional on-disk form named in the spec.
    /// STUB: returns empty.
    func serializedNDJSON() -> String {
        ""
    }
}

/// Replays a recording into the SAME dispatch path the live engine uses:
/// `preparedNotesByBlockID(forStep:)` returns the `[BlockID: [NoteEvent]]` map
/// the executor consumes, reconstructed from the recorded `RealizedEvent`s so
/// the realized event list is byte-identical to the live run.
///
/// STUB: an empty replay source so the rail compiles and runs RED. The builder
/// implements decoding + per-step grouping.
struct EventReplaySource {
    /// The events this source will replay, in realization order.
    /// STUB: always empty.
    private let events: [RealizedEvent]

    /// Build a replay source from an in-memory recording.
    /// STUB: drops the events (no-op) so replay produces nothing.
    init(events: [RealizedEvent]) {
        _ = events
        self.events = []
    }

    /// Build a replay source from a serialized NDJSON recording.
    /// STUB: parses nothing.
    init(ndjson: String) {
        _ = ndjson
        self.events = []
    }

    /// All recorded events this source will replay, in order.
    /// STUB: always empty.
    var recordedEvents: [RealizedEvent] { events }

    /// The prepared-notes map for one step, keyed by block id exactly as the
    /// live engine hands it to the executor (`preparedNotesByBlockID`). Feeding
    /// this into the dispatch path replays the recording deterministically.
    /// STUB: returns empty.
    func preparedNotesByBlockID(forStep step: Int) -> [BlockID: [NoteEvent]] {
        _ = step
        return [:]
    }
}
