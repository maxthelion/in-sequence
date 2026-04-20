import AVFoundation
import Foundation
import Observation

@Observable
final class EngineController: RouterDispatcher {
    private struct PipelineEntry: Equatable {
        let trackID: UUID
        let output: Destination.Kind
    }

    private struct AudioTrackRuntime {
        let trackID: UUID
        let generatorBlockID: BlockID
        let mix: TrackMixSettings
        let destination: Destination
        let pitchOffset: Int
    }

    private enum AudioOutputKey: Hashable {
        case track(UUID)
        case group(TrackGroupID)
    }

    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let sharedAudioOutput: TrackPlaybackSink?
    private let audioOutputFactory: (() -> TrackPlaybackSink)?
    private let stepsPerBar: Int
    private let stateLock = NSLock()
    @ObservationIgnored
    private lazy var router = MIDIRouter(dispatcher: self)

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    private let eventQueue = EventQueue()
    private let coordinator = MacroCoordinator()
    private let sampleEngine: SamplePlaybackSink
    private let sampleLibrary: AudioSampleLibrary
    private var sampleLibraryRoot: URL { sampleLibrary.libraryRoot }

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    private(set) var transportTickIndex: UInt64 = 0
    private(set) var transportPosition = "1:1:1"
    private(set) var transportMode: TransportMode = .free
    private(set) var lastNoteTriggerUptime: TimeInterval = 0
    private(set) var lastNoteTriggerCount: Int = 0
    private(set) var executor: Executor?
    private(set) var selectedOutput: Destination.Kind

    private var currentTrackMix = TrackMixSettings.default
    private var currentDocumentModel: Project = .empty
    private var generatorIDsByTrackID: [UUID: BlockID] = [:]
    private var midiOutBlocksByTrackID: [UUID: MidiOut] = [:]
    private var audioTrackRuntimes: [UUID: AudioTrackRuntime] = [:]
    private var audioOutputsByTrackID: [UUID: TrackPlaybackSink] = [:]
    private var audioOutputKeysByTrackID: [UUID: AudioOutputKey] = [:]
    private var lastDestinationByOutputKey: [AudioOutputKey: Destination] = [:]
    private var routeMidiOutputs: [Destination: MidiOut] = [:]
    private var pipelineShape: [PipelineEntry] = []
    private var routedNoteEvents: [RouteDestination: [NoteEvent]] = [:]
    private var routedChords: [(RouteDestination, Chord, String?)] = []
    private var routedMIDINotes: [Destination: [NoteEvent]] = [:]
    private var routeDispatchNow: TimeInterval = 0
    private(set) var chordContextByLane: [String: Chord] = [:]
    // Threading: written in prepareTick and read in flushConcreteDestination.
    // Both currently run on the clock-callback thread within one processTick call.
    // Do not read or mutate from other threads without revisiting this contract.
    private var currentLayerSnapshot = LayerSnapshot.empty

