import Foundation

struct ScheduledEvent: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case trackAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
        case routedAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
        case routedMIDI(destination: Destination, channel: UInt8, notes: [NoteEvent], bpm: Double)
        case chordContextBroadcast(lane: String, chord: Chord)
        /// `mixLevel` is `track.mix.level` (linear, [0, 1]) snapshotted at enqueue time.
        /// Baked into the payload rather than looked up at dispatch so fader state doesn't
        /// require a second lock round-trip per trigger; the trade-off is that fader moves
        /// during an in-flight sample don't take effect until the next trigger — acceptable
        /// for drum one-shots. Per-track mixer nodes (for live fader rides + pan) are a
        /// follow-up.
        case sampleTrigger(trackID: UUID, sampleID: UUID, settings: SamplerSettings, mixLevel: Double, scheduledHostTime: TimeInterval)
    }

    let scheduledHostTime: TimeInterval
    let payload: Payload
}
