import CoreMIDI
import Foundation

final class MIDIClient {
    enum ClientError: Error {
        case failedToCreateClient(status: OSStatus)
    }

    let name: String
    private var clientRef: MIDIClientRef = 0

    init(name: String) throws {
        self.name = name
        let status = MIDIClientCreateWithBlock(name as CFString, &clientRef) { _ in
            // MIDI system notifications (device added/removed) — handled in a later task.
        }
        guard status == noErr else {
            throw ClientError.failedToCreateClient(status: status)
        }
    }

    deinit {
        if clientRef != 0 {
            MIDIClientDispose(clientRef)
        }
    }

    var inputEndpoints: [MIDIEndpoint] {
        let count = MIDIGetNumberOfSources()
        return (0..<count).compactMap { i in
            let ref = MIDIGetSource(i)
            return MIDIEndpoint(ref: ref, direction: .input)
        }
    }

    var outputEndpoints: [MIDIEndpoint] {
        let count = MIDIGetNumberOfDestinations()
        return (0..<count).compactMap { i in
            let ref = MIDIGetDestination(i)
            return MIDIEndpoint(ref: ref, direction: .output)
        }
    }
}
