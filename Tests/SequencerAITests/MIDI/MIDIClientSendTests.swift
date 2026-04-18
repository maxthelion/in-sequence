import XCTest
import CoreMIDI
@testable import SequencerAI

final class MIDIClientSendTests: XCTestCase {

    /// Two-client loopback: client A owns a virtual destination; client B creates an input port
    /// connected to that destination and records received packets.
    /// Sending via A.send() must result in B's port handler receiving the packet.
    func test_send_to_virtual_destination_is_received_by_connected_port() throws {
        let received = LockedPacketStore()

        // Client A: owns the virtual destination (other apps write to it)
        let clientA = try MIDIClient(name: "SequencerAI_SendTest_A")
        let destA = try clientA.createVirtualInput(name: "SequencerAI_SendTest_Dest") { packetList in
            // CoreMIDI calls this when data arrives at the virtual destination.
            // Forward to our store so the test can inspect it.
            received.append(packetList)
        }

        // Client B: creates an output port and sends to destA
        let clientB = try MIDIClient(name: "SequencerAI_SendTest_B")

        // Build a note-on packet
        var builder = MIDIPacketBuilder()
        builder.addNoteOn(channel: 0, pitch: 69, velocity: 88, timestamp: 0)

        // Send from B to A's virtual destination
        try builder.withPacketList { listPtr in
            try clientB.send(listPtr, to: destA)
        }

        // CoreMIDI dispatches asynchronously; poll briefly.
        let deadline = Date().addingTimeInterval(1.0)
        while received.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertFalse(received.isEmpty, "Should have received at least one packet")

        received.withFirstPacket { packet in
            XCTAssertEqual(packet.data.0, 0x90 | 0) // note-on, channel 0
            XCTAssertEqual(packet.data.1, 69)         // pitch A4
            XCTAssertEqual(packet.data.2, 88)         // velocity
        }
    }
}

// MARK: - Test helpers

/// Thread-safe store for received MIDIPacket data.
private final class LockedPacketStore: @unchecked Sendable {
    private var packets: [[UInt8]] = []
    private let lock = NSLock()

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return packets.isEmpty
    }

    func append(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock(); defer { lock.unlock() }
        var current = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(current.length)
            let bytes = withUnsafeBytes(of: current.data) { ptr in
                Array(ptr.prefix(length))
            }
            packets.append(bytes)
            current = MIDIPacketNext(&current).pointee
        }
    }

    func withFirstPacket(_ body: (MIDIPacket) -> Void) {
        lock.lock()
        guard !packets.isEmpty else { lock.unlock(); return }
        let bytes = packets[0]
        lock.unlock()
        // Reconstruct a MIDIPacket for assertion convenience
        var packet = MIDIPacket()
        packet.length = UInt16(min(bytes.count, 256))
        withUnsafeMutableBytes(of: &packet.data) { dst in
            for (i, b) in bytes.prefix(256).enumerated() {
                dst[i] = b
            }
        }
        body(packet)
    }
}
