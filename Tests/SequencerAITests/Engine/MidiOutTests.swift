import CoreMIDI
import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

final class MidiOutTests: XCTestCase {
    func test_single_note_emits_note_on_then_note_off_at_gate_length() throws {
        let received = LockedMIDIPacketStore()
        let observer = try MIDIClient(name: "SequencerAI_MidiOut_Observer_1")
        let destination = try observer.createVirtualInput(name: "SequencerAI_MidiOut_Destination_1") { packetList in
            received.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_MidiOut_Producer_1")
        let block = MidiOut(id: "out", client: producer, endpoint: destination)

        _ = block.tick(context: makeContext(
            tickIndex: 0,
            now: 0,
            notes: [NoteEvent(pitch: 60, velocity: 100, length: 4, gate: true, voiceTag: nil)]
        ))
        waitForPacketCount(received, expected: 1)
        _ = block.tick(context: makeContext(tickIndex: 4, now: 0.25, notes: []))
        waitForPacketCount(received, expected: 2)

        XCTAssertEqual(received.packets[0], [0x90, 60, 100])
        XCTAssertEqual(received.packets[1], [0x80, 60, 0])
    }

    func test_empty_note_input_sends_nothing() throws {
        let received = LockedMIDIPacketStore()
        let observer = try MIDIClient(name: "SequencerAI_MidiOut_Observer_2")
        let destination = try observer.createVirtualInput(name: "SequencerAI_MidiOut_Destination_2") { packetList in
            received.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_MidiOut_Producer_2")
        let block = MidiOut(id: "out", client: producer, endpoint: destination)

        _ = block.tick(context: makeContext(tickIndex: 0, now: 0, notes: []))

        waitForPacketCount(received, expected: 0, timeout: 0.2)
        XCTAssertTrue(received.packets.isEmpty)
    }

    func test_chord_emits_all_note_ons_and_note_offs() throws {
        let received = LockedMIDIPacketStore()
        let observer = try MIDIClient(name: "SequencerAI_MidiOut_Observer_3")
        let destination = try observer.createVirtualInput(name: "SequencerAI_MidiOut_Destination_3") { packetList in
            received.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_MidiOut_Producer_3")
        let block = MidiOut(id: "out", client: producer, endpoint: destination)
        let notes = [
            NoteEvent(pitch: 60, velocity: 100, length: 2, gate: true, voiceTag: nil),
            NoteEvent(pitch: 64, velocity: 100, length: 2, gate: true, voiceTag: nil),
            NoteEvent(pitch: 67, velocity: 100, length: 2, gate: true, voiceTag: nil)
        ]

        _ = block.tick(context: makeContext(tickIndex: 0, now: 0, notes: notes))
        waitForPacketCount(received, expected: 3)
        _ = block.tick(context: makeContext(tickIndex: 2, now: 0.125, notes: []))
        waitForPacketCount(received, expected: 6)

        XCTAssertEqual(Array(received.packets.prefix(3)).map { $0[1] }, [60, 64, 67])
        XCTAssertEqual(Array(received.packets.prefix(3)).map { $0[0] }, [0x90, 0x90, 0x90])
        XCTAssertEqual(Array(received.packets.suffix(3)).map { $0[0] }, [0x80, 0x80, 0x80])
    }

    func test_channel_param_controls_status_byte() throws {
        let received = LockedMIDIPacketStore()
        let observer = try MIDIClient(name: "SequencerAI_MidiOut_Observer_4")
        let destination = try observer.createVirtualInput(name: "SequencerAI_MidiOut_Destination_4") { packetList in
            received.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_MidiOut_Producer_4")
        let block = MidiOut(
            id: "out",
            params: ["channel": .number(5)],
            client: producer,
            endpoint: destination
        )

        _ = block.tick(context: makeContext(
            tickIndex: 0,
            now: 0,
            notes: [NoteEvent(pitch: 60, velocity: 100, length: 1, gate: true, voiceTag: nil)]
        ))
        waitForPacketCount(received, expected: 1)

        XCTAssertEqual(received.packets[0][0], 0x95)
    }

    func test_registers_in_block_registry_under_midi_out() throws {
        let registry = BlockRegistry()

        try registerCoreBlocks(registry)
        let block = registry.make(kindID: "midi-out", blockID: "out")

        XCTAssertTrue(block is MidiOut)
    }

    private func makeContext(
        tickIndex: UInt64,
        now: TimeInterval,
        notes: [NoteEvent]
    ) -> TickContext {
        TickContext(
            tickIndex: tickIndex,
            bpm: 120,
            inputs: ["notes": EngineStream.notes(notes)],
            now: now,
            preparedNotesByBlockID: [:]
        )
    }

    private func waitForPacketCount(
        _ store: LockedMIDIPacketStore,
        expected: Int,
        timeout: TimeInterval = 1.0
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while store.packets.count < expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

private final class LockedMIDIPacketStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[UInt8]] = []

    func append(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock()
        defer { lock.unlock() }

        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
        var packet = UnsafeMutableRawPointer(mutating: packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            let current = packet.pointee
            let length = Int(current.length)
            let bytes = withUnsafeBytes(of: current.data) { data in
                Array(data.prefix(length))
            }
            for index in stride(from: 0, to: bytes.count, by: 3) {
                let end = min(index + 3, bytes.count)
                storage.append(Array(bytes[index..<end]))
            }
            packet = MIDIPacketNext(packet)
        }
    }

    var packets: [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
