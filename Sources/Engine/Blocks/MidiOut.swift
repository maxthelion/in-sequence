import CoreMIDI
import Foundation

final class MidiOut: Block {
    static let inputs: [PortSpec] = [
        PortSpec(id: "notes", streamKind: .notes)
    ]
    static let outputs: [PortSpec] = []
    static let defaultChannel: UInt8 = 0

    let id: BlockID
    var client: MIDIClient?
    var endpoint: MIDIEndpoint?

    private var channel: UInt8
    private var pendingNoteOffs: [UInt64: [UInt8]] = [:]

    init(
        id: BlockID,
        params: [String: ParamValue] = [:],
        client: MIDIClient? = nil,
        endpoint: MIDIEndpoint? = nil
    ) {
        self.id = id
        self.client = client
        self.endpoint = endpoint
        self.channel = Self.defaultChannel

        for (key, value) in params {
            apply(paramKey: key, value: value)
        }
    }

    func tick(context: TickContext) -> [PortID: Stream] {
        guard let client, let endpoint else {
            return [:]
        }

        var builder = MIDIPacketBuilder()
        let timestamp = Self.timestamp(from: context.now)

        if let dueNoteOffs = pendingNoteOffs.removeValue(forKey: context.tickIndex) {
            for pitch in dueNoteOffs {
                builder.addNoteOff(channel: channel, pitch: pitch, timestamp: timestamp)
            }
        }

        if case let .notes(events)? = context.inputs["notes"] {
            for event in events where event.gate {
                builder.addNoteOn(
                    channel: channel,
                    pitch: event.pitch,
                    velocity: event.velocity,
                    timestamp: timestamp
                )
                pendingNoteOffs[context.tickIndex + UInt64(event.length), default: []].append(event.pitch)
            }
        }

        do {
            try builder.withPacketList { packetList in
                try client.send(packetList, to: endpoint)
            }
        } catch {
            // This block is a leaf sink in the current plan; transport-level error handling
            // is added when the engine controller owns a surfaced diagnostics path.
        }

        return [:]
    }

    func apply(paramKey: String, value: ParamValue) {
        guard case let ("channel", .number(nextChannel)) = (paramKey, value),
              let channel = Self.midiChannel(from: Int(nextChannel.rounded()))
        else {
            return
        }

        self.channel = channel
    }

    private static func midiChannel(from value: Int) -> UInt8? {
        guard (0...15).contains(value) else {
            return nil
        }
        return UInt8(value)
    }

    private static func timestamp(from now: TimeInterval) -> MIDITimeStamp {
        MIDITimeStamp((max(0, now) * 1_000_000_000).rounded())
    }
}