    private func log(_ message: String) {
        NSLog("[EngineController] \(message)")
    }

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        audioOutput: TrackPlaybackSink? = nil,
        audioOutputFactory: (() -> TrackPlaybackSink)? = nil,
        stepsPerBar: Int = 16,
        sampleEngine: SamplePlaybackSink = SamplePlaybackEngine(),
        sampleLibrary: AudioSampleLibrary = .shared
    ) {
        self.sampleEngine = sampleEngine
        self.sampleLibrary = sampleLibrary
        self.midiClient = client
        self.endpoint = endpoint
        self.sharedAudioOutput = audioOutput
        self.audioOutputFactory = audioOutputFactory
        self.stepsPerBar = max(1, stepsPerBar)
        self.registry = BlockRegistry()
        self.commandQueue = CommandQueue(capacity: 256)
        self.clock = TickClock(stepsPerBar: stepsPerBar)
        self.currentBPM = 120
        self.selectedOutput = .midi

        do {
            try registerCoreBlocks(registry)
            try buildPipeline(for: .empty)
            router.applyRoutesSnapshot(Project.empty.routes)
        } catch {
            NSLog("EngineController setup failed: \(error)")
        }
    }

    func start() {
        guard !isRunning, executor != nil else {
            return
        }

        let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
        hosts.forEach { $0.startIfNeeded() }
        try? sampleEngine.start()

        prepareTick(upcomingStep: 0, now: ProcessInfo.processInfo.systemUptime)
        isRunning = true
        clock.start { [weak self] tickIndex, now in
            self?.processTick(tickIndex: tickIndex, now: now)
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        flushAllPendingMIDINoteOffs(now: ProcessInfo.processInfo.systemUptime)
        clock.stop()
        let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
        hosts.forEach { $0.stop() }
        isRunning = false
        lastNoteTriggerUptime = 0
        lastNoteTriggerCount = 0
        sampleEngine.stop()
    }

    func setBPM(_ bpm: Double) {
        let clamped = min(max(bpm, 40), 300)
        currentBPM = clamped
        clock.bpm = clamped
        _ = commandQueue.enqueue(.setBPM(clamped))
    }

    func setTransportMode(_ mode: TransportMode) {
        transportMode = mode
    }

    func setParam(blockID: BlockID, paramKey: String, value: ParamValue) {
        _ = commandQueue.enqueue(.setParam(blockID: blockID, paramKey: paramKey, value: value))
    }

    func apply(documentModel: Project) {
        flushDetachedMIDINoteOffs(from: currentDocumentModel, to: documentModel, now: ProcessInfo.processInfo.systemUptime)
        currentDocumentModel = documentModel
        let selectedTrack = documentModel.selectedTrack
        selectedOutput = Self.effectiveDestination(for: selectedTrack.id, in: documentModel).destination.kind
        currentTrackMix = selectedTrack.mix
        router.applyRoutesSnapshot(documentModel.routes)

        do {
            if withStateLock({ pipelineShape != Self.pipelineShape(for: documentModel) || executor == nil }) {
                try buildPipeline(for: documentModel)
            } else {
                syncTrackParams(for: documentModel)
                syncMidiOutputs(for: documentModel)
                syncAudioOutputs(for: documentModel)
            }
        } catch {
            NSLog("EngineController apply failed: \(error)")
        }
    }

    func apply(track: StepSequenceTrack) {
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        apply(
            documentModel: Project(
                version: 1,
                tracks: [track],
                layers: layers,
                selectedTrackID: track.id,
                phrases: [phrase],
                selectedPhraseID: phrase.id
            )
        )
    }

    var registeredKindIDs: [String] {
        registry.kinds().map(\.id)
    }

    var canStart: Bool {
        executor != nil
    }

    var sampleEngineSink: SamplePlaybackSink { sampleEngine }

    var availableAudioInstruments: [AudioInstrumentChoice] {
        sharedAudioOutput?.availableInstruments ?? AudioInstrumentChoice.defaultChoices
    }

    var availableMIDIDestinationNames: [MIDIEndpointName] {
        var names: [MIDIEndpointName] = []
        if let endpoint {
            names.append(MIDIEndpointName(displayName: endpoint.displayName, isVirtual: true))
        } else {
            names.append(.sequencerAIOut)
        }

        let discovered = (midiClient?.destinations ?? []).map {
            MIDIEndpointName(displayName: $0.displayName, isVirtual: false)
        }
        for name in discovered where !names.contains(name) {
            names.append(name)
        }
        return names.sorted { lhs, rhs in
            if lhs == .sequencerAIOut { return true }
            if rhs == .sequencerAIOut { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func currentAudioUnit(for trackID: UUID) -> AVAudioUnit? {
        withStateLock {
            audioOutputsByTrackID[trackID]?.currentAudioUnit
        }
    }

    func prepareAudioUnit(for trackID: UUID) {
        log("prepareAudioUnit trackID=\(trackID)")
        syncAudioOutputs(for: currentDocumentModel)
        let host = withStateLock { audioOutputsByTrackID[trackID] }
        log("prepareAudioUnit hostFound=\(host != nil)")
        host?.prepareIfNeeded()
    }

    func effectiveDestination(for trackID: UUID) -> (destination: Destination, pitchOffset: Int) {
        Self.effectiveDestination(for: trackID, in: currentDocumentModel)
    }

    var statusSummary: String {
        guard canStart else {
            return "Engine unavailable"
        }

        let selectedTrack = currentDocumentModel.selectedTrack
        let (destination, _) = effectiveDestination(for: selectedTrack.id)
        switch destination {
        case .midi:
            if selectedTrack.mix.isMuted {
                return "MIDI output muted"
            }
            guard case let .midi(port, _, _) = destination,
                  let port
            else {
                return "Playing without MIDI output"
            }
            return "Output: \(port.displayName)"
        case .auInstrument:
            let host = withStateLock { audioOutputsByTrackID[selectedTrack.id] }
            guard let host else {
                return "Audio instrument unavailable"
            }
            return host.isAvailable
                ? "Audio: \(host.displayName) via Main Mixer\(selectedTrack.mix.isMuted ? " (Muted)" : "")"
                : "Audio instrument unavailable"
        case .internalSampler:
            return "Internal sampler pending"
        case .sample:
            // TODO: Task 11 will wire sample dispatch
            return "Sample playback pending"
        case .inheritGroup, .none:
            return "No default output"
        }
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        dispatchTick()
        prepareTick(upcomingStep: tickIndex &+ 1, now: now)
    }

    private func prepareTick(upcomingStep: UInt64, now: TimeInterval) {
        let (executor, audioRuntimes, audioOutputs, generatorIDs, documentModel) = withStateLock {
            (
                self.executor,
                self.audioTrackRuntimes,
                self.audioOutputsByTrackID,
                self.generatorIDsByTrackID,
                self.currentDocumentModel
            )
        }

        assert(executor != nil, "EngineController.prepareTick called without an executor.")
        guard let executor else {
            return
        }

        currentLayerSnapshot = coordinator.snapshot(
            upcomingGlobalStep: upcomingStep,
            project: documentModel,
            phraseID: documentModel.selectedPhraseID
        )

        let outputs = executor.tick(now: now)
        currentBPM = executor.currentBPM
        let completedStep = upcomingStep == 0 ? 0 : upcomingStep &- 1
        transportTickIndex = completedStep
        transportPosition = Self.transportString(for: completedStep, stepsPerBar: stepsPerBar)
        let triggeredNoteCount = outputs.values.reduce(0) { partial, ports in
            partial + ports.values.reduce(0) { nested, stream in
                if case let .notes(events) = stream {
                    return nested + events.count
                }
                return nested
            }
        }
        if triggeredNoteCount > 0 {
            lastNoteTriggerUptime = now
            lastNoteTriggerCount = triggeredNoteCount
        }

        for runtime in audioRuntimes.values where !runtime.mix.isMuted && !currentLayerSnapshot.isMuted(runtime.trackID) {
            guard case let .notes(events)? = outputs[runtime.generatorBlockID]?["notes"],
                  audioOutputs[runtime.trackID] != nil
            else {
                continue
            }

            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: now,
                    payload: .trackAU(
                        trackID: runtime.trackID,
                        destination: runtime.destination,
                        notes: Self.shifted(events, by: runtime.pitchOffset),
                        bpm: executor.currentBPM,
                        stepsPerBar: stepsPerBar
                    )
                )
            )
        }

        // Sample dispatch → queue (drum tracks and any other track with .sample destination).
        for track in documentModel.tracks {
            guard !currentLayerSnapshot.isMuted(track.id),
                  let generatorID = generatorIDs[track.id],
                  case let .notes(events)? = outputs[generatorID]?["notes"],
                  !events.isEmpty
            else { continue }
            guard case let .sample(sampleID, settings) = track.destination else { continue }
            for _ in events {
                eventQueue.enqueue(ScheduledEvent(
                    scheduledHostTime: now,
                    payload: .sampleTrigger(
                        trackID: track.id,
                        sampleID: sampleID,
                        settings: settings,
                        scheduledHostTime: now
                    )
                ))
            }
        }

        routeDispatchNow = now
        routedNoteEvents = [:]
        routedChords = []
        routedMIDINotes = [:]
        let trackInputs = documentModel.tracks.compactMap { track -> RouterTickInput? in
            guard !currentLayerSnapshot.isMuted(track.id),
                  let generatorID = generatorIDs[track.id],
                  case let .notes(events)? = outputs[generatorID]?["notes"]
            else {
                return nil
            }

            return RouterTickInput(sourceTrack: track.id, notes: events, chordContext: nil)
        }
        router.tick(trackInputs)
        flushRoutedEvents(bpm: executor.currentBPM)
    }

    private func dispatchTick() {
        let events = eventQueue.drain()
        let (audioOutputs, outputKeys) = withStateLock { (audioOutputsByTrackID, audioOutputKeysByTrackID) }

        for event in events {
            switch event.payload {
            case let .trackAU(trackID, destination, notes, bpm, stepsPerBar):
                guard let host = audioOutputs[trackID] else {
                    continue
                }
                applyDestinationIfNeeded(destination, trackID: trackID, host: host, outputKeys: outputKeys)
                host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

            case let .routedAU(trackID, destination, notes, bpm, stepsPerBar):
                guard let host = audioOutputs[trackID] else {
                    continue
                }
                applyDestinationIfNeeded(destination, trackID: trackID, host: host, outputKeys: outputKeys)
                host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

            case let .chordContextBroadcast(lane, chord):
                chordContextByLane[lane] = chord

            case .routedMIDI:
                break

            case let .sampleTrigger(_, sampleID, settings, _):
                guard let sample = sampleLibrary.sample(id: sampleID) else { continue }
                guard let url = try? sample.fileRef.resolve(libraryRoot: sampleLibraryRoot) else { continue }
                _ = sampleEngine.play(sampleURL: url, settings: settings, at: nil)
            }
        }
    }

    private func applyDestinationIfNeeded(
        _ destination: Destination,
        trackID: UUID,
        host: TrackPlaybackSink,
        outputKeys: [UUID: AudioOutputKey]
    ) {
        guard let outputKey = outputKeys[trackID] else {
            host.setDestination(destination)
            return
        }

        let shouldApply = withStateLock {
            if lastDestinationByOutputKey[outputKey] == destination {
                return false
            }
            lastDestinationByOutputKey[outputKey] = destination
            return true
        }

        if shouldApply {
            host.setDestination(destination)
        }
    }

    func dispatch(_ event: RouterEvent) {
        switch event {
        case let .note(destination, noteEvent):
            routedNoteEvents[destination, default: []].append(noteEvent)
        case let .chord(destination, chord, lane):
            routedChords.append((destination, chord, lane))
        }
    }

    private func buildPipeline(for documentModel: Project) throws {
        var blocks: [BlockID: Block] = [:]
        var wiring: [BlockID: [PortID: (BlockID, PortID)]] = [:]
        var generatorIDs: [UUID: BlockID] = [:]
        var midiOutBlocks: [UUID: MidiOut] = [:]
        var audioRuntimes: [UUID: AudioTrackRuntime] = [:]

        for track in documentModel.tracks {
            let (effectiveDestination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            let generatorBlockID = Self.generatorBlockID(for: track.id)
            let generator = NoteGenerator(id: generatorBlockID, params: Self.sourceParams(for: track, in: documentModel))
            blocks[generatorBlockID] = generator
            generatorIDs[track.id] = generatorBlockID

            switch effectiveDestination {
            case let .midi(port, channel, noteOffset):
                let midiOutBlockID = Self.midiOutBlockID(for: track.id)
                let midiOut = MidiOut(
                    id: midiOutBlockID,
                    params: [
                        "channel": .number(Double(channel)),
                        "noteOffset": .number(Double(noteOffset + pitchOffset))
                    ],
                    client: midiClient,
                    endpoint: track.mix.isMuted ? nil : (port.flatMap(resolveEndpoint(named:)))
                )
                blocks[midiOutBlockID] = midiOut
                wiring[midiOutBlockID] = ["notes": (generatorBlockID, "notes")]
                midiOutBlocks[track.id] = midiOut

            case .auInstrument:
                audioRuntimes[track.id] = AudioTrackRuntime(
                    trackID: track.id,
                    generatorBlockID: generatorBlockID,
                    mix: track.mix,
                    destination: effectiveDestination,
                    pitchOffset: pitchOffset
                )
            case .internalSampler, .sample, .inheritGroup, .none:
                // TODO: Task 11 will wire .sample dispatch
                break
            }
        }

        let nextExecutor = try Executor(
            blocks: blocks,
            wiring: wiring,
            commandQueue: commandQueue
        )

        withStateLock {
            executor = nextExecutor
            generatorIDsByTrackID = generatorIDs
            midiOutBlocksByTrackID = midiOutBlocks
            audioTrackRuntimes = audioRuntimes
            pipelineShape = Self.pipelineShape(for: documentModel)
        }

        syncAudioOutputs(for: documentModel)
        currentDocumentModel = documentModel
        selectedOutput = Self.effectiveDestination(for: documentModel.selectedTrack.id, in: documentModel).destination.kind
        currentTrackMix = documentModel.selectedTrack.mix
    }

    private func flushRoutedEvents(bpm: Double) {
        for (destination, notes) in routedNoteEvents where !notes.isEmpty {
            flushRoutedNotes(notes, to: destination, bpm: bpm)
        }

        let midiDestinationsToTick = Set(routeMidiOutputs.keys).union(routedMIDINotes.keys)
        for destination in midiDestinationsToTick {
            guard case let .midi(port, channel, _) = destination,
                  let port,
                  let midiOut = routeMidiOut(for: destination, port: port, channel: channel)
            else {
                continue
            }

            let notes = routedMIDINotes[destination] ?? []
            _ = midiOut.tick(
                context: TickContext(
                    tickIndex: transportTickIndex,
                    bpm: bpm,
                    inputs: ["notes": .notes(notes)],
                    now: routeDispatchNow
                )
            )
        }

        for (destination, chord, lane) in routedChords {
            guard case let .chordContext(broadcastTag) = destination else {
                continue
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: routeDispatchNow,
                    payload: .chordContextBroadcast(
                        lane: broadcastTag ?? lane ?? "default",
                        chord: chord
                    )
                )
            )
        }
    }

    private func flushRoutedNotes(_ notes: [NoteEvent], to destination: RouteDestination, bpm: Double) {
        switch destination {
        case let .midi(port, channel, noteOffset):
            let adjustedNotes = notes.map { note in
                let shifted = min(max(Int(note.pitch) + noteOffset, 0), 127)
                return NoteEvent(
                    pitch: UInt8(shifted),
                    velocity: note.velocity,
                    length: note.length,
                    gate: note.gate,
                    voiceTag: note.voiceTag
                )
            }
            routedMIDINotes[.midi(port: port, channel: channel, noteOffset: noteOffset), default: []]
                .append(contentsOf: adjustedNotes)

        case let .voicing(trackID):
            guard let track = currentDocumentModel.tracks.first(where: { $0.id == trackID }) else {
                return
            }
            let (destination, pitchOffset) = effectiveDestination(for: trackID)
            flushConcreteDestination(destination, notes: notes, bpm: bpm, pitchOffset: pitchOffset, track: track)

        case let .trackInput(trackID, tag):
            guard let track = currentDocumentModel.tracks.first(where: { $0.id == trackID }) else {
                return
            }
            _ = tag
            let (destination, pitchOffset) = effectiveDestination(for: trackID)
            flushConcreteDestination(destination, notes: notes, bpm: bpm, pitchOffset: pitchOffset, track: track)

        case .chordContext:
            return
        }
    }

    private func flushConcreteDestination(
        _ destination: Destination,
        notes: [NoteEvent],
        bpm: Double,
        pitchOffset: Int = 0,
        track: StepSequenceTrack?
    ) {
        switch destination {
        case let .midi(port, channel, noteOffset):
            if let track, track.mix.isMuted {
                return
            }
            guard let port else {
                return
            }
            let adjustedNotes = Self.shifted(notes, by: pitchOffset + noteOffset)
            routedMIDINotes[.midi(port: port, channel: channel, noteOffset: noteOffset), default: []]
                .append(contentsOf: adjustedNotes)

        case .auInstrument:
            guard let track,
                  !track.mix.isMuted,
                  !currentLayerSnapshot.isMuted(track.id),
                  audioOutputsByTrackID[track.id] != nil
            else {
                return
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: routeDispatchNow,
                    payload: .routedAU(
                        trackID: track.id,
                        destination: destination,
                        notes: Self.shifted(notes, by: pitchOffset),
                        bpm: bpm,
                        stepsPerBar: stepsPerBar
                    )
                )
            )

        case .internalSampler, .sample, .inheritGroup, .none:
            // TODO: Task 11 will wire .sample dispatch
            return
        }
    }

    private func routeMidiOut(
        for destination: Destination,
        port: MIDIEndpointName,
        channel: UInt8
    ) -> MidiOut? {
        guard let resolvedEndpoint = resolveEndpoint(named: port) else {
            return nil
        }

        let midiOut = routeMidiOutputs[destination] ?? {
            let block = MidiOut(
                id: "route-\(destination.hashValue)",
                client: midiClient,
                endpoint: resolvedEndpoint
            )
            routeMidiOutputs[destination] = block
            return block
        }()

        midiOut.client = midiClient
        midiOut.endpoint = resolvedEndpoint
        midiOut.apply(paramKey: "channel", value: .number(Double(channel)))
        return midiOut
    }

    private func resolveEndpoint(named port: MIDIEndpointName) -> MIDIEndpoint? {
        if port == .sequencerAIOut, let endpoint {
            return endpoint
        }

        if port.isVirtual,
           let endpoint,
           endpoint.displayName == port.displayName
        {
            return endpoint
        }

        return midiClient?.destinations.first(where: { $0.displayName == port.displayName })
    }

    private func syncTrackParams(for documentModel: Project) {
        let generatorIDs = withStateLock { generatorIDsByTrackID }
        for track in documentModel.tracks {
            guard let generatorBlockID = generatorIDs[track.id] else {
                continue
            }

            for (paramKey, value) in Self.sourceParams(for: track, in: documentModel) {
                setParam(blockID: generatorBlockID, paramKey: paramKey, value: value)
            }
        }
    }

    private func syncMidiOutputs(for documentModel: Project) {
        let midiOutBlocks = withStateLock { midiOutBlocksByTrackID }
        for track in documentModel.tracks {
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            let nextEndpoint: MIDIEndpoint?
            if case let .midi(port, channel, noteOffset) = destination,
               !track.mix.isMuted
            {
                nextEndpoint = port.flatMap(resolveEndpoint(named:))
                midiOutBlocks[track.id]?.apply(paramKey: "channel", value: .number(Double(channel)))
                midiOutBlocks[track.id]?.apply(paramKey: "noteOffset", value: .number(Double(noteOffset + pitchOffset)))
            } else {
                nextEndpoint = nil
            }
            if midiOutBlocks[track.id]?.endpoint != nil, nextEndpoint == nil {
                midiOutBlocks[track.id]?.flushPendingNoteOffs(now: ProcessInfo.processInfo.systemUptime)
            }
            midiOutBlocks[track.id]?.endpoint = nextEndpoint
        }
    }

    private func syncAudioOutputs(for documentModel: Project) {
        let desiredAudioTracks = documentModel.tracks.compactMap { track -> (StepSequenceTrack, Destination, Int, AudioOutputKey)? in
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            guard case .auInstrument = destination,
                  let key = Self.audioOutputKey(for: track, in: documentModel)
            else {
                return nil
            }
            return (track, destination, pitchOffset, key)
        }

        let previousOutputs = withStateLock { audioOutputsByTrackID }
        let previousKeys = withStateLock { audioOutputKeysByTrackID }
        let previousDestinations = withStateLock { lastDestinationByOutputKey }
        var hostsByKey: [AudioOutputKey: TrackPlaybackSink] = [:]
        var nextOutputs: [UUID: TrackPlaybackSink] = [:]
        var nextKeys: [UUID: AudioOutputKey] = [:]
        var nextDestinations: [AudioOutputKey: Destination] = [:]

        for (track, destination, _, key) in desiredAudioTracks {
            let host = hostsByKey[key] ?? {
                if let existingTrackID = previousKeys.first(where: { $0.value == key })?.key,
                   let existing = previousOutputs[existingTrackID]
                {
                    hostsByKey[key] = existing
                    return existing
                }

                let created = audioOutputFactory?() ?? sharedAudioOutput
                if let created {
                    hostsByKey[key] = created
                }
                return created
            }()

            guard let host else {
                continue
            }

            nextOutputs[track.id] = host
            nextKeys[track.id] = key
            log("syncAudioOutputs track=\(track.name) key=\(String(describing: key)) destination=\(destination.summary)")
            if previousDestinations[key] != destination {
                host.setDestination(destination)
            }
            nextDestinations[key] = destination
            host.setMix(track.mix)
            host.prepareIfNeeded()
            if isRunning {
                host.startIfNeeded()
            }
        }

        let previousUniqueHosts = Self.uniqueHosts(Array(previousOutputs.values))
        let nextUniqueHosts = Self.uniqueHosts(Array(nextOutputs.values))
        let nextHostIDs = Set(nextUniqueHosts.map { ObjectIdentifier($0) })
        let removedHosts = previousUniqueHosts.filter { !nextHostIDs.contains(ObjectIdentifier($0)) }

        withStateLock {
            audioOutputsByTrackID = nextOutputs
            audioOutputKeysByTrackID = nextKeys
            lastDestinationByOutputKey = nextDestinations
            audioTrackRuntimes = Dictionary(
                uniqueKeysWithValues: desiredAudioTracks.map {
                    (
                        $0.0.id,
                        AudioTrackRuntime(
                            trackID: $0.0.id,
                            generatorBlockID: generatorIDsByTrackID[$0.0.id] ?? Self.generatorBlockID(for: $0.0.id),
                            mix: $0.0.mix,
                            destination: $0.1,
                            pitchOffset: $0.2
                        )
                    )
                }
            )
        }

        removedHosts.forEach { $0.stop() }
    }

    private static func sourceParams(
        for track: StepSequenceTrack,
        in documentModel: Project
    ) -> [String: ParamValue] {
        if let program = noteProgram(for: track, in: documentModel),
           let encoded = encode(program: program)
        {
            return ["noteProgram": .text(encoded)]
        }

        return legacyGeneratorParams(for: track)
    }

    private static func legacyGeneratorParams(for track: StepSequenceTrack) -> [String: ParamValue] {
        [
            "noteProgram": .text(""),
            "pitches": .integers(track.pitches),
            "stepPattern": .integers(track.stepPattern.map { $0 ? 1 : 0 }),
            "accentPattern": .integers(track.stepAccents.map { $0 ? 1 : 0 }),
            "velocity": .number(Double(track.velocity)),
            "gateLength": .number(Double(track.gateLength))
        ]
    }

    private static func noteProgram(
        for track: StepSequenceTrack,
        in documentModel: Project
    ) -> NoteGenerator.NoteProgram? {
        let patternIndex = documentModel.selectedPhrase.patternIndex(for: track.id, layers: documentModel.layers)
        let slot = documentModel.patternBank(for: track.id).slot(at: patternIndex)

        switch slot.sourceRef.mode {
        case .generator:
            guard let generator = documentModel.generatorEntry(id: slot.sourceRef.generatorID) else {
                return nil
            }
            return noteProgram(for: generator, track: track, clipPool: documentModel.clipPool)
        case .clip:
            guard let clip = documentModel.clipEntry(id: slot.sourceRef.clipID) else {
                return nil
            }
            return noteProgram(for: clip)
        }
    }

    private static func noteProgram(
        for generator: GeneratorPoolEntry,
        track: StepSequenceTrack,
        clipPool: [ClipPoolEntry]
    ) -> NoteGenerator.NoteProgram? {
        switch generator.params {
        case let .mono(step, pitch, shape):
            let cycleLength = max(stepCycleLength(step, clipPool: clipPool), 1)
            var rng = SystemRandomNumberGenerator()
            var lastPitch: Int?
            let steps = (0..<cycleLength).map { stepIndex in
                guard stepFires(step, at: stepIndex, totalSteps: cycleLength, clipPool: clipPool, rng: &rng) else {
                    return [NoteGenerator.ProgrammedNote]()
                }
                let pickedPitch = resolvedPitch(
                    pitch,
                    stepIndex: stepIndex,
                    lastPitch: lastPitch,
                    clipPool: clipPool
                )
                lastPitch = pickedPitch
                return [
                    NoteGenerator.ProgrammedNote(
                        pitch: pickedPitch,
                        velocity: clampedMIDI(shape.velocity),
                        length: max(1, shape.gateLength),
                        voiceTag: nil
                    )
                ]
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)

        case let .poly(step, pitches, shape):
            let cycleLength = max(stepCycleLength(step, clipPool: clipPool), 1)
            var rng = SystemRandomNumberGenerator()
            let steps = (0..<cycleLength).map { stepIndex in
                guard stepFires(step, at: stepIndex, totalSteps: cycleLength, clipPool: clipPool, rng: &rng) else {
                    return [NoteGenerator.ProgrammedNote]()
                }
                return pitches.map { pitch in
                    NoteGenerator.ProgrammedNote(
                        pitch: resolvedPitch(pitch, stepIndex: stepIndex, lastPitch: nil, clipPool: clipPool),
                        velocity: clampedMIDI(shape.velocity),
                        length: max(1, shape.gateLength),
                        voiceTag: nil
                    )
                }
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)

        case let .drum(stepsByVoice, shape):
            let cycleLength = max(stepsByVoice.values.map { stepCycleLength($0, clipPool: clipPool) }.max() ?? 1, 1)
            var rng = SystemRandomNumberGenerator()
            let steps = (0..<cycleLength).map { stepIndex in
                stepsByVoice.compactMap { (voiceTag: String, step: StepAlgo) -> NoteGenerator.ProgrammedNote? in
                    guard stepFires(step, at: stepIndex, totalSteps: cycleLength, clipPool: clipPool, rng: &rng) else {
                        return nil
                    }
                    return NoteGenerator.ProgrammedNote(
                        pitch: Int(DrumKitNoteMap.note(for: voiceTag)),
                        velocity: clampedMIDI(shape.velocity),
                        length: max(1, shape.gateLength),
                        voiceTag: voiceTag
                    )
                }
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)

        case .template:
            return nil

        case let .slice(step, sliceIndexes):
            let cycleLength = max(stepCycleLength(step, clipPool: clipPool), 1)
            var rng = SystemRandomNumberGenerator()
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            let steps = (0..<cycleLength).map { stepIndex in
                guard stepFires(step, at: stepIndex, totalSteps: cycleLength, clipPool: clipPool, rng: &rng) else {
                    return [NoteGenerator.ProgrammedNote]()
                }
                let sliceIndex = resolvedIndexes[stepIndex % resolvedIndexes.count]
                return [
                    NoteGenerator.ProgrammedNote(
                        pitch: clampedMIDI(60 + sliceIndex),
                        velocity: clampedMIDI(track.velocity),
                        length: max(1, track.gateLength),
                        voiceTag: nil
                    )
                ]
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)
        }
    }

    private static func noteProgram(for clip: ClipPoolEntry) -> NoteGenerator.NoteProgram? {
        switch clip.content {
        case let .stepSequence(stepPattern, pitches):
            let cycleLength = max(stepPattern.count, 1)
            let resolvedPitches = pitches.isEmpty ? [60] : pitches
            let steps = (0..<cycleLength).map { stepIndex in
                guard stepPattern.indices.contains(stepIndex), stepPattern[stepIndex] else {
                    return [NoteGenerator.ProgrammedNote]()
                }
                return [
                    NoteGenerator.ProgrammedNote(
                        pitch: clampedMIDI(resolvedPitches[stepIndex % resolvedPitches.count]),
                        velocity: 100,
                        length: 4,
                        voiceTag: nil
                    )
                ]
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)

        case let .pianoRoll(lengthBars, stepsPerBar, notes):
            let cycleLength = max(1, lengthBars * stepsPerBar)
            var steps = Array(repeating: [NoteGenerator.ProgrammedNote](), count: cycleLength)
            for note in notes {
                let clampedStart = min(max(note.startStep, 0), cycleLength - 1)
                steps[clampedStart].append(
                    NoteGenerator.ProgrammedNote(
                        pitch: clampedMIDI(note.pitch),
                        velocity: clampedMIDI(note.velocity),
                        length: max(1, note.lengthSteps),
                        voiceTag: nil
                    )
                )
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)

        case let .sliceTriggers(stepPattern, sliceIndexes):
            let cycleLength = max(stepPattern.count, 1)
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            let steps = (0..<cycleLength).map { stepIndex in
                guard stepPattern.indices.contains(stepIndex), stepPattern[stepIndex] else {
                    return [NoteGenerator.ProgrammedNote]()
                }
                let sliceIndex = resolvedIndexes[stepIndex % resolvedIndexes.count]
                return [
                    NoteGenerator.ProgrammedNote(
                        pitch: clampedMIDI(60 + sliceIndex),
                        velocity: 100,
                        length: 4,
                        voiceTag: nil
                    )
                ]
            }
            return NoteGenerator.NoteProgram(cycleLength: cycleLength, steps: steps)
        }
    }

    private static func stepCycleLength(_ step: StepAlgo, clipPool: [ClipPoolEntry]) -> Int {
        switch step {
        case let .manual(pattern):
            return max(pattern.count, 1)
        case .randomWeighted:
            return 16
        case let .euclidean(_, steps, _):
            return max(steps, 1)
        case let .perStepProbability(probs):
            return max(probs.count, 1)
        case let .fromClipSteps(clipID):
            guard let clip = clipPool.first(where: { $0.id == clipID }) else {
                return 16
            }
            switch clip.content {
            case let .stepSequence(stepPattern, _), let .sliceTriggers(stepPattern, _):
                return max(stepPattern.count, 1)
            case let .pianoRoll(lengthBars, stepsPerBar, _):
                return max(1, lengthBars * stepsPerBar)
            }
        }
    }

    private static func stepFires<R: RandomNumberGenerator>(
        _ step: StepAlgo,
        at stepIndex: Int,
        totalSteps: Int,
        clipPool: [ClipPoolEntry],
        rng: inout R
    ) -> Bool {
        switch step {
        case let .fromClipSteps(clipID):
            guard let clip = clipPool.first(where: { $0.id == clipID }) else {
                return false
            }
            switch clip.content {
            case let .stepSequence(stepPattern, _), let .sliceTriggers(stepPattern, _):
                guard !stepPattern.isEmpty else { return false }
                return stepPattern[stepIndex % stepPattern.count]
            case let .pianoRoll(lengthBars, stepsPerBar, notes):
                let cycleLength = max(1, lengthBars * stepsPerBar)
                let normalizedStep = stepIndex % cycleLength
                return notes.contains { $0.startStep == normalizedStep }
            }
        default:
            return step.fires(at: stepIndex, totalSteps: totalSteps, rng: &rng)
        }
    }

    private static func resolvedPitch(
        _ pitch: PitchAlgo,
        stepIndex: Int,
        lastPitch: Int?,
        clipPool: [ClipPoolEntry]
    ) -> Int {
        switch pitch {
        case let .fromClipPitches(clipID, pickMode):
            guard let clip = clipPool.first(where: { $0.id == clipID }) else {
                return 60
            }
            let pool: [Int]
            switch clip.content {
            case let .stepSequence(_, pitches):
                pool = pitches
            case let .pianoRoll(_, _, notes):
                pool = notes.map(\.pitch)
            case let .sliceTriggers(_, sliceIndexes):
                pool = sliceIndexes.map { 60 + $0 }
            }
            guard !pool.isEmpty else {
                return 60
            }
            switch pickMode {
            case .sequential:
                return pool[stepIndex % pool.count]
            case .random:
                return pool.randomElement() ?? 60
            }
        default:
            var rng = SystemRandomNumberGenerator()
            return pitch.pick(
                context: PitchContext(
                    lastPitch: lastPitch,
                    scaleRoot: lastPitch ?? 60,
                    scaleID: .major,
                    currentChord: nil,
                    stepIndex: stepIndex
                ),
                rng: &rng
            )
        }
    }

    private static func clampedMIDI(_ value: Int) -> Int {
        min(max(value, 0), 127)
    }

    private static func encode(program: NoteGenerator.NoteProgram) -> String? {
        do {
            let data = try JSONEncoder().encode(program)
            guard let string = String(data: data, encoding: .utf8) else {
                assertionFailure("EngineController note program encoding produced invalid UTF-8")
                return nil
            }
            return string
        } catch {
            assertionFailure("EngineController note program encode failed: \(error)")
            return nil
        }
    }

    private static func generatorBlockID(for trackID: UUID) -> BlockID {
        "gen-\(trackID.uuidString.lowercased())"
    }

    private static func midiOutBlockID(for trackID: UUID) -> BlockID {
        "out-\(trackID.uuidString.lowercased())"
    }

    private static func pipelineShape(for documentModel: Project) -> [PipelineEntry] {
        documentModel.tracks.map {
            PipelineEntry(
                trackID: $0.id,
                output: Self.effectiveDestination(for: $0.id, in: documentModel).destination.kind
            )
        }
    }

    private func flushAllPendingMIDINoteOffs(now: TimeInterval) {
        let midiOutBlocks = withStateLock { Array(midiOutBlocksByTrackID.values) }
        midiOutBlocks.forEach { $0.flushPendingNoteOffs(now: now) }

        let routedOutputs = withStateLock { Array(routeMidiOutputs.values) }
        routedOutputs.forEach { $0.flushPendingNoteOffs(now: now) }
    }

    private func flushDetachedMIDINoteOffs(
        from previousDocument: Project,
        to nextDocument: Project,
        now: TimeInterval
    ) {
        let previousTracks = Dictionary(uniqueKeysWithValues: previousDocument.tracks.map { ($0.id, $0) })
        let nextTracks = Dictionary(uniqueKeysWithValues: nextDocument.tracks.map { ($0.id, $0) })
        let midiOutBlocks = withStateLock { midiOutBlocksByTrackID }

        for (trackID, previousTrack) in previousTracks {
            let previousEffective = Self.effectiveDestination(for: trackID, in: previousDocument).destination
            guard case .midi = previousEffective, !previousTrack.mix.isMuted else {
                continue
            }

            let nextTrack = nextTracks[trackID]
            let nextEffective = nextTrack.map { _ in
                Self.effectiveDestination(for: trackID, in: nextDocument).destination
            }
            let stillTargetsPrimaryMIDI = nextTrack?.mix.isMuted == false && {
                if case .midi = nextEffective {
                    return true
                }
                return false
            }()
            if !stillTargetsPrimaryMIDI {
                midiOutBlocks[trackID]?.flushPendingNoteOffs(now: now)
            }
        }

        let previousRoutedMIDIDestinations = Set(previousDocument.routes.compactMap(Self.routedMIDIDestination(from:)))
        let nextRoutedMIDIDestinations = Set(nextDocument.routes.compactMap(Self.routedMIDIDestination(from:)))
        let detachedRoutedDestinations = previousRoutedMIDIDestinations.subtracting(nextRoutedMIDIDestinations)

        let routedOutputs = withStateLock { routeMidiOutputs }
        for destination in detachedRoutedDestinations {
            routedOutputs[destination]?.flushPendingNoteOffs(now: now)
        }

        withStateLock {
            for destination in detachedRoutedDestinations {
                routeMidiOutputs.removeValue(forKey: destination)
            }
        }
    }

    private static func routedMIDIDestination(from route: Route) -> Destination? {
        guard case let .midi(port, channel, noteOffset) = route.destination else {
            return nil
        }

        return .midi(port: port, channel: channel, noteOffset: noteOffset)
    }

    private static func transportString(for tickIndex: UInt64, stepsPerBar: Int) -> String {
        let zeroBasedTick = Int(tickIndex)
        let bar = zeroBasedTick / stepsPerBar + 1
        let stepsPerBeat = max(1, stepsPerBar / 4)
        let beat = (zeroBasedTick % stepsPerBar) / stepsPerBeat + 1
        let step = zeroBasedTick % stepsPerBeat + 1
        return "\(bar):\(beat):\(step)"
    }

    private static func effectiveDestination(for trackID: UUID, in documentModel: Project) -> (destination: Destination, pitchOffset: Int) {
        guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else {
            return (.none, 0)
        }

        if case .inheritGroup = track.destination {
            guard let groupID = track.groupID,
                  let group = documentModel.trackGroups.first(where: { $0.id == groupID }),
                  let sharedDestination = group.sharedDestination
            else {
                return (.none, 0)
            }

            return (sharedDestination, group.noteMapping[trackID] ?? 0)
        }

        return (track.destination, 0)
    }

    private static func audioOutputKey(for track: StepSequenceTrack, in documentModel: Project) -> AudioOutputKey? {
        let (destination, _) = effectiveDestination(for: track.id, in: documentModel)
        guard case .auInstrument = destination else {
            return nil
        }
        if case .inheritGroup = track.destination,
           let groupID = track.groupID
        {
            return .group(groupID)
        }
        return .track(track.id)
    }

    private static func shifted(_ notes: [NoteEvent], by semitones: Int) -> [NoteEvent] {
        guard semitones != 0 else {
            return notes
        }

        return notes.map { note in
            let shiftedPitch = min(max(Int(note.pitch) + semitones, 0), 127)
            return NoteEvent(
                pitch: UInt8(shiftedPitch),
                velocity: note.velocity,
                length: note.length,
                gate: note.gate,
                voiceTag: note.voiceTag
            )
        }
    }

    private static func uniqueHosts(_ hosts: [TrackPlaybackSink]) -> [TrackPlaybackSink] {
        var seen: Set<ObjectIdentifier> = []
        return hosts.filter { host in
            seen.insert(ObjectIdentifier(host)).inserted
        }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
