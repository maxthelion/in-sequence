import XCTest
import CoreMIDI
@testable import SequencerAI

final class MIDIPacketBuilderTests: XCTestCase {

    // Tests a note-on + note-off pair: correct byte payloads and strictly ordered timestamps.
    func test_noteOn_noteOff_pair_payloads_and_ordering() throws {
        var builder = MIDIPacketBuilder()
        let baseTime = MIDITimeStamp(0)
        let laterTime = MIDITimeStamp(1000)

        builder.addNoteOn(channel: 0, pitch: 60, velocity: 100, timestamp: baseTime)
        builder.addNoteOff(channel: 0, pitch: 60, timestamp: laterTime)

        try builder.withPacketList { listPtr in
            XCTAssertEqual(listPtr.pointee.numPackets, 2)

            // First packet: use MemoryLayout.offset(of:) to find the `packet` field instead
            // of hard-coding 4 bytes (the offset depends on CoreMIDI's packing attributes).
            let firstPacketOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let firstPacketPtr = UnsafeRawPointer(listPtr)
                .advanced(by: firstPacketOffset)
                .assumingMemoryBound(to: MIDIPacket.self)
            let firstPacket = firstPacketPtr.pointee
            XCTAssertEqual(firstPacket.data.0, 0x90 | 0)  // note-on, channel 0
            XCTAssertEqual(firstPacket.data.1, 60)          // pitch
            XCTAssertEqual(firstPacket.data.2, 100)         // velocity
            XCTAssertEqual(firstPacket.timeStamp, baseTime)

            // Second packet: use MIDIPacketNext for safe iteration (never advance by hand).
            var mutableFirst = firstPacket
            let secondPacketPtr = MIDIPacketNext(&mutableFirst)
            let secondPacket = secondPacketPtr.pointee
            XCTAssertEqual(secondPacket.data.0, 0x80 | 0)  // note-off, channel 0
            XCTAssertEqual(secondPacket.data.1, 60)          // pitch
            XCTAssertEqual(secondPacket.data.2, 0)           // velocity always 0 for note-off
            XCTAssertEqual(secondPacket.timeStamp, laterTime)

            // Timestamps: second must be strictly later
            XCTAssertGreaterThan(secondPacket.timeStamp, firstPacket.timeStamp)
        }
    }

    func test_cc_payload() throws {
        var builder = MIDIPacketBuilder()
        builder.addCC(channel: 2, controller: 7, value: 64, timestamp: MIDITimeStamp(500))

        try builder.withPacketList { listPtr in
            XCTAssertEqual(listPtr.pointee.numPackets, 1)

            let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let packetPtr = UnsafeRawPointer(listPtr)
                .advanced(by: packetOffset)
                .assumingMemoryBound(to: MIDIPacket.self)
            let packet = packetPtr.pointee
            XCTAssertEqual(packet.data.0, 0xB0 | 2)  // CC, channel 2
            XCTAssertEqual(packet.data.1, 7)           // controller
            XCTAssertEqual(packet.data.2, 64)          // value
        }
    }

    // Buffer size sanity check: the backing buffer must be small (< 4 KiB).
    func test_buffer_size_is_small() {
        XCTAssertLessThan(MIDIPacketBuilder.bufferSize, 4096,
            "bufferSize must be < 4 KiB; found \(MIDIPacketBuilder.bufferSize) bytes")
    }

    func test_withPacketList_can_be_called_on_let_builder() throws {
        let builder = makeBuilderWithSingleNoteOn()

        try builder.withPacketList { listPtr in
            XCTAssertEqual(listPtr.pointee.numPackets, 1)
        }
    }

    // At capacity limit (128 events): withPacketList must succeed.
    func test_at_capacity_withPacketList_succeeds() throws {
        var builder = MIDIPacketBuilder()
        for i in 0..<128 {
            builder.addNoteOn(channel: 0, pitch: UInt8(i % 128), velocity: 64,
                              timestamp: MIDITimeStamp(i))
        }
        // Should not throw
        try builder.withPacketList { listPtr in
            XCTAssertEqual(listPtr.pointee.numPackets, 128)
        }
    }

    // MARK: - Input validation (precondition style B)
    //
    // Out-of-range MIDI values are programmer errors. The add methods use
    // `precondition()` so they trap immediately rather than silently truncating
    // (e.g. channel 20 becoming channel 4). Because precondition() terminates
    // the process, the trap paths cannot be exercised in-process. The tests
    // below verify correct byte encoding at the valid boundaries to confirm the
    // preconditions do not fire for legal values.

