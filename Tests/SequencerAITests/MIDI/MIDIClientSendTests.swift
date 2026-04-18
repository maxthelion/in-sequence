import XCTest
import CoreMIDI
@testable import SequencerAI

final class MIDIClientSendTests: XCTestCase {

    // MARK: - Finding 6: 2-client loopback (MIDISend branch)
    //
    // Plan Task 1 wiring (corrected): client B owns the virtual destination and records
    // packets arriving at its own createVirtualInput callback. Client A creates an
    // output port and sends to B's destination via MIDISend.
    //
    // Previously the recording handler lived on A's own createVirtualInput callback
    // while B only sent, making it a 1-direction test. Now B is both the destination
    // owner AND the recorder; A is purely the sender. This catches regressions in
    // CoreMIDI's MIDISend → virtual destination delivery path.
    func test_send_loopback_roundtrip() throws {
        let received = LockedPacketStore()

        // Client B: owns the virtual destination and records arriving packets.
        let clientB = try MIDIClient(name: "SequencerAI_Loopback_B")
        let destB = try clientB.createVirtualInput(name: "SequencerAI_Loopback_Dest") { packetList in
            received.append(packetList)
        }

        // Client A: creates an output port and sends to B's virtual destination.
        let clientA = try MIDIClient(name: "SequencerAI_Loopback_A")

        // Build a note-on packet.
        var builder = MIDIPacketBuilder()
        builder.addNoteOn(channel: 0, pitch: 69, velocity: 88, timestamp: 0)

        // Send from A to B's virtual destination (MIDISend path).
        try builder.withPacketList { listPtr in
            try clientA.send(listPtr, to: destB)
        }

        // CoreMIDI dispatches asynchronously; poll briefly.
        let deadline = Date().addingTimeInterval(1.0)
        while received.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertFalse(received.isEmpty, "B's virtual destination should have received at least one packet")
        received.withFirstPacket { packet in
            XCTAssertEqual(packet.data.0, 0x90 | 0)  // note-on, channel 0
            XCTAssertEqual(packet.data.1, 69)          // pitch A4
            XCTAssertEqual(packet.data.2, 88)          // velocity
        }
    }

    // MARK: - Finding 5: MIDIReceived branch of send(_:to:)
    //
    // When send() targets a virtual source owned by this client, it calls MIDIReceived
    // instead of MIDISend. This test exercises that branch:
    //   - Client A creates a virtual source.
    //   - Client B creates an input port connected to A's virtual source.
    //   - Client A calls send(_:to:) targeting its own virtual source.
    //   - Client B's input port handler must observe the packet.
    func test_send_via_MIDIReceived_is_observed_by_connected_client() throws {
        let received = LockedPacketStore()

        // Client A: owns the virtual source (MIDI producer).
        let clientA = try MIDIClient(name: "SequencerAI_Received_A")
        let sourceA = try clientA.createVirtualOutput(name: "SequencerAI_Received_Src")

        // Client B: input port connected to A's virtual source.
        let clientB = try MIDIClient(name: "SequencerAI_Received_B")
        var inputPortRef: MIDIPortRef = 0
        let portStatus = MIDIInputPortCreateWithBlock(
            clientB.clientRefForTesting,
            "SequencerAI_Received_B_InPort" as CFString,
            &inputPortRef
        ) { packetList, _ in
            received.append(packetList)
        }
        XCTAssertEqual(portStatus, noErr, "Failed to create input port on client B")
        let connectStatus = MIDIPortConnectSource(inputPortRef, sourceA.ref, nil)
        XCTAssertEqual(connectStatus, noErr, "Failed to connect B's port to A's virtual source")

        // Build and send from A targeting its own virtual source — triggers MIDIReceived.
        var builder = MIDIPacketBuilder()
        builder.addNoteOn(channel: 1, pitch: 48, velocity: 72, timestamp: 0)
        try builder.withPacketList { listPtr in
            try clientA.send(listPtr, to: sourceA)
        }

        // Poll for receipt.
        let deadline = Date().addingTimeInterval(1.0)
        while received.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        MIDIPortDispose(inputPortRef)

        XCTAssertFalse(received.isEmpty, "B should have received a packet via MIDIReceived path")
        received.withFirstPacket { packet in
            XCTAssertEqual(packet.data.0, 0x91)  // note-on, channel 1
            XCTAssertEqual(packet.data.1, 48)     // pitch C3
            XCTAssertEqual(packet.data.2, 72)     // velocity
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
