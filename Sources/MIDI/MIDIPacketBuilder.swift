import CoreMIDI
import Foundation

/// Errors that `MIDIPacketBuilder` can surface.
enum MIDIPacketBuilderError: Error {
    /// `MIDIPacketListAdd` returned nil — the packet list buffer is exhausted.
    case packetListFull
}

/// A value-type builder that constructs a `MIDIPacketList` for note-on, note-off,
/// and CC payloads, avoiding the error-prone C-style `MIDIPacketListAdd` dance at
/// every call site.
///
/// Each call to `withPacketList` rebuilds the list from scratch; no state is
/// carried between invocations.
///
/// Usage:
/// ```swift
/// var builder = MIDIPacketBuilder()
/// builder.addNoteOn(channel: 0, pitch: 60, velocity: 100, timestamp: mach_absolute_time())
/// builder.addNoteOff(channel: 0, pitch: 60, timestamp: mach_absolute_time() + delta)
/// try builder.withPacketList { ptr in
///     MIDISend(outputPort, destination, ptr)
/// }
/// ```
struct MIDIPacketBuilder {

    // Maximum bytes for the packet list buffer.
    // Each MIDI packet occupies: timeStamp(8) + length(2) + data(3) rounded up to 4-byte
    // alignment = 16 bytes. MIDIPacketList header = 4 bytes.
    // 128 MIDI messages: 4 + 128 × 16 = 2052 bytes; use 2200 for headroom.
    // This is well within the 2–4 KiB target from the spec and far below the old 64 KiB.
    static let bufferSize = 2200

    private var buffer: [UInt8]

    init() {
        buffer = [UInt8](repeating: 0, count: Self.bufferSize)
    }

    /// Calls `body` with a pointer to the built `MIDIPacketList`.
    /// The pointer is valid only for the duration of the closure.
    ///
    /// - Throws: `MIDIPacketBuilderError.packetListFull` if the events added to
    ///   this builder exceed the 2 KiB buffer capacity.
    mutating func withPacketList<R>(_ body: (UnsafePointer<MIDIPacketList>) throws -> R) throws -> R {
        try buffer.withUnsafeMutableBytes { rawBuffer in
            let listPtr = rawBuffer.baseAddress!
                .assumingMemoryBound(to: MIDIPacketList.self)
            var current = MIDIPacketListInit(listPtr)
            // Replay all stored events into the packet list
            for event in events {
                let next = MIDIPacketListAdd(
                    listPtr,
                    Self.bufferSize,
                    current,
                    event.timestamp,
                    event.bytes.count,
                    event.bytes
                )
                // MIDIPacketListAdd returns nil (null pointer) when the buffer is exhausted.
                // Swift's importer may map the return type as non-Optional even though the
                // C API documents a null return on overflow, so we check the bit pattern.
                guard UInt(bitPattern: next) != 0 else {
                    throw MIDIPacketBuilderError.packetListFull
                }
                current = next
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
