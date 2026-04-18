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

            // First packet: note-on
            let firstPacketPtr = UnsafeRawPointer(listPtr)
                .advanced(by: MemoryLayout<UInt32>.size) // skip numPackets
                .assumingMemoryBound(to: MIDIPacket.self)
            let firstPacket = firstPacketPtr.pointee
            XCTAssertEqual(firstPacket.data.0, 0x90 | 0)  // note-on, channel 0
            XCTAssertEqual(firstPacket.data.1, 60)          // pitch
            XCTAssertEqual(firstPacket.data.2, 100)         // velocity
            XCTAssertEqual(firstPacket.timeStamp, baseTime)

            // Second packet: note-off
            let secondPacketPtr = MIDIPacketNext(firstPacketPtr)
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

            let packetPtr = UnsafeRawPointer(listPtr)
                .advanced(by: MemoryLayout<UInt32>.size)
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
}
