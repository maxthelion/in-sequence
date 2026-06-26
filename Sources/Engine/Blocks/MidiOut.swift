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

    /// Per-port hardware-calibration output offset, in SECONDS, ADDED to every
    /// MIDI timestamp before send (note-on and note-off). Plumbed for Phase 3:
    /// a human can later dial in the constant latency of a specific external
    /// instrument/interface so its notes line up acoustically with the audio
    /// sinks. PLUMB-ONLY — default 0, never auto-detected/tuned here. Read it
    /// back via `outputOffsetSeconds` for tests. Threading: set/read on the
    /// tick queue (same as `channel`/`noteOffset`).
    private(set) var outputOffsetSeconds: TimeInterval = 0

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
        let timestamp = Self.timestamp(from: context.now, offsetSeconds: outputOffsetSeconds)

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
        case let ("outputOffsetSeconds", .number(nextOffset)):
            setOutputOffsetSeconds(nextOffset)
        default:
            return
        }
    }

    /// Set the per-port hardware-calibration output offset (seconds). PLUMB-ONLY
    /// config seam — a future calibration UI/config writes here; the engine
    /// never auto-tunes it. Negative values are clamped to 0 (a port cannot be
    /// asked to send before the scheduled musical time; only positive latency
    /// compensation — pushing a note later — is meaningful here).
    func setOutputOffsetSeconds(_ seconds: TimeInterval) {
        outputOffsetSeconds = max(0, seconds)
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
        let timestamp = Self.timestamp(from: now, offsetSeconds: outputOffsetSeconds)
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

    /// Build the `MIDITimeStamp` (mach host-time units) for a send.
    ///
    /// `now` is a HOST-TIME seconds value that, since Phase 3, is derived from
    /// the unified `AudioMasterClock` (`hostSeconds(atMusicalSeconds:)`): the
    /// render-origin host time plus the event's musical offset. That makes the
    /// MIDI stamp share the audio sinks' timeline — origin-anchored and
    /// jitter-free under pump wake jitter — instead of the old pump wall-clock
    /// `now + stepDuration`. The per-port `offsetSeconds` is ADDED here so a
    /// human can calibrate a specific port's hardware latency (default 0).
    private static func timestamp(
        from now: TimeInterval,
        offsetSeconds: TimeInterval
    ) -> MIDITimeStamp {
        let seconds = max(0, now + offsetSeconds)
        return AudioConvertNanosToHostTime(UInt64((seconds * 1_000_000_000).rounded()))
    }
}
