import CoreMIDI
import XCTest
@testable import SequencerAI

final class EngineIntegrationTests: XCTestCase {
    func test_engine_emits_expected_midi_for_half_second_run() throws {
        let queue = CommandQueue(capacity: 128)
        let clock = TickClock(stepsPerBar: 16)
        let recorder = IntegrationMIDIPacketRecorder()
        let producer = try MIDIClient(name: "SequencerAI_Engine_Producer_1")
        let observer = try MIDIClient(name: "SequencerAI_Engine_Observer_1")
        let destination = try observer.createVirtualInput(name: "SequencerAI_Engine_Destination_1") { packetList in
            recorder.append(packetList)
        }
        let executor = try makeExecutor(
            queue: queue,
            producerClient: producer,
            endpoint: destination,
            noteGeneratorParams: [
                "pitches": .integers([60]),
                "stepPattern": .integers([1]),
                "velocity": .number(100),
                "gateLength": .number(4)
            ]
        )

        queue.enqueue(.setBPM(480))
        clock.bpm = 480
        clock.start { _, now in
            _ = executor.tick(now: now)
        }

        let finished = expectation(description: "engine run finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            clock.stop()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1.0)

        XCTAssertGreaterThanOrEqual(recorder.noteOnCount, 14)
    }

    func test_setBPM_mid_run_expands_note_intervals() throws {
        let queue = CommandQueue(capacity: 128)
        let clock = TickClock(stepsPerBar: 16)
        let recorder = IntegrationMIDIPacketRecorder()
        let producer = try MIDIClient(name: "SequencerAI_Engine_Producer_2")
        let observer = try MIDIClient(name: "SequencerAI_Engine_Observer_2")
        let destination = try observer.createVirtualInput(name: "SequencerAI_Engine_Destination_2") { packetList in
            recorder.append(packetList)
        }
        let executor = try makeExecutor(
            queue: queue,
            producerClient: producer,
            endpoint: destination,
            noteGeneratorParams: [
                "pitches": .integers([60]),
                "stepPattern": .integers([1]),
                "velocity": .number(100),
                "gateLength": .number(4)
            ]
        )

        queue.enqueue(.setBPM(480))
        clock.bpm = 480
        clock.start { _, now in
            _ = executor.tick(now: now)
        }

        let finished = expectation(description: "bpm change observed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            queue.enqueue(.setBPM(120))
            clock.bpm = 120
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            clock.stop()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1.0)

        let deltas = recorder.noteOnDeltas
        XCTAssertGreaterThanOrEqual(deltas.count, 6)

        let earlyAverage = average(Array(deltas.prefix(3)))
        let lateAverage = average(Array(deltas.suffix(2)))

        XCTAssertGreaterThan(lateAverage, earlyAverage * 2.5)
    }

    func test_setParam_mid_run_changes_generated_pitch_set() throws {
        let queue = CommandQueue(capacity: 128)
        let clock = TickClock(stepsPerBar: 16)
        let recorder = IntegrationMIDIPacketRecorder()
        let producer = try MIDIClient(name: "SequencerAI_Engine_Producer_3")
        let observer = try MIDIClient(name: "SequencerAI_Engine_Observer_3")
        let destination = try observer.createVirtualInput(name: "SequencerAI_Engine_Destination_3") { packetList in
            recorder.append(packetList)
        }
        let executor = try makeExecutor(
            queue: queue,
            producerClient: producer,
            endpoint: destination,
            noteGeneratorParams: [
                "pitches": .integers([60]),
                "stepPattern": .integers([1]),
                "velocity": .number(100),
                "gateLength": .number(4)
            ]
        )

        queue.enqueue(.setBPM(240))
        clock.bpm = 240
        clock.start { _, now in
            _ = executor.tick(now: now)
        }

        let finished = expectation(description: "param change observed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            queue.enqueue(.setParam(blockID: "gen", paramKey: "pitches", value: .integers([60, 64, 67])))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            clock.stop()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1.0)

        let pitches = recorder.noteOnPitches
        XCTAssertGreaterThanOrEqual(pitches.count, 8)
        XCTAssertTrue(Array(pitches.prefix(4)).allSatisfy { $0 == 60 })
        XCTAssertTrue(pitches.contains(64) || pitches.contains(67))
    }

    private func makeExecutor(
        queue: CommandQueue,
        producerClient: MIDIClient,
        endpoint: MIDIEndpoint,
        noteGeneratorParams: [String: ParamValue]
    ) throws -> Executor {
        let generator = NoteGenerator(id: "gen", params: noteGeneratorParams)
        let midiOut = MidiOut(
            id: "out",
            params: ["channel": .number(0)],
            client: producerClient,
            endpoint: endpoint
        )
        return try Executor(
            blocks: [
                "gen": generator,
                "out": midiOut
            ],
            wiring: [
                "out": ["notes": ("gen", "notes")]
            ],
            commandQueue: queue
        )
    }

    private func average(_ values: [TimeInterval]) -> TimeInterval {
        values.reduce(0, +) / Double(values.count)
    }
}

private final class IntegrationMIDIPacketRecorder: @unchecked Sendable {
    private struct Message {
        let timestamp: TimeInterval
        let bytes: [UInt8]
    }

    private let lock = NSLock()
    private var messages: [Message] = []

    func append(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock()
        defer { lock.unlock() }

        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
        var packet = UnsafeMutableRawPointer(mutating: packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetList.pointee.numPackets {
            let current = packet.pointee
            let timestamp = TimeInterval(current.timeStamp) / 1_000_000_000
            let length = Int(current.length)
            let bytes = withUnsafeBytes(of: current.data) { data in
                Array(data.prefix(length))
            }

            for index in stride(from: 0, to: bytes.count, by: 3) {
                let end = min(index + 3, bytes.count)
                let message = Array(bytes[index..<end])
                messages.append(Message(timestamp: timestamp, bytes: message))
            }

            packet = MIDIPacketNext(packet)
        }
    }

    var noteOnCount: Int {
        noteOnMessages.count
    }

    var noteOnPitches: [UInt8] {
        noteOnMessages.compactMap { $0.bytes.count > 1 ? $0.bytes[1] : nil }
    }

    var noteOnDeltas: [TimeInterval] {
        let timestamps = noteOnMessages.map(\.timestamp)
        guard timestamps.count > 1 else {
            return []
        }
        return zip(timestamps, timestamps.dropFirst()).map { $1 - $0 }
    }

    private var noteOnMessages: [Message] {
        lock.lock()
        defer { lock.unlock() }
        return messages.filter { message in
            guard let status = message.bytes.first else {
                return false
            }
            return (status & 0xF0) == 0x90 && message.bytes.count >= 3 && message.bytes[2] > 0
        }
    }
}