    // channel 0 and channel 15 are both valid; verify bytes at boundary.
    func test_addNoteOn_validChannelBoundaries_encodeCorrectly() throws {
        var low = MIDIPacketBuilder()
        low.addNoteOn(channel: 0, pitch: 60, velocity: 64, timestamp: 0)
        try low.withPacketList { listPtr in
            let off = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let p = UnsafeRawPointer(listPtr).advanced(by: off).assumingMemoryBound(to: MIDIPacket.self).pointee
            XCTAssertEqual(p.data.0, 0x90, "channel 0 => status 0x90")
        }

        var high = MIDIPacketBuilder()
        high.addNoteOn(channel: 15, pitch: 60, velocity: 64, timestamp: 0)
        try high.withPacketList { listPtr in
            let off = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let p = UnsafeRawPointer(listPtr).advanced(by: off).assumingMemoryBound(to: MIDIPacket.self).pointee
            XCTAssertEqual(p.data.0, 0x9F, "channel 15 => status 0x9F")
        }
    }

    // pitch 0 and pitch 127 are both valid.
    func test_addNoteOn_validPitchBoundaries_encodeCorrectly() throws {
        var b = MIDIPacketBuilder()
        b.addNoteOn(channel: 0, pitch: 0, velocity: 64, timestamp: 0)
        b.addNoteOn(channel: 0, pitch: 127, velocity: 64, timestamp: 1)
        try b.withPacketList { listPtr in
            let off = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let first = UnsafeRawPointer(listPtr).advanced(by: off).assumingMemoryBound(to: MIDIPacket.self).pointee
            XCTAssertEqual(first.data.1, 0)
            var mutableFirst = first
            let second = MIDIPacketNext(&mutableFirst).pointee
            XCTAssertEqual(second.data.1, 127)
        }
    }

    // velocity 0 and velocity 127 are both valid.
    func test_addNoteOn_validVelocityBoundaries_encodeCorrectly() throws {
        var b = MIDIPacketBuilder()
        b.addNoteOn(channel: 0, pitch: 60, velocity: 0, timestamp: 0)
        b.addNoteOn(channel: 0, pitch: 60, velocity: 127, timestamp: 1)
        try b.withPacketList { listPtr in
            let off = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let first = UnsafeRawPointer(listPtr).advanced(by: off).assumingMemoryBound(to: MIDIPacket.self).pointee
            XCTAssertEqual(first.data.2, 0)
            var mutableFirst = first
            let second = MIDIPacketNext(&mutableFirst).pointee
            XCTAssertEqual(second.data.2, 127)
        }
    }

    // addCC: controller and value at max valid boundary.
    func test_addCC_validBoundaries_encodeCorrectly() throws {
        var b = MIDIPacketBuilder()
        b.addCC(channel: 15, controller: 127, value: 127, timestamp: 0)
        try b.withPacketList { listPtr in
            let off = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            let p = UnsafeRawPointer(listPtr).advanced(by: off).assumingMemoryBound(to: MIDIPacket.self).pointee
            XCTAssertEqual(p.data.0, 0xBF)   // CC, channel 15
            XCTAssertEqual(p.data.1, 127)     // controller
            XCTAssertEqual(p.data.2, 127)     // value
        }
    }

    // Beyond capacity: withPacketList must throw packetListFull.
    func test_overflow_throws_packetListFull() {
        var builder = MIDIPacketBuilder()
        // Add more events than the 2200-byte buffer can hold (each packet ~16 bytes;
        // 200 × 16 + 4 = 3204 bytes > 2200 bytes).
        for i in 0..<200 {
            builder.addNoteOn(channel: 0, pitch: UInt8(i % 128), velocity: 64,
                              timestamp: MIDITimeStamp(i))
        }
        XCTAssertThrowsError(try builder.withPacketList { _ in }) { error in
            guard case MIDIPacketBuilderError.packetListFull = error else {
                XCTFail("Expected MIDIPacketBuilderError.packetListFull, got \(error)")
                return
            }
        }
    }

    private func makeBuilderWithSingleNoteOn() -> MIDIPacketBuilder {
        var builder = MIDIPacketBuilder()
        builder.addNoteOn(channel: 0, pitch: 60, velocity: 64, timestamp: 0)
        return builder
    }
}
