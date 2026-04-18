import CoreMIDI
import Foundation

final class MIDIClient {
    enum ClientError: Error {
        case failedToCreateClient(status: OSStatus)
        case failedToCreateSource(status: OSStatus)
        case failedToCreateDestination(status: OSStatus)
        case endpointConstructionFailed
    }

    typealias IncomingMIDIHandler = (UnsafePointer<MIDIPacketList>) -> Void

    let name: String
    private var clientRef: MIDIClientRef = 0
    private var virtualSourceRefs: [MIDIEndpointRef] = []
    private var virtualDestinationRefs: [MIDIEndpointRef] = []
    private var incomingHandlers: [MIDIEndpointRef: IncomingMIDIHandler] = [:]

    init(name: String) throws {
        self.name = name
        let status = MIDIClientCreateWithBlock(name as CFString, &clientRef) { _ in
            // MIDI system notifications — handled in a later task.
        }
        guard status == noErr else {
            throw ClientError.failedToCreateClient(status: status)
        }
    }

    deinit {
        for ref in virtualSourceRefs { MIDIEndpointDispose(ref) }
        for ref in virtualDestinationRefs { MIDIEndpointDispose(ref) }
        if clientRef != 0 {
            MIDIClientDispose(clientRef)
        }
    }

    /// All MIDI *sources* known to CoreMIDI (producers of MIDI data), including any
    /// virtual sources this app has created via `createVirtualOutput`.
    var sources: [MIDIEndpoint] {
        let count = MIDIGetNumberOfSources()
        return (0..<count).compactMap { i in
            MIDIEndpoint(ref: MIDIGetSource(i), role: .source)
        }
    }

    /// All MIDI *destinations* known to CoreMIDI (consumers of MIDI data), including any
    /// virtual destinations this app has created via `createVirtualInput`.
    var destinations: [MIDIEndpoint] {
        let count = MIDIGetNumberOfDestinations()
        return (0..<count).compactMap { i in
            MIDIEndpoint(ref: MIDIGetDestination(i), role: .destination)
        }
    }

    /// Creates a virtual source: MIDI *output* from this app's perspective (other apps
    /// see it as an input they can connect to). Because CoreMIDI lists it via
    /// `MIDIGetSource`, the returned endpoint's `role` is `.source`.
    func createVirtualOutput(name: String) throws -> MIDIEndpoint {
        var ref: MIDIEndpointRef = 0
        let status = MIDISourceCreate(clientRef, name as CFString, &ref)
        guard status == noErr else {
            throw ClientError.failedToCreateSource(status: status)
        }
        virtualSourceRefs.append(ref)
        guard let endpoint = MIDIEndpoint(ref: ref, role: .source) else {
            throw ClientError.endpointConstructionFailed
        }
        return endpoint
    }

    /// Creates a virtual destination: MIDI *input* from this app's perspective (other apps
    /// see it as an output they can send to). Because CoreMIDI lists it via
    /// `MIDIGetDestination`, the returned endpoint's `role` is `.destination`.
    func createVirtualInput(
        name: String,
        handler: @escaping IncomingMIDIHandler
    ) throws -> MIDIEndpoint {
        var ref: MIDIEndpointRef = 0
        let status = MIDIDestinationCreateWithBlock(clientRef, name as CFString, &ref) { packetList, _ in
            handler(packetList)
        }
        guard status == noErr else {
            throw ClientError.failedToCreateDestination(status: status)
        }
        virtualDestinationRefs.append(ref)
        incomingHandlers[ref] = handler
        guard let endpoint = MIDIEndpoint(ref: ref, role: .destination) else {
            throw ClientError.endpointConstructionFailed
        }
        return endpoint
    }
}
