import CoreMIDI
import XCTest
@testable import SequencerAI

final class TrackFanOutTests: XCTestCase {
    func test_route_can_deliver_track_output_to_additional_midi_destination() throws {
        let primaryPackets = LockedMIDIPacketStore()
        let routedPackets = LockedMIDIPacketStore()

        let primaryObserver = try MIDIClient(name: "SequencerAI_Route_Primary_Observer")
        let primaryDestination = try primaryObserver.createVirtualInput(name: "SequencerAI Route Primary") { packetList in
            primaryPackets.append(packetList)
        }
        let routedObserver = try MIDIClient(name: "SequencerAI_Route_Secondary_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Route Secondary") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_Route_Producer")
        let controller = EngineController(client: producer, endpoint: primaryDestination)

        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF") ?? UUID(),
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            output: .midiOut,
            velocity: 100,
            gateLength: 2
        )
        let phrase = PhraseModel.default(tracks: [sourceTrack])
        let route = Route(
            source: .track(sourceTrack.id),
            destination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )
        let document = SeqAIDocumentModel(
            version: 1,
            tracks: [sourceTrack],
            routes: [route],
            selectedTrackID: sourceTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        waitForPacketCount(primaryPackets, expected: 1)
        waitForPacketCount(routedPackets, expected: 1)

        XCTAssertEqual(primaryPackets.packets.first, [0x90, 60, 100])
        XCTAssertEqual(routedPackets.packets.first, [0x90, 60, 100])
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
