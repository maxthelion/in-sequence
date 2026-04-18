import CoreMIDI
import Foundation

struct MIDIEndpoint: Identifiable, Hashable {
    enum Direction {
        case input
        case output
    }

    let id: MIDIUniqueID
    let ref: MIDIEndpointRef
    let displayName: String
    let direction: Direction

    init?(ref: MIDIEndpointRef, direction: Direction) {
        guard ref != 0 else { return nil }
        self.ref = ref
        self.direction = direction

        var uniqueID: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uniqueID)
        self.id = uniqueID

        var nameRef: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &nameRef)
        if status == noErr, let name = nameRef?.takeRetainedValue() as String? {
            self.displayName = name
        } else {
            self.displayName = "Unknown MIDI Endpoint"
        }
    }
}
