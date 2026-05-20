import Foundation

extension EngineController {
    final class RouterDispatchState {
        var midiOutputs: [Destination: MidiOut] = [:]
        var noteEvents: [RouteDestination: [NoteEvent]] = [:]
        var chords: [(RouteDestination, Chord, String?)] = []
        var midiNotes: [Destination: [NoteEvent]] = [:]
        var dispatchNow: TimeInterval = 0

        func resetOutputs() {
            midiOutputs = [:]
        }

        func beginTick(now: TimeInterval) {
            dispatchNow = now
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
