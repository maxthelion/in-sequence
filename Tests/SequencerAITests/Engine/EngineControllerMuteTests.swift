import AVFoundation
import CoreMIDI
import XCTest
@testable import SequencerAI

final class EngineControllerMuteTests: XCTestCase {
    func test_phraseMuteCell_suppresses_directAudioAndRoutedMIDIForMutedTrack() throws {
        let routedPackets = LockedMIDIPacketStore()
        let routedObserver = try MIDIClient(name: "SequencerAI_Mute_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Mute Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_Mute_Producer")

        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: producer,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )

        let leadTrack = StepSequenceTrack(
            id: UUID(uuidString: "10101010-1010-1010-1010-101010101010") ?? UUID(),
            name: "Lead",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 2
        )
        let mutedTrack = StepSequenceTrack(
            id: UUID(uuidString: "20202020-2020-2020-2020-202020202020") ?? UUID(),
            name: "Muted",
            pitches: [67],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 96,
            gateLength: 2
        )

        let leadGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "30303030-3030-3030-3030-303030303030")!,
            name: "Lead Program",
            trackType: leadTrack.trackType,
            pattern: [true],
            pitch: 60,
            velocity: 100,
            gateLength: 2
        )
        let mutedGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "40404040-4040-4040-4040-404040404040")!,
            name: "Muted Program",
            trackType: mutedTrack.trackType,
            pattern: [true],
            pitch: 67,
            velocity: 96,
            gateLength: 2
        )
        let generators = [leadGenerator, mutedGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [leadTrack, mutedTrack])
        let muteLayer = try XCTUnwrap(layers.first(where: { $0.target == .mute }))
        var phrase = PhraseModel.default(
            tracks: [leadTrack, mutedTrack],
            layers: layers,
            generatorPool: generators,
            clipPool: []
        )
        phrase.setCell(.single(.bool(true)), for: muteLayer.id, trackID: mutedTrack.id)

        let route = Route(
            source: .track(mutedTrack.id),
            destination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )
        let patternBanks = [
            TrackPatternBank(
                trackID: leadTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(leadGenerator.id))]
            ),
            TrackPatternBank(
                trackID: mutedTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(mutedGenerator.id))]
            )
        ]
        let project = Project(
            version: 1,
            tracks: [leadTrack, mutedTrack],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [route],
            patternBanks: patternBanks,
            selectedTrackID: leadTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch), [60])
        XCTAssertTrue(createdSinks[1].receivedEvents.isEmpty)

        waitForNoteOnCount(routedPackets, expected: 0, timeout: 0.1)
        XCTAssertTrue(routedPackets.noteOnPackets.isEmpty)
    }
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mute Test Sink"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit? = nil
    private(set) var receivedEvents: [[NoteEvent]] = []

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func setMix(_ mix: TrackMixSettings) {}
    func setDestination(_ destination: Destination) {
        if case let .auInstrument(componentID, _) = destination {
            selectedInstrument = availableInstruments.first(where: { $0.audioComponentID == componentID }) ?? .builtInSynth
        }
    }
    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }
    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        receivedEvents.append(noteEvents)
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

private func monoGeneratorEntry(
    id: UUID,
    name: String,
    trackType: TrackType,
    pattern: [Bool],
    pitch: Int,
    velocity: Int,
    gateLength: Int
) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: id,
        name: name,
        trackType: trackType,
        kind: .monoGenerator,
        params: .mono(
            step: .manual(pattern: pattern),
            pitch: .manual(pitches: [pitch], pickMode: .sequential),
            shape: NoteShape(velocity: velocity, gateLength: gateLength, accent: false)
        )
    )
}
