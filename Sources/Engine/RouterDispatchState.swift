import Foundation

extension EngineController {
    final class RouterDispatchState {
        var midiOutputs: [Destination: MidiOut] = [:]
        var noteEvents: [RouteDestination: [NoteEvent]] = [:]
        var chords: [(RouteDestination, Chord, String?)] = []
        var midiNotes: [Destination: [NoteEvent]] = [:]
        /// Wall-clock host time for this tick. The MIDI-out path stamps a
        /// `MIDITimeStamp` from this (via `AudioConvertNanosToHostTime`), so it
        /// MUST stay a real future host time. MIDI-out is NOT yet on the unified
        /// audio clock (that is Phase 3); do not feed the unified clock's
        /// musical-seconds value here or external gear would fire at ~boot time.
        var dispatchNow: TimeInterval = 0
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

        func beginTick(now: TimeInterval, musicalSeconds: TimeInterval) {
            dispatchNow = now
            dispatchMusicalSeconds = musicalSeconds
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
