import AVFoundation
import Foundation
import Observation

@Observable
final class EngineController: RouterDispatcher {
    private struct PipelineEntry: Equatable {
        let trackID: UUID
        let output: TrackOutputDestination
    }

    private struct AudioTrackRuntime {
        let trackID: UUID
        let generatorBlockID: BlockID
        let mix: TrackMixSettings
        let destination: Destination
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

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    private(set) var transportTickIndex: UInt64 = 0
    private(set) var transportPosition = "1:1:1"
    private(set) var executor: Executor?
    private(set) var selectedOutput: TrackOutputDestination

    private var currentTrackMix = TrackMixSettings.default
    private var currentDocumentModel: SeqAIDocumentModel = .empty
    private var generatorIDsByTrackID: [UUID: BlockID] = [:]
    private var midiOutBlocksByTrackID: [UUID: MidiOut] = [:]
    private var audioTrackRuntimes: [UUID: AudioTrackRuntime] = [:]
    private var audioOutputsByTrackID: [UUID: TrackPlaybackSink] = [:]
    private var routeMidiOutputs: [Destination: MidiOut] = [:]
    private var pipelineShape: [PipelineEntry] = []
    private var routedNoteEvents: [RouteDestination: [NoteEvent]] = [:]
    private var routedChords: [(RouteDestination, Chord, String?)] = []
    private var routedMIDINotes: [Destination: [NoteEvent]] = [:]
    private var routeDispatchNow: TimeInterval = 0
    private(set) var chordContextByLane: [String: Chord] = [:]

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        audioOutput: TrackPlaybackSink? = nil,
        audioOutputFactory: (() -> TrackPlaybackSink)? = nil,
        stepsPerBar: Int = 16
    ) {
        self.midiClient = client
        self.endpoint = endpoint
        self.sharedAudioOutput = audioOutput
        self.audioOutputFactory = audioOutputFactory
        self.stepsPerBar = max(1, stepsPerBar)
        self.registry = BlockRegistry()
        self.commandQueue = CommandQueue(capacity: 256)
        self.clock = TickClock(stepsPerBar: stepsPerBar)
        self.currentBPM = 120
        self.selectedOutput = .midiOut

        do {
            try registerCoreBlocks(registry)
            try buildPipeline(for: .empty)
            router.applyRoutesSnapshot(SeqAIDocumentModel.empty.routes)
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
    }

    func setBPM(_ bpm: Double) {
        let clamped = min(max(bpm, 40), 300)
        currentBPM = clamped
        clock.bpm = clamped
        _ = commandQueue.enqueue(.setBPM(clamped))
    }

    func setParam(blockID: BlockID, paramKey: String, value: ParamValue) {
        _ = commandQueue.enqueue(.setParam(blockID: blockID, paramKey: paramKey, value: value))
    }

    func apply(documentModel: SeqAIDocumentModel) {
        flushDetachedMIDINoteOffs(from: currentDocumentModel, to: documentModel, now: ProcessInfo.processInfo.systemUptime)
        currentDocumentModel = documentModel
        let selectedTrack = documentModel.selectedTrack
        selectedOutput = selectedTrack.output
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
        let phrase = PhraseModel.default(tracks: [track])
        apply(
            documentModel: SeqAIDocumentModel(
                version: 1,
                tracks: [track],
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

    var statusSummary: String {
        guard canStart else {
            return "Engine unavailable"
        }

        let selectedTrack = currentDocumentModel.selectedTrack
        switch selectedTrack.output {
        case .midiOut:
            if selectedTrack.mix.isMuted {
                return "MIDI output muted"
            }
            guard let endpoint else {
                return "Playing without MIDI output"
            }
            return "Output: \(endpoint.displayName)"
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
        case .none:
            return "No default output"
        }
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        let (executor, audioRuntimes, audioOutputs, generatorIDs, documentModel) = withStateLock {
            (
                self.executor,
                self.audioTrackRuntimes,
                self.audioOutputsByTrackID,
                self.generatorIDsByTrackID,
                self.currentDocumentModel
            )
        }

        guard let executor else {
            return
        }

        let outputs = executor.tick(now: now)
        currentBPM = executor.currentBPM
        transportTickIndex = tickIndex
        transportPosition = Self.transportString(for: tickIndex, stepsPerBar: stepsPerBar)

        for runtime in audioRuntimes.values where !runtime.mix.isMuted {
            guard case let .notes(events)? = outputs[runtime.generatorBlockID]?["notes"],
                  let host = audioOutputs[runtime.trackID]
            else {
                continue
            }

            host.setDestination(runtime.destination)
            host.play(noteEvents: events, bpm: executor.currentBPM, stepsPerBar: stepsPerBar)
        }

        routeDispatchNow = now
        routedNoteEvents = [:]
        routedChords = []
        routedMIDINotes = [:]
        let trackInputs = documentModel.tracks.compactMap { track -> RouterTickInput? in
            guard let generatorID = generatorIDs[track.id],
                  case let .notes(events)? = outputs[generatorID]?["notes"]
            else {
                return nil
            }

            return RouterTickInput(sourceTrack: track.id, notes: events, chordContext: nil)
        }
        router.tick(trackInputs)
        flushRoutedEvents(bpm: executor.currentBPM)
    }

    func dispatch(_ event: RouterEvent) {
        switch event {
        case let .note(destination, noteEvent):
            routedNoteEvents[destination, default: []].append(noteEvent)
        case let .chord(destination, chord, lane):
            routedChords.append((destination, chord, lane))
        }
    }

    private func buildPipeline(for documentModel: SeqAIDocumentModel) throws {
        var blocks: [BlockID: Block] = [:]
        var wiring: [BlockID: [PortID: (BlockID, PortID)]] = [:]
        var generatorIDs: [UUID: BlockID] = [:]
        var midiOutBlocks: [UUID: MidiOut] = [:]
        var audioRuntimes: [UUID: AudioTrackRuntime] = [:]

        for track in documentModel.tracks {
            let generatorBlockID = Self.generatorBlockID(for: track.id)
            let generator = NoteGenerator(id: generatorBlockID, params: Self.generatorParams(for: track))
            blocks[generatorBlockID] = generator
            generatorIDs[track.id] = generatorBlockID

            switch track.output {
            case .midiOut:
                let midiOutBlockID = Self.midiOutBlockID(for: track.id)
                let midiOut = MidiOut(
                    id: midiOutBlockID,
                    params: ["channel": .number(0)],
                    client: midiClient,
                    endpoint: track.mix.isMuted ? nil : endpoint
                )
                blocks[midiOutBlockID] = midiOut
                wiring[midiOutBlockID] = ["notes": (generatorBlockID, "notes")]
                midiOutBlocks[track.id] = midiOut

            case .auInstrument:
                audioRuntimes[track.id] = AudioTrackRuntime(
                    trackID: track.id,
                    generatorBlockID: generatorBlockID,
                    mix: track.mix,
                    destination: track.defaultDestination
                )
            case .internalSampler, .none:
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
        selectedOutput = documentModel.selectedTrack.output
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
            chordContextByLane[broadcastTag ?? lane ?? "default"] = chord
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
            flushConcreteDestination(track.defaultDestination, notes: notes, bpm: bpm, track: track)

        case let .trackInput(trackID, tag):
            guard let track = currentDocumentModel.tracks.first(where: { $0.id == trackID }) else {
                return
            }
            _ = tag
            flushConcreteDestination(track.defaultDestination, notes: notes, bpm: bpm, track: track)

        case .chordContext:
            return
        }
    }

    private func flushConcreteDestination(
        _ destination: Destination,
        notes: [NoteEvent],
        bpm: Double,
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

        case .auInstrument:
            guard let track,
                  !track.mix.isMuted,
                  let host = audioOutputsByTrackID[track.id]
            else {
                return
            }
            host.setDestination(destination)
            host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

        case .internalSampler, .inheritGroup, .none:
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
        if port.isVirtual,
           let endpoint,
           endpoint.displayName == port.displayName
        {
            return endpoint
        }

        return midiClient?.destinations.first(where: { $0.displayName == port.displayName })
    }

    private func syncTrackParams(for documentModel: SeqAIDocumentModel) {
        let generatorIDs = withStateLock { generatorIDsByTrackID }
        for track in documentModel.tracks {
            guard let generatorBlockID = generatorIDs[track.id] else {
                continue
            }

            for (paramKey, value) in Self.generatorParams(for: track) {
                setParam(blockID: generatorBlockID, paramKey: paramKey, value: value)
            }
        }
    }

    private func syncMidiOutputs(for documentModel: SeqAIDocumentModel) {
        let midiOutBlocks = withStateLock { midiOutBlocksByTrackID }
        for track in documentModel.tracks {
            let nextEndpoint = track.output == .midiOut && !track.mix.isMuted ? endpoint : nil
            if midiOutBlocks[track.id]?.endpoint != nil, nextEndpoint == nil {
                midiOutBlocks[track.id]?.flushPendingNoteOffs(now: ProcessInfo.processInfo.systemUptime)
            }
            midiOutBlocks[track.id]?.endpoint = nextEndpoint
        }
    }

    private func syncAudioOutputs(for documentModel: SeqAIDocumentModel) {
        let desiredAudioTracks = documentModel.tracks.filter { $0.output == .auInstrument }
        let desiredTrackIDs = Set(desiredAudioTracks.map(\.id))

        let removedHosts = withStateLock { () -> [TrackPlaybackSink] in
            let removedIDs = Set(audioOutputsByTrackID.keys).subtracting(desiredTrackIDs)
            let hosts = removedIDs.compactMap { audioOutputsByTrackID.removeValue(forKey: $0) }
            return hosts
        }
        removedHosts.forEach { $0.stop() }

        for track in desiredAudioTracks {
            let host = withStateLock { () -> TrackPlaybackSink? in
                if let existing = audioOutputsByTrackID[track.id] {
                    return existing
                }

                let created = audioOutputFactory?() ?? sharedAudioOutput
                if let created {
                    audioOutputsByTrackID[track.id] = created
                }
                return created
            }

            host?.setDestination(track.defaultDestination)
            host?.setMix(track.mix)
            if isRunning {
                host?.startIfNeeded()
            }
        }

        withStateLock {
            audioTrackRuntimes = Dictionary(
                uniqueKeysWithValues: desiredAudioTracks.map {
                    (
                        $0.id,
                        AudioTrackRuntime(
                            trackID: $0.id,
                            generatorBlockID: generatorIDsByTrackID[$0.id] ?? Self.generatorBlockID(for: $0.id),
                            mix: $0.mix,
                            destination: $0.defaultDestination
                        )
                    )
                }
            )
        }
    }

    private static func generatorParams(for track: StepSequenceTrack) -> [String: ParamValue] {
        [
            "pitches": .integers(track.pitches),
            "stepPattern": .integers(track.stepPattern.map { $0 ? 1 : 0 }),
            "accentPattern": .integers(track.stepAccents.map { $0 ? 1 : 0 }),
            "velocity": .number(Double(track.velocity)),
            "gateLength": .number(Double(track.gateLength))
        ]
    }

    private static func generatorBlockID(for trackID: UUID) -> BlockID {
        "gen-\(trackID.uuidString.lowercased())"
    }

    private static func midiOutBlockID(for trackID: UUID) -> BlockID {
        "out-\(trackID.uuidString.lowercased())"
    }

    private static func pipelineShape(for documentModel: SeqAIDocumentModel) -> [PipelineEntry] {
        documentModel.tracks.map { PipelineEntry(trackID: $0.id, output: $0.output) }
    }

    private func flushAllPendingMIDINoteOffs(now: TimeInterval) {
        let midiOutBlocks = withStateLock { Array(midiOutBlocksByTrackID.values) }
        midiOutBlocks.forEach { $0.flushPendingNoteOffs(now: now) }

        let routedOutputs = withStateLock { Array(routeMidiOutputs.values) }
        routedOutputs.forEach { $0.flushPendingNoteOffs(now: now) }
    }

    private func flushDetachedMIDINoteOffs(
        from previousDocument: SeqAIDocumentModel,
        to nextDocument: SeqAIDocumentModel,
        now: TimeInterval
    ) {
        let previousTracks = Dictionary(uniqueKeysWithValues: previousDocument.tracks.map { ($0.id, $0) })
        let nextTracks = Dictionary(uniqueKeysWithValues: nextDocument.tracks.map { ($0.id, $0) })
        let midiOutBlocks = withStateLock { midiOutBlocksByTrackID }

        for (trackID, previousTrack) in previousTracks {
            guard previousTrack.output == .midiOut, !previousTrack.mix.isMuted else {
                continue
            }

            let nextTrack = nextTracks[trackID]
            let stillTargetsPrimaryMIDI = nextTrack?.output == .midiOut && nextTrack?.mix.isMuted == false
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

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
