import CoreMIDI
import CoreAudio
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
    private var noteOffset: Int
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
        self.noteOffset = 0

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
                let shiftedPitch = Self.shiftedPitch(for: event.pitch, noteOffset: noteOffset)
                builder.addNoteOn(
                    channel: channel,
                    pitch: shiftedPitch,
                    velocity: event.velocity,
                    timestamp: timestamp
                )
                pendingNoteOffs[context.tickIndex + UInt64(event.length), default: []].append(shiftedPitch)
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
        switch (paramKey, value) {
        case let ("channel", .number(nextChannel)):
            guard let channel = Self.midiChannel(from: Int(nextChannel.rounded())) else {
                return
            }
            self.channel = channel
        case let ("noteOffset", .number(nextOffset)):
            noteOffset = Int(nextOffset.rounded())
        default:
            return
        }
    }

    func flushPendingNoteOffs(now: TimeInterval) {
        guard !pendingNoteOffs.isEmpty else {
            return
        }

        let noteOffs = pendingNoteOffs
            .keys
            .sorted()
            .flatMap { pendingNoteOffs[$0] ?? [] }
        pendingNoteOffs.removeAll()

        guard let client, let endpoint, !noteOffs.isEmpty else {
            return
        }

        var builder = MIDIPacketBuilder()
        let timestamp = Self.timestamp(from: now)
        for pitch in noteOffs {
            builder.addNoteOff(channel: channel, pitch: pitch, timestamp: timestamp)
        }

        do {
            try builder.withPacketList { packetList in
                try client.send(packetList, to: endpoint)
            }
        } catch {
            // Flush is best-effort transport cleanup. If the destination vanished, we still
            // clear local state so future ticks do not re-emit stale note-offs.
        }
    }

    private static func midiChannel(from value: Int) -> UInt8? {
        guard (0...15).contains(value) else {
            return nil
        }
        return UInt8(value)
    }

    private static func shiftedPitch(for pitch: UInt8, noteOffset: Int) -> UInt8 {
        UInt8(min(max(Int(pitch) + noteOffset, 0), 127))
    }

    private static func timestamp(from now: TimeInterval) -> MIDITimeStamp {
        AudioConvertNanosToHostTime(UInt64((max(0, now) * 1_000_000_000).rounded()))
    }
}
