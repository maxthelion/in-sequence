import Foundation

extension EngineController {
    final class RouterDispatchState {
        var midiOutputs: [Destination: MidiOut] = [:]
        var noteEvents: [RouteDestination: [NoteEvent]] = [:]
        var chords: [(RouteDestination, Chord, String?)] = []
        var midiNotes: [Destination: [NoteEvent]] = [:]
        /// Wall-clock host time for this tick. Used ONLY by the control-path
        /// note-off flush during repeat/cleanup teardown (off the sounding
        /// path). It MUST stay a real future host time; do not feed the unified
        /// clock's musical-seconds value here or a flushed note-off would carry
        /// a ~boot-time stamp.
        var dispatchNow: TimeInterval = 0
        /// Unified-clock-derived MIDI host-time seconds for this tick (Phase 3).
        /// `AudioMasterClock.hostSeconds(atMusicalSeconds:)` for the upcoming
        /// step — the render-origin host time plus the step's musical offset.
        /// The sounding MIDI-out path stamps its `MIDITimeStamp` from THIS, so
        /// external gear shares the audio sinks' timeline (origin-anchored,
        /// jitter-free) instead of the old pump wall-clock `now + stepDuration`.
        /// It is a HOST-TIME value (already includes the origin); never confuse
        /// it with `dispatchMusicalSeconds` (a bare musical offset) — feeding
        /// musical seconds to a `MIDITimeStamp` would resolve to ~boot time.
        var dispatchMIDIHostSeconds: TimeInterval = 0
        /// Cumulative MUSICAL seconds for this tick on the unified audio clock
        /// (`AudioMasterClock`). Routed AUDIO events (routed slicer / routed AU)
        /// stamp from this so they share the own-pattern audio path's units and
        /// land on the same frame on the same step (zero flam). It is mapped to
        /// `sampleTime` by `scheduledAudioTime(for:)` at dispatch — NEVER handed
        /// to a MIDITimeStamp.
        var dispatchMusicalSeconds: TimeInterval = 0

        func resetOutputs() {
            midiOutputs = [:]
        }

        func beginTick(
            now: TimeInterval,
            musicalSeconds: TimeInterval,
            midiHostSeconds: TimeInterval
        ) {
            dispatchNow = now
            dispatchMusicalSeconds = musicalSeconds
            dispatchMIDIHostSeconds = midiHostSeconds
            noteEvents = [:]
            chords = []
            midiNotes = [:]
        }

        func record(_ event: RouterEvent) {
            switch event {
            case let .note(destination, noteEvent):
                noteEvents[destination, default: []].append(noteEvent)
            case let .chord(destination, chord, lane):
                chords.append((destination, chord, lane))
            }
        }

        func appendMIDINotes(_ notes: [NoteEvent], to destination: Destination) {
            midiNotes[destination, default: []].append(contentsOf: notes)
        }

        func removeOutputs(for destinations: Set<Destination>) {
            for destination in destinations {
                midiOutputs.removeValue(forKey: destination)
            }
        }
    }
}
