import Foundation
import Observation

/// App-wide MIDI session. Owns the single `MIDIClient`, creates this app's virtual
/// endpoints, and exposes the system-wide source/destination lists to the UI.
///
/// Property names follow CoreMIDI terminology: `sources` are MIDI producers
/// (what the app can *listen* to), `destinations` are MIDI consumers (what the
/// app can *send* to). UI labels like "Inputs" / "Outputs" are a user-facing
/// framing and live in the view layer.
@Observable
final class MIDISession {
    static let shared = MIDISession()

    let client: MIDIClient?
    let clientError: Error?
    private(set) var appInput: MIDIEndpoint?
    private(set) var appOutput: MIDIEndpoint?

    private init() {
        do {
            let c = try MIDIClient(name: "SequencerAI")
            self.client = c
            self.clientError = nil
            do {
                self.appOutput = try c.createVirtualOutput(name: "SequencerAI Out")
                self.appInput = try c.createVirtualInput(name: "SequencerAI In") { _ in
                    // TODO(phase 2): route incoming MIDI into the engine
                }
            } catch {
                NSLog("Virtual endpoint creation failed: \(error)")
            }
        } catch {
            self.client = nil
            self.clientError = error
            self.appInput = nil
            self.appOutput = nil
        }
    }

    var sources: [MIDIEndpoint] { client?.sources ?? [] }
    var destinations: [MIDIEndpoint] { client?.destinations ?? [] }
}
