import CoreMIDI
import Foundation

/// A value-type builder that constructs a `MIDIPacketList` for note-on, note-off,
/// and CC payloads, avoiding the error-prone C-style `MIDIPacketListAdd` dance at
/// every call site.
///
/// Usage:
/// ```swift
/// var builder = MIDIPacketBuilder()
/// builder.addNoteOn(channel: 0, pitch: 60, velocity: 100, timestamp: mach_absolute_time())
/// builder.addNoteOff(channel: 0, pitch: 60, timestamp: mach_absolute_time() + delta)
/// builder.withPacketList { ptr in
///     MIDISend(outputPort, destination, ptr)
/// }
/// ```
struct MIDIPacketBuilder {

    // Maximum bytes for the packet list buffer.
    // Each MIDI packet is: timeStamp(8) + length(2) + data(3) + padding(up to 1) ≈ 14 bytes.
    // 128 MIDI messages is a very generous upper bound for a single list.
    private static let maxPackets = 128
    private static let bufferSize = 65536

    private var buffer: [UInt8]
    private var currentPacketPtr: UnsafeMutablePointer<MIDIPacket>?
    private var listPtr: UnsafeMutablePointer<MIDIPacketList>?

    init() {
        buffer = [UInt8](repeating: 0, count: Self.bufferSize)
    }

    /// Calls `body` with a pointer to the built `MIDIPacketList`.
    /// The pointer is valid only for the duration of the closure.
    mutating func withPacketList<R>(_ body: (UnsafePointer<MIDIPacketList>) throws -> R) rethrows -> R {
        try buffer.withUnsafeMutableBytes { rawBuffer in
            let listPtr = rawBuffer.baseAddress!
                .assumingMemoryBound(to: MIDIPacketList.self)
            var current = MIDIPacketListInit(listPtr)
            // Replay all stored events into the packet list
            for event in events {
                current = MIDIPacketListAdd(
                    listPtr,
                    Self.bufferSize,
                    current,
                    event.timestamp,
                    event.bytes.count,
                    event.bytes
                )
            }
            return try body(UnsafePointer(listPtr))
        }
    }

    // MARK: - Add methods

    mutating func addNoteOn(
        channel: UInt8,
        pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp
    ) {
        events.append(MIDIEvent(
            timestamp: timestamp,
            bytes: [0x90 | (channel & 0x0F), pitch & 0x7F, velocity & 0x7F]
        ))
    }

    mutating func addNoteOff(
        channel: UInt8,
        pitch: UInt8,
        timestamp: MIDITimeStamp
    ) {
        events.append(MIDIEvent(
            timestamp: timestamp,
            bytes: [0x80 | (channel & 0x0F), pitch & 0x7F, 0]
        ))
    }

    mutating func addCC(
        channel: UInt8,
        controller: UInt8,
        value: UInt8,
        timestamp: MIDITimeStamp
    ) {
        events.append(MIDIEvent(
            timestamp: timestamp,
            bytes: [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
        ))
    }

    // MARK: - Private storage

    private struct MIDIEvent {
        let timestamp: MIDITimeStamp
        let bytes: [UInt8]
    }

    private var events: [MIDIEvent] = []
}
