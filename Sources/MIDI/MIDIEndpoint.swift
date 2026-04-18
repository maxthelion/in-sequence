import CoreMIDI
import Foundation

struct MIDIEndpoint: Identifiable, Hashable {
    /// CoreMIDI classifies every endpoint as either a *source* (produces MIDI) or a
    /// *destination* (consumes MIDI). We mirror that terminology here rather than
    /// the app-centric "input/output", because it matches what `MIDIGetSource` and
    /// `MIDIGetDestination` enumerate — including virtual endpoints this app creates.
    enum Role {
        case source
        case destination
    }

    let id: MIDIUniqueID
    let ref: MIDIEndpointRef
    let displayName: String
    let role: Role

    init?(ref: MIDIEndpointRef, role: Role) {
        guard ref != 0 else { return nil }
        self.ref = ref
        self.role = role

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
