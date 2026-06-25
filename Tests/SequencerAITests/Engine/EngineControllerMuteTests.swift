import AVFoundation
import CoreMIDI
import XCTest
@testable import SequencerAI

final class EngineControllerMuteTests: XCTestCase {
    func test_trackSoloEffectiveMute_suppressesPrimaryAndRoutedMIDIForMutedSource() throws {
        let primaryPackets = LockedMIDIPacketStore()
        let routedPackets = LockedMIDIPacketStore()
        let primaryObserver = try MIDIClient(name: "SequencerAI_EffectiveMute_Primary_Observer")
        let primaryDestination = try primaryObserver.createVirtualInput(name: "SequencerAI Effective Mute Primary") { packetList in
            primaryPackets.append(packetList)
        }
        let routedObserver = try MIDIClient(name: "SequencerAI_EffectiveMute_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Effective Mute Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_EffectiveMute_Producer")
        let controller = EngineController(client: producer, endpoint: primaryDestination)

        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "51515151-5151-5151-5151-515151515151")!,
            name: "Muted Source",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 2
        )
        var soloedTrack = StepSequenceTrack(
            id: UUID(uuidString: "52525252-5252-5252-5252-525252525252")!,
            name: "Soloed Track",
            pitches: [72],
            stepPattern: [false],
            stepAccents: [false],
            destination: .none,
            velocity: 100,
            gateLength: 2
        )
        soloedTrack.mix.isSoloed = true

        let project = Self.routingProject(
            tracks: [sourceTrack, soloedTrack],
            routeDestination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            )
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)

        waitForNoNoteOns(primaryPackets)
        waitForNoNoteOns(routedPackets)
        XCTAssertTrue(primaryPackets.noteOnPackets.isEmpty)
        XCTAssertTrue(routedPackets.noteOnPackets.isEmpty)
    }

    func test_soloedBusEffectiveMute_suppressesPrimaryAndRoutedMIDIForMutedSource() throws {
        let primaryPackets = LockedMIDIPacketStore()
        let routedPackets = LockedMIDIPacketStore()
        let primaryObserver = try MIDIClient(name: "SequencerAI_BusMute_Primary_Observer")
        let primaryDestination = try primaryObserver.createVirtualInput(name: "SequencerAI Bus Mute Primary") { packetList in
            primaryPackets.append(packetList)
        }
        let routedObserver = try MIDIClient(name: "SequencerAI_BusMute_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Bus Mute Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_BusMute_Producer")
        let controller = EngineController(client: producer, endpoint: primaryDestination)

        let busID = UUID(uuidString: "53535353-5353-5353-5353-535353535353")!
        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "54545454-5454-5454-5454-545454545454")!,
            name: "Muted Source",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 100,
            gateLength: 2
        )
        let busTrack = StepSequenceTrack(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Bus Member",
            pitches: [72],
            stepPattern: [false],
            stepAccents: [false],
            destination: .none,
            outputBusID: busID,
            velocity: 100,
            gateLength: 2
        )
        let soloedBus = MixerBus(
            id: busID,
            name: "Solo Bus",
            mix: BusMixSettings(level: 1, pan: 0, isMuted: false, isSoloed: true)
        )
        let project = Self.routingProject(
            tracks: [sourceTrack, busTrack],
            routeDestination: .midi(
                port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
                channel: 0,
                noteOffset: 0
            ),
            buses: [soloedBus]
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)

        waitForNoNoteOns(primaryPackets)
        waitForNoNoteOns(routedPackets)
        XCTAssertTrue(primaryPackets.noteOnPackets.isEmpty)
        XCTAssertTrue(routedPackets.noteOnPackets.isEmpty)
    }

    func test_routedVoicingDestinationUsesPlaybackSnapshotInsteadOfCurrentDocumentModel() throws {
        let routedPackets = LockedMIDIPacketStore()
        let routedObserver = try MIDIClient(name: "SequencerAI_SnapshotDestination_Routed_Observer")
        let routedDestination = try routedObserver.createVirtualInput(name: "SequencerAI Snapshot Destination Routed") { packetList in
            routedPackets.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_SnapshotDestination_Producer")
        let controller = EngineController(client: producer, endpoint: nil)

        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656")!,
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .none,
            velocity: 100,
            gateLength: 2
        )
        let currentTarget = StepSequenceTrack(
            id: UUID(uuidString: "57575757-5757-5757-5757-575757575757")!,
            name: "Snapshot Target",
            pitches: [72],
            stepPattern: [false],
            stepAccents: [false],
            destination: .none,
            velocity: 100,
            gateLength: 2
        )
        var snapshotTarget = currentTarget
        snapshotTarget.destination = .midi(
            port: MIDIEndpointName(displayName: routedDestination.displayName, isVirtual: false),
            channel: 0,
            noteOffset: 0
        )

        let currentProject = Self.routingProject(
            tracks: [sourceTrack, currentTarget],
            routeDestination: .voicing(currentTarget.id)
        )
        let snapshotProject = Self.routingProject(
            tracks: [sourceTrack, snapshotTarget],
            routeDestination: .voicing(currentTarget.id)
        )

        controller.apply(documentModel: currentProject)
        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: snapshotProject))
        controller.processTick(tickIndex: 0, now: 0)

        waitForNoteOnCount(routedPackets, expected: 1)
        XCTAssertEqual(routedPackets.noteOnPackets.first, [0x90, 60, 100])
    }

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

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch), [60])
        // Mute is now a GAIN change, not a trigger-gate: the layer-muted AU
        // track KEEPS triggering its voices (so a ringing note can be cut and
        // unmute returns instantly), and the perform-layer mute is applied as
        // ramped gain via setMuteGain(true).
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.pitch), [67])
        XCTAssertEqual(createdSinks[1].muteGainHistory.last, true)
        XCTAssertFalse(createdSinks[0].muteGainHistory.contains(true))

        // The ROUTED MIDI copy of the muted source stays gated (routing is the
        // external/MIDI direction — no internal gain stage to ramp).
        waitForNoteOnCount(routedPackets, expected: 0, timeout: 0.1)
        XCTAssertTrue(routedPackets.noteOnPackets.isEmpty)
    }

    private static func routingProject(
        tracks: [StepSequenceTrack],
        routeDestination: RouteDestination,
        buses: [MixerBus] = []
    ) -> Project {
        let generators = tracks.map { track in
            monoGeneratorEntry(
                id: UUID(),
                name: "\(track.name) Program",
                trackType: track.trackType,
                pattern: track.stepPattern,
                pitch: track.pitches.first ?? 60,
                velocity: Int(track.velocity),
                gateLength: track.gateLength
            )
        }
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: generators,
            clipPool: []
        )
        let patternBanks = zip(tracks, generators).map { track, generator in
            TrackPatternBank(
                trackID: track.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
            )
        }

        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [Route(source: .track(tracks[0].id), destination: routeDestination)],
            buses: buses,
            patternBanks: patternBanks,
            selectedTrackID: tracks[0].id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mute Test Sink"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit? = nil
    private(set) var receivedEvents: [[NoteEvent]] = []
    private(set) var muteGainHistory: [Bool] = []

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}
    func setMix(_ mix: TrackMixSettings) {}
    func setMuteGain(_ muted: Bool) { muteGainHistory.append(muted) }
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

private func waitForNoNoteOns(
    _ store: LockedMIDIPacketStore,
    timeout: TimeInterval = 0.1
) {
    RunLoop.current.run(until: Date().addingTimeInterval(timeout))
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
            trigger: .native(euclideanAlgo(matching: pattern)),
            pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
            shape: NoteShape(velocity: velocity, gateLength: gateLength, accent: false)
        )
    )
}
