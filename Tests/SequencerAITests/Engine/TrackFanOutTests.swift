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
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 2
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [sourceTrack])
        let generator = fanOutGeneratorEntry(for: sourceTrack)
        let phrase = PhraseModel.default(tracks: [sourceTrack], layers: layers, generatorPool: [generator], clipPool: [])
        let route = Route(
            source: .track(sourceTrack.id),
            destination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )
        let document = Project(
            version: 1,
            tracks: [sourceTrack],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [route],
            patternBanks: [TrackPatternBank(trackID: sourceTrack.id, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))])],
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

    func test_stop_flushes_pending_note_offs_for_primary_and_routed_midi_outputs() throws {
        let primaryPackets = LockedMIDIPacketStore()
        let routedPackets = LockedMIDIPacketStore()

        let primaryObserver = try MIDIClient(name: "SequencerAI_StopFlush_Primary_Observer")
        let primaryDestination = try primaryObserver.createVirtualInput(name: "SequencerAI Stop Flush Primary") { packetList in
            primaryPackets.append(packetList)
        }
        let routedObserver = try MIDIClient(name: "SequencerAI_StopFlush_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Stop Flush Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_StopFlush_Producer")
        let controller = EngineController(client: producer, endpoint: primaryDestination)

        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB") ?? UUID(),
            name: "Source",
            pitches: [60],
            stepPattern: [true] + Array(repeating: false, count: 15),
            stepAccents: Array(repeating: false, count: 16),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 8
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [sourceTrack])
        let generator = fanOutGeneratorEntry(for: sourceTrack)
        let phrase = PhraseModel.default(tracks: [sourceTrack], layers: layers, generatorPool: [generator], clipPool: [])
        let route = Route(
            source: .track(sourceTrack.id),
            destination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )
        let document = Project(
            version: 1,
            tracks: [sourceTrack],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [route],
            patternBanks: [TrackPatternBank(trackID: sourceTrack.id, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))])],
            selectedTrackID: sourceTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.start()
        waitForNoteOnCount(primaryPackets, expected: 1)
        waitForNoteOnCount(routedPackets, expected: 1)

        controller.stop()

        waitForNoteOffCount(primaryPackets, expected: 1)
        waitForNoteOffCount(routedPackets, expected: 1)

        XCTAssertEqual(primaryPackets.noteOffPackets.last, [0x80, 60, 0])
        XCTAssertEqual(routedPackets.noteOffPackets.last, [0x80, 60, 0])
    }

    func test_apply_flushes_pending_note_offs_before_detaching_midi_destinations() throws {
        let primaryPackets = LockedMIDIPacketStore()
        let routedPackets = LockedMIDIPacketStore()

        let primaryObserver = try MIDIClient(name: "SequencerAI_DetachFlush_Primary_Observer")
        let primaryDestination = try primaryObserver.createVirtualInput(name: "SequencerAI Detach Flush Primary") { packetList in
            primaryPackets.append(packetList)
        }
        let routedObserver = try MIDIClient(name: "SequencerAI_DetachFlush_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Detach Flush Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_DetachFlush_Producer")
        let controller = EngineController(client: producer, endpoint: primaryDestination)

        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD") ?? UUID(),
            name: "Source",
            pitches: [64],
            stepPattern: [true],
            stepAccents: [false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 8
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [sourceTrack])
        let generator = fanOutGeneratorEntry(for: sourceTrack)
        let phrase = PhraseModel.default(tracks: [sourceTrack], layers: layers, generatorPool: [generator], clipPool: [])
        let route = Route(
            source: .track(sourceTrack.id),
            destination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )
        let activeDocument = Project(
            version: 1,
            tracks: [sourceTrack],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [route],
            patternBanks: [TrackPatternBank(trackID: sourceTrack.id, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))])],
            selectedTrackID: sourceTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: activeDocument)
        controller.processTick(tickIndex: 0, now: 0)

        waitForNoteOnCount(primaryPackets, expected: 1)
        waitForNoteOnCount(routedPackets, expected: 1)

        var detachedTrack = sourceTrack
        detachedTrack.destination = .none
        let detachedDocument = Project(
            version: 1,
            tracks: [detachedTrack],
            routes: [],
            selectedTrackID: detachedTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: detachedDocument)

        waitForNoteOffCount(primaryPackets, expected: 1)
        waitForNoteOffCount(routedPackets, expected: 1)

        XCTAssertEqual(primaryPackets.noteOffPackets.last, [0x80, 64, 0])
        XCTAssertEqual(routedPackets.noteOffPackets.last, [0x80, 64, 0])
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

    var noteOnPackets: [[UInt8]] {
        packets.filter { packet in
            packet.count >= 3 && (packet[0] & 0xF0) == 0x90 && packet[2] > 0
        }
    }

    var noteOffPackets: [[UInt8]] {
        packets.filter { packet in
            packet.count >= 3 && (packet[0] & 0xF0) == 0x80
        }
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

private func waitForNoteOnCount(
    _ store: LockedMIDIPacketStore,
    expected: Int,
    timeout: TimeInterval = 1.0
) {
    let deadline = Date().addingTimeInterval(timeout)
    while store.noteOnPackets.count < expected && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}

private func waitForNoteOffCount(
    _ store: LockedMIDIPacketStore,
    expected: Int,
    timeout: TimeInterval = 1.0
) {
    let deadline = Date().addingTimeInterval(timeout)
    while store.noteOffPackets.count < expected && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}

private func fanOutGeneratorEntry(for track: StepSequenceTrack) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: UUID(),
        name: "\(track.name) Generator",
        trackType: track.trackType,
        kind: .monoGenerator,
        params: .mono(
            trigger: .native(euclideanAlgo(matching: track.stepPattern)),
            pitch: .native(.manual(pitches: [track.pitches.first ?? 60], pickMode: .sequential)),
            shape: NoteShape(velocity: Int(track.velocity), gateLength: track.gateLength, accent: false)
        )
    )
}
