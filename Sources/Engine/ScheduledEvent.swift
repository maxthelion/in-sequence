import Foundation

struct ScheduledEvent: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case trackAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
        case routedAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
        case routedMIDI(destination: Destination, channel: UInt8, notes: [NoteEvent], bpm: Double)
        case chordContextBroadcast(lane: String, chord: Chord)
        /// `trackID` identifies which per-track mixer node inside `SamplePlaybackEngine`
        /// the voice routes to. The fader's `level` and `pan` are applied to that mixer
        /// node via `SamplePlaybackSink.setTrackMix(...)` outside the trigger path, so
        /// in-flight voices respond to live fader moves.
        case sampleTrigger(trackID: UUID, sampleID: UUID, settings: SamplerSettings, scheduledHostTime: TimeInterval)
    }

    let scheduledHostTime: TimeInterval
    let payload: Payload
}
