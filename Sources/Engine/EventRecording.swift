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

/// A deterministic NDJSON codec for `RealizedEvent`, shared by the recorder and
/// the replay source so record→replay→re-record reproduces byte-identical bytes.
///
/// `JSONEncoder.OutputFormatting.sortedKeys` pins object key order, so a given
/// `RealizedEvent` always serializes to the same line regardless of dictionary
/// hashing — the property the round-trip gate asserts.
enum RealizedEventNDJSON {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    /// Serialize a stream to NDJSON (one `RealizedEvent` JSON object per line).
    /// A non-empty stream yields a non-empty, newline-terminated string; an empty
    /// stream yields the empty string.
    static func serialize(_ events: [RealizedEvent]) -> String {
        guard !events.isEmpty else { return "" }
        var output = ""
        for event in events {
            guard let data = try? encoder.encode(event),
                  let line = String(data: data, encoding: .utf8) else {
                continue
            }
            output += line
            output += "\n"
        }
        return output
    }

    /// Parse an NDJSON recording back into a realized stream, preserving line
    /// (realization) order. Blank lines are skipped.
    static func parse(_ ndjson: String) -> [RealizedEvent] {
        guard !ndjson.isEmpty else { return [] }
        var events: [RealizedEvent] = []
        ndjson.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let event = try? decoder.decode(RealizedEvent.self, from: data) else {
                return
            }
            events.append(event)
        }
        return events
    }
}

/// Records the realized note stream into a bounded in-memory ring and serializes
/// it to NDJSON (one `RealizedEvent` JSON object per line). The recorder sink is
/// fed from `EngineController.prepareTick` where each realized `GeneratedNote` →
/// `NoteEvent` is prepared for the dispatch path.
final class EventRecorder {
    /// Maximum events retained in the in-memory ring.
    let capacity: Int

    /// The in-memory ring, oldest-first. Capped at `capacity`; recording past the
    /// cap drops the oldest events.
    private var ring: [RealizedEvent] = []

    init(capacity: Int = 8192) {
        self.capacity = capacity
    }

    /// The events recorded so far, in realization order.
    var recordedEvents: [RealizedEvent] { ring }

    /// Record one realized event as it is prepared for the dispatch path.
    func record(_ event: RealizedEvent) {
        ring.append(event)
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
    }

    /// Record all realized note events for a single `(block, step)` slice of the
    /// prepared dispatch map (`preparedNotesByBlockID`), in order.
    func record(blockID: BlockID, step: Int, notes: [NoteEvent]) {
        for note in notes {
            record(RealizedEvent(blockID: blockID, step: step, noteEvent: note))
        }
    }

    /// Serialize the recorded stream to NDJSON (one `RealizedEvent` per line),
    /// the optional on-disk form named in the spec.
    func serializedNDJSON() -> String {
        RealizedEventNDJSON.serialize(ring)
    }
}

/// Replays a recording into the SAME dispatch path the live engine uses:
/// `preparedNotesByBlockID(forStep:)` returns the `[BlockID: [NoteEvent]]` map
/// the executor consumes, reconstructed from the recorded `RealizedEvent`s so
/// the realized event list is byte-identical to the live run.
struct EventReplaySource {
    /// The events this source will replay, in realization order.
    private let events: [RealizedEvent]

    /// Build a replay source from an in-memory recording, preserving order.
    init(events: [RealizedEvent]) {
        self.events = events
    }

    /// Build a replay source from a serialized NDJSON recording.
    init(ndjson: String) {
        self.events = RealizedEventNDJSON.parse(ndjson)
    }

    /// All recorded events this source will replay, in order.
    var recordedEvents: [RealizedEvent] { events }

    /// The prepared-notes map for one step, keyed by block id exactly as the
    /// live engine hands it to the executor (`preparedNotesByBlockID`). Feeding
    /// this into the dispatch path replays the recording deterministically.
    func preparedNotesByBlockID(forStep step: Int) -> [BlockID: [NoteEvent]] {
        var map: [BlockID: [NoteEvent]] = [:]
        for event in events where event.step == step {
            map[event.blockID, default: []].append(event.noteEvent)
        }
        return map
    }
}
