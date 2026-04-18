import CoreMIDI
import Foundation

final class MIDIClient {
    enum ClientError: Error {
        case failedToCreateClient(status: OSStatus)
        case failedToCreateSource(status: OSStatus)
        case failedToCreateDestination(status: OSStatus)
        case failedToCreateOutputPort(status: OSStatus)
        case failedToSend(status: OSStatus)
        case endpointConstructionFailed
    }

    let name: String
    private var clientRef: MIDIClientRef = 0
    private var virtualSourceRefs: [MIDIEndpointRef] = []
    private var virtualDestinationRefs: [MIDIEndpointRef] = []
    private var outputPortRef: MIDIPortRef = 0

    init(name: String) throws {
        self.name = name
        // NB: the notification block runs on a CoreMIDI-internal thread; when it grows
        // beyond a no-op (to track kMIDIMsgObjectAdded/Removed for device hot-plug),
        // mutations from here must be marshalled to match the main-thread readers of
        // `sources` / `destinations`.
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
        if outputPortRef != 0 { MIDIPortDispose(outputPortRef) }
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
        handler: @escaping (UnsafePointer<MIDIPacketList>) -> Void
    ) throws -> MIDIEndpoint {
        var ref: MIDIEndpointRef = 0
        let status = MIDIDestinationCreateWithBlock(clientRef, name as CFString, &ref) { packetList, _ in
            handler(packetList)
        }
        guard status == noErr else {
            throw ClientError.failedToCreateDestination(status: status)
        }
        // Handler is retained by the closure captured by MIDIDestinationCreateWithBlock; no
        // separate ownership needed here.
        virtualDestinationRefs.append(ref)
        guard let endpoint = MIDIEndpoint(ref: ref, role: .destination) else {
            throw ClientError.endpointConstructionFailed
        }
        return endpoint
    }

    /// Sends a `MIDIPacketList` to `endpoint`.
    ///
    /// - If `endpoint` is a virtual source owned by this client, `MIDIReceived` is used
    ///   so any connected input ports receive the data directly.
    /// - Otherwise an output port is lazily created and `MIDISend` is used, which works
    ///   for any real or virtual destination.
    ///
    /// **Contract / failure modes:**
    /// - Empty packet list (`numPackets == 0`): this is a silent no-op — CoreMIDI and
    ///   `MIDIReceived` both accept an empty list without error. Callers that want
    ///   to avoid the round-trip should guard `!events.isEmpty` before calling.
    /// - Disposed or invalid endpoint (`endpoint.ref == 0` or already disposed):
    ///   CoreMIDI returns a non-`noErr` status, which this method surfaces as
    ///   `ClientError.failedToSend(status:)`. The caller is responsible for not
    ///   sending to an endpoint whose lifetime has ended.
    /// - Errors from `MIDIReceived` / `MIDISend` / `MIDIOutputPortCreate` are all
    ///   re-thrown; no status is silently swallowed.
    ///
    /// - Throws: `ClientError.failedToSend` if CoreMIDI reports an error.
    /// - Throws: `ClientError.failedToCreateOutputPort` on first use if the output
    ///   port cannot be created.
    func send(_ packetList: UnsafePointer<MIDIPacketList>, to endpoint: MIDIEndpoint) throws {
        if endpoint.role == .source && virtualSourceRefs.contains(endpoint.ref) {
            // Push into a virtual source we own.
            let status = MIDIReceived(endpoint.ref, packetList)
            guard status == noErr else {
                throw ClientError.failedToSend(status: status)
            }
        } else {
            // Send to any destination (including virtual destinations) via an output port.
            let port = try lazyOutputPort()
            let status = MIDISend(port, endpoint.ref, packetList)
            guard status == noErr else {
                throw ClientError.failedToSend(status: status)
            }
        }
    }

    // MARK: - Internal (test access)

    /// Exposes the underlying `MIDIClientRef` so test helpers (e.g. `MIDIInputPortCreateWithBlock`)
    /// can create additional ports on this client without making `clientRef` fully public.
    var clientRefForTesting: MIDIClientRef { clientRef }

    // MARK: - Private

    /// Creates the output port on first use.
    private func lazyOutputPort() throws -> MIDIPortRef {
        if outputPortRef != 0 { return outputPortRef }
        let status = MIDIOutputPortCreate(clientRef, "\(name) Out Port" as CFString, &outputPortRef)
        guard status == noErr else {
            throw ClientError.failedToCreateOutputPort(status: status)
        }
        return outputPortRef
    }
}
