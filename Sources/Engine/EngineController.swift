import AVFoundation
import Foundation
import Observation

@Observable
final class EngineController: RouterDispatcher {
    struct PipelineEntry: Equatable {
        let trackID: UUID
        let output: Destination.Kind
    }

    struct AudioTrackRuntime {
        let trackID: UUID
        let generatorBlockID: BlockID
        let mix: TrackMixSettings
        let destination: Destination
        let pitchOffset: Int
    }

    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let sharedAudioOutput: TrackPlaybackSink?
    private let audioOutputFactory: (() -> TrackPlaybackSink)?
    private let mainAudioGraph: MainAudioGraph
    private let masterBusHost: MasterBusHosting
    private let stepsPerBar: Int
    private let stateLock = NSLock()
    private let documentApplyLock = NSLock()
    @ObservationIgnored
    private lazy var router = MIDIRouter(dispatcher: self)

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    private let eventQueue = EventQueue()
    private let sampleEngine: SamplePlaybackSink
    private let audioInputCaptureStore = AudioInputCaptureStore()
    private let audioInputCaptureTransport = AudioInputCaptureSummaryRing(capacity: 1024)
    private let audioInputCapturePublicationQueue = DispatchQueue(
        label: "ai.sequencer.SequencerAI.AudioInputCapturePublication"
    )
    private let audioInputCapturePublicationQueueKey = DispatchSpecificKey<Void>()
    private let publishesAudioInputCapture: Bool
    private var audioInputCaptureDrainTimer: DispatchSourceTimer?
    // Initialized at end of init() after `self` is fully available.
    private var macroApplier: TrackMacroApplier!
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
    private(set) var masterBusPerformanceOverlay = MasterBusPerformanceOverlayState()
    private(set) var audioInputRuntimeRevision = 0

    private var currentTrackMix = TrackMixSettings.default
    private var currentDocumentModel: Project = .empty
    private let tickState = TickStateBuffer(playbackSnapshot: SequencerSnapshotCompiler.compile(state: .empty))
    private let trackRuntime = TrackRuntimeRegistry()
    private let routerDispatch = RouterDispatchState()
    private(set) var chordContextByLane: [String: Chord] = [:]

    private func log(_ message: String) {
        NSLog("[EngineController] \(message)")
    }

    /// Apply a mutation to `@Observable` state from any thread without deadlocking.
    ///
    /// SwiftUI observers register tracking callbacks that run synchronously inside
    /// the `ObservationRegistrar`'s `willSet`/`didSet`. When the tick-clock queue
    /// writes an observed property, those callbacks may re-enter the main thread —
    /// and if main is blocked in `clock.stop()`'s `queue.sync`, it deadlocks.
    ///
    /// This helper hops writes to the main thread when called off-main, and runs
    /// inline when already on main (so synchronous test drivers of `processTick`
    /// still see writes before the next XCTAssert).
    private func publishToMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        audioOutput: TrackPlaybackSink? = nil,
        audioOutputFactory: (() -> TrackPlaybackSink)? = nil,
        stepsPerBar: Int = 16,
        mainAudioGraph: MainAudioGraph = MainAudioGraph(),
        sampleEngine: SamplePlaybackSink? = nil,
        sampleLibrary: AudioSampleLibrary = .shared,
        masterBusHost: MasterBusHosting = MasterBusHost(),
        publishesAudioInputCapture: Bool = false
    ) {
        self.mainAudioGraph = mainAudioGraph
        self.sampleEngine = sampleEngine ?? SamplePlaybackEngine(audioGraph: mainAudioGraph)
        self.sampleLibrary = sampleLibrary
        self.masterBusHost = masterBusHost
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
        self.publishesAudioInputCapture = publishesAudioInputCapture
        self.audioInputCapturePublicationQueue.setSpecific(
            key: audioInputCapturePublicationQueueKey,
            value: ()
        )
        if publishesAudioInputCapture {
            startAudioInputCaptureDrainTimer()
        }
        self.masterBusHost.attach(to: mainAudioGraph)

        // Now self is fully initialized; safe to capture as weak.
        self.macroApplier = TrackMacroApplier(sampleEngine: self.sampleEngine) { [weak self] trackID in
            self?.currentAudioUnit(for: trackID)
        }
        if publishesAudioInputCapture {
            self.mainAudioGraph.setAudioInputCaptureHandler { [weak self] trackID, buffer in
                self?.processAudioInputBuffer(trackID: trackID, buffer: buffer)
            }
        }

        do {
            try registerCoreBlocks(registry)
            try buildPipeline(for: .empty)
            router.applyRoutesSnapshot(Project.empty.routes)
        } catch {
            NSLog("EngineController setup failed: \(error)")
        }
    }

    deinit {
        audioInputCaptureDrainTimer?.cancel()
    }

    func start() {
        guard !isRunning, executor != nil else {
            return
        }

        let hosts = withStateLock { Array(trackRuntime.audioOutputsByTrackID.values) }
        hosts.forEach { $0.startIfNeeded() }
        try? sampleEngine.start()

        prepareTick(upcomingStep: 0, now: ProcessInfo.processInfo.systemUptime)
        tickState.markPreparedTick(0)
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
        let hosts = withStateLock { Array(trackRuntime.audioOutputsByTrackID.values) }
        hosts.forEach { $0.stop() }
        isRunning = false
        lastNoteTriggerUptime = 0
        lastNoteTriggerCount = 0
        sampleEngine.stop()
        tickState.resetRuntimeState()
    }

    func applyAudioDeviceUIDs(inputUID: String?, outputUID: String?) throws -> AudioDeviceApplyResult {
        if let audioDeviceApplyOverrideForTesting {
            return try audioDeviceApplyOverrideForTesting(inputUID, outputUID)
        }
        return try mainAudioGraph.applyAudioDeviceUIDs(inputUID: inputUID, outputUID: outputUID)
    }

    func audioInputRuntime(for trackID: UUID) -> AudioInputTrackRuntime? {
        _ = audioInputRuntimeRevision
        return withStateLock { trackRuntime.audioInputRuntimes[trackID] }
    }

    func audioInputRoutingReadoutForTesting(trackID: UUID) -> MainAudioGraph.AudioInputRoutingReadout? {
        mainAudioGraph.audioInputRoutingReadoutForTesting(trackID: trackID)
    }

    func audioInputTrackSendReadoutForTesting(trackID: UUID) -> MainAudioGraph.TrackSendReadout? {
        guard let readout = mainAudioGraph.audioInputRoutingReadoutForTesting(trackID: trackID) else {
            return nil
        }
        return mainAudioGraph.trackSendReadoutForTesting(readout.outputMixer)
    }

    var audioInputRuntimeTrackIDs: Set<UUID> {
        _ = audioInputRuntimeRevision
        return withStateLock { Set(trackRuntime.audioInputRuntimes.keys) }
    }

    @discardableResult
    func armAudioInput(trackID: UUID, pendingStartTick: UInt64? = nil) -> Bool {
        let scheduledStartTick = pendingStartTick ?? nextAudioInputBarBoundary(after: transportTickIndex)
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.armState = .armed
            runtime.pendingStartTick = scheduledStartTick
            runtime.pendingStopTick = nil
            runtime.pendingLoopStartTick = nil
            runtime.captureStartTick = nil
            runtime.captureEndTick = nil
            runtime.armedRecordBarLength = runtime.recordBarLength
            runtime.transientFrameCount = 0
            runtime.routeState = audioInputRouteState(for: runtime.selectedInputChannel)
            applyAudioInputCaptureSnapshot(
                readAudioInputCaptureStore {
                    audioInputCaptureStore.prepareCapture(trackID: trackID)
                },
                to: &runtime
            )
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func cancelAudioInputArm(trackID: UUID) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            switch runtime.armState {
            case .armed, .recording:
                runtime.armState = runtime.hasRecordedLoop ? .hasLoop : .idle
                runtime.pendingStartTick = nil
                runtime.pendingStopTick = nil
                runtime.pendingLoopStartTick = nil
                runtime.captureStartTick = nil
                runtime.captureEndTick = nil
                runtime.armedRecordBarLength = nil
                runtime.transientFrameCount = 0
                applyAudioInputCaptureSnapshot(
                    readAudioInputCaptureStore {
                        audioInputCaptureStore.cancelCapture(trackID: trackID)
                    },
                    to: &runtime
                )
            case .idle, .hasLoop:
                runtime.pendingStartTick = nil
                runtime.pendingStopTick = nil
                runtime.pendingLoopStartTick = nil
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func setAudioInputMonitorMode(trackID: UUID, mode: AudioInputMonitorMode) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.monitorMode = mode
            switch mode {
            case .input:
                runtime.activeMonitorMode = .input
                runtime.pendingLoopStartTick = nil
            case .loop:
                if runtime.hasRecordedLoop {
                    if runtime.activeMonitorMode != .loop {
                        runtime.pendingLoopStartTick = nextAudioInputBarBoundary(after: transportTickIndex)
                    }
                } else {
                    runtime.activeMonitorMode = .loop
                    runtime.pendingLoopStartTick = nil
                }
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func rerouteAudioInput(trackID: UUID, channel: AudioInputChannel) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.selectedInputChannel = channel
            runtime.routeState = audioInputRouteState(for: channel)
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func markAudioInputLoopPlaceholder(trackID: UUID, waveformBuckets: [Float] = []) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.armState = .hasLoop
            runtime.pendingStartTick = nil
            runtime.pendingStopTick = nil
            runtime.captureStartTick = nil
            runtime.captureEndTick = nil
            runtime.armedRecordBarLength = nil
            runtime.recordedLoopID = UUID()
            runtime.recordedLoopBarLength = runtime.recordBarLength
            runtime.transientFrameCount = 0
            applyAudioInputCaptureSnapshot(
                readAudioInputCaptureStore {
                    audioInputCaptureStore.replaceCompletedLoop(
                        trackID: trackID,
                        waveformBuckets: waveformBuckets
                    )
                },
                to: &runtime
            )
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    /// Called at the start of every `shutdown()` / `shutdown(completion:)` invocation.
    /// Intended for test observation only — do not use in production code paths.
    var shutdownObserver: (() -> Void)?

    /// Test-only hook for session/registry audio-device preference behavior.
    /// Production applies through `mainAudioGraph`.
    var audioDeviceApplyOverrideForTesting: ((_ inputUID: String?, _ outputUID: String?) throws -> AudioDeviceApplyResult)?
    var audioInputAvailableChannelCountOverrideForTesting: Int?
    var bypassAudioInputRoutingSyncForTesting = false
    var audioInputCapturePublicationEnabledForTesting: Bool { publishesAudioInputCapture }

    func drainAudioInputCapturePublicationForTesting() {
        readAudioInputCaptureStore {}
    }

    func shutdown() {
        shutdown(completion: {})
    }

    func shutdown(completion: @escaping () -> Void) {
        shutdownObserver?()
        log("shutdown start")
        let hosts = withStateLock { Self.uniqueHosts(Array(trackRuntime.audioOutputsByTrackID.values)) }
        if isRunning {
            flushAllPendingMIDINoteOffs(now: ProcessInfo.processInfo.systemUptime)
            clock.stop()
            isRunning = false
            lastNoteTriggerUptime = 0
            lastNoteTriggerCount = 0
        } else if tickState.hasPreparedTick() {
            clock.stop()
        }

        sampleEngine.stop()
        tickState.resetRuntimeState()

        let finish: () -> Void = { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.withStateLock {
                self.trackRuntime.resetSinks()
                self.routerDispatch.resetOutputs()
            }
            self.tickState.resetRuntimeState(clearCapture: true)
            self.log("shutdown complete")
            completion()
        }

        guard !hosts.isEmpty else {
            finish()
            return
        }

        for host in hosts {
            host.stop()
            host.shutdown()
        }

        finish()
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
        documentApplyLock.lock()
        defer { documentApplyLock.unlock() }

        applyDocumentModelCallCount += 1
        let previousDocumentModel = currentDocumentModel
        flushDetachedMIDINoteOffs(from: previousDocumentModel, to: documentModel, now: ProcessInfo.processInfo.systemUptime)
        let deltas = documentModel.deltas(from: previousDocumentModel)
        currentDocumentModel = documentModel
        sendBusStates = [
            .sendA: documentModel.sendBusA.normalized(expectedID: .sendA),
            .sendB: documentModel.sendBusB.normalized(expectedID: .sendB),
        ]
        let compiledSnapshot = SequencerSnapshotCompiler.compile(project: documentModel)
        tickState.installPlaybackSnapshot(
            compiledSnapshot,
            currentTrackIDs: Set(documentModel.tracks.map(\.id)),
            clearAuditionOverrides: true
        )
        apply(deltas: deltas, documentModel: documentModel)
    }

    func apply(playbackSnapshot: PlaybackSnapshot) {
        applyPlaybackSnapshotCallCount += 1
        tickState.installPlaybackSnapshot(
            playbackSnapshot,
            currentTrackIDs: Set(playbackSnapshot.tracks.map(\.id)),
            resetGeneratedStates: true
        )
        eventQueue.clear()
    }

    /// Exposes the current playback snapshot for test assertions.
    /// Do not use in production code — read the published observable state instead.
    var currentPlaybackSnapshotForTesting: PlaybackSnapshot {
        tickState.currentPlaybackSnapshot()
    }

    /// Counter for test observation of `apply(documentModel:)` invocations.
    var applyDocumentModelCallCount: Int = 0

    /// Counter for test observation of `apply(playbackSnapshot:)` invocations.
    var applyPlaybackSnapshotCallCount: Int = 0

    /// Counter for test observation of scoped send-bus authored updates.
    var sendBusApplyCallCount: Int = 0

    /// Last fixed send-bus states seen through scoped authored updates.
    private(set) var sendBusStates: [SendBusID: SendBusState] = [
        .sendA: .sendA,
        .sendB: .sendB,
    ]

    /// Test hook: exposes whether the internal event queue is empty.
    /// Use to assert that prepared events were cleared after a snapshot swap.
    var eventQueueIsEmpty: Bool { eventQueue.isEmpty }

    /// Scoped write: store a new AU state blob for the given track.
    ///
    /// The AU state was already applied live when the preset was loaded via
    /// `loadPreset(_:for:)`. This call persists the blob into `currentDocumentModel`
    /// so the in-memory model stays coherent with the store.
    func writeStateBlob(_ blob: Data?, for trackID: UUID) {
        guard let index = currentDocumentModel.tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        guard case let .auInstrument(componentID, _) = currentDocumentModel.tracks[index].destination else {
            return
        }
        currentDocumentModel.tracks[index].destination = .auInstrument(componentID: componentID, stateBlob: blob)
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

    /// Scoped mix update for high-frequency UI such as fader drags. This writes
    /// directly to the live playback sinks without rebuilding the document-driven
    /// engine pipeline.
    func setMix(trackID: UUID, mix: TrackMixSettings) {
        guard let trackIndex = currentDocumentModel.tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        currentDocumentModel.tracks[trackIndex].mix = mix
        if currentDocumentModel.selectedTrackID == trackID {
            currentTrackMix = mix
        }
        refreshEffectiveMixerState(for: currentDocumentModel)
    }

    /// Scoped bus mix update for performance-time bus controls. This stays on the
    /// parameter path: bus fader, pan, mute, solo, and bypass-style insert changes
    /// avoid broad document re-application and do not rebuild the engine pipeline.
    func setMixerBusMix(busID: UUID, mix: BusMixSettings) {
        guard let index = currentDocumentModel.buses.firstIndex(where: { $0.id == busID }) else {
            return
        }
        currentDocumentModel.buses[index].mix = mix.normalized()
        refreshEffectiveMixerState(for: currentDocumentModel)
    }

    func setMixerBusParameters(busID: UUID, bus: MixerBus) {
        guard let index = currentDocumentModel.buses.firstIndex(where: { $0.id == busID }) else {
            return
        }
        let normalized = bus.normalized(fallbackName: currentDocumentModel.buses[index].name)
        currentDocumentModel.buses[index] = normalized
        let effectiveMuteState = Self.effectiveMixerMuteState(for: currentDocumentModel)
        mainAudioGraph.setMixerBusParameters(
            bus: normalized,
            effectiveMute: effectiveMuteState.mutedBusIDs.contains(busID)
        )
    }

    func apply(sendBus: SendBusState) {
        let normalized = sendBus.normalized(expectedID: sendBus.id)
        sendBusStates[normalized.id] = normalized
        sendBusApplyCallCount += 1
        currentDocumentModel.updateSendBus(id: normalized.id) { sendBus in
            sendBus = normalized
        }
        mainAudioGraph.installSendBus(normalized)
    }

    var registeredKindIDs: [String] {
        registry.kinds().map(\.id)
    }

    var canStart: Bool {
        executor != nil
    }

    var sampleEngineSink: SamplePlaybackSink { sampleEngine }

    var masterBusState: MasterBusState {
        masterBusHost.appliedState
    }

    var resolvedMasterBusState: MasterBusState {
        masterBusHost.resolvedState
    }

    var masterMeterPublisher: MasterMeterPublisher {
        mainAudioGraph.masterMeterPublisher
    }

    var effectiveCrossfader: Double {
        masterBusPerformanceOverlay.crossfaderOverride
            ?? currentDocumentModel.masterBus.abSelection?.crossfader
            ?? 0
    }

    var masterBusApplyCallCount: Int {
        masterBusHost.applyCallCount
    }

    func apply(masterBus: MasterBusState) {
        applyMasterBusIfChanged(masterBus)
        currentDocumentModel.masterBus = masterBus.normalized()
    }

    func setMasterSceneMacroOverride(sceneID: UUID, macroID: UUID, value: Double) {
        masterBusPerformanceOverlay.setMacroOverride(sceneID: sceneID, macroID: macroID, value: value)
        masterBusPerformanceOverlay = masterBusPerformanceOverlay.normalized(for: currentDocumentModel.masterBus)
        masterBusHost.setSceneMacroOverride(sceneID: sceneID, macroID: macroID, value: value)
    }

    func clearMasterSceneMacroOverrides(sceneID: UUID) {
        masterBusPerformanceOverlay.clearMacroOverrides(sceneID: sceneID)
        masterBusHost.clearSceneMacroOverrides(sceneID: sceneID)
    }

    func setLiveMasterCrossfader(_ value: Double) {
        masterBusPerformanceOverlay.crossfaderOverride = value.clamped(to: 0...1)
        masterBusPerformanceOverlay = masterBusPerformanceOverlay.normalized(for: currentDocumentModel.masterBus)
        masterBusHost.setLiveCrossfaderOverride(value)
    }

    func clearLiveMasterCrossfader() {
        masterBusPerformanceOverlay.crossfaderOverride = nil
        masterBusHost.setLiveCrossfaderOverride(nil)
    }

    func setLiveMasterOutputGain(_ value: Double) {
        masterBusHost.setLiveMasterOutputGain(value)
    }

    func clearLiveMasterOutputGain() {
        masterBusHost.clearLiveMasterOutputGain()
    }

    func clearMasterBusPerformanceOverlay() {
        masterBusPerformanceOverlay.clearAll()
        masterBusHost.clearPerformanceOverlay()
    }

    var hasMasterBusPerformanceOverlay: Bool {
        masterBusPerformanceOverlay.isActive
    }

    func masterSceneMacroOverride(sceneID: UUID, macroID: UUID) -> Double? {
        masterBusPerformanceOverlay.macroOverride(sceneID: sceneID, macroID: macroID)
    }

    func masterSceneMacroOverrides(sceneID: UUID) -> [UUID: Double] {
        masterBusPerformanceOverlay.macroOverrides(sceneID: sceneID)
    }

    func hasMasterSceneMacroOverrides(sceneID: UUID) -> Bool {
        masterBusPerformanceOverlay.hasMacroOverrides(sceneID: sceneID)
    }

    func prepareMasterAUEffect(insertID: UUID) {
        masterBusHost.prepareAUEffect(insertID: insertID)
    }

    func currentMasterAUEffect(insertID: UUID) -> AVAudioUnit? {
        masterBusHost.currentAUEffect(insertID: insertID)
    }

    func masterAUEffectParameterReadout(insertID: UUID) -> [AUParameterDescriptor]? {
        masterBusHost.auEffectParameterReadout(insertID: insertID)
    }

    var availableAudioInstruments: [AudioInstrumentChoice] {
        sharedAudioOutput?.availableInstruments ?? AudioInstrumentChoice.defaultChoices
    }

    var availableAudioEffects: [AudioEffectChoice] {
        AudioEffectChoice.defaultChoices
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
            trackRuntime.audioOutputsByTrackID[trackID]?.currentAudioUnit
        }
    }

    /// Returns the `AudioInstrumentHost` for a track if one is active.
    /// Intended for UI-side parameter readout (e.g. macro picker).
    func audioInstrumentHost(for trackID: UUID) -> AudioInstrumentHost? {
        withStateLock {
            trackRuntime.audioOutputsByTrackID[trackID] as? AudioInstrumentHost
        }
    }

    func prepareAudioUnit(for trackID: UUID) {
        log("prepareAudioUnit trackID=\(trackID)")
        if let host = withStateLock({ trackRuntime.audioOutputsByTrackID[trackID] }) {
            log("prepareAudioUnit hostFound=true")
            host.preparePresetBrowser()
            return
        }

        syncAudioOutputs(for: currentDocumentModel)
        let host = withStateLock { trackRuntime.audioOutputsByTrackID[trackID] }
        log("prepareAudioUnit hostFound=\(host != nil)")
        host?.preparePresetBrowser()
    }

    /// Returns the live AU's preset readout for the given track, or `nil` if no AU
    /// is currently loaded for that track.
    func presetReadout(for trackID: UUID) -> PresetReadout? {
        let host = withStateLock { trackRuntime.audioOutputsByTrackID[trackID] }
        guard let host = host as? AudioInstrumentHost else {
            return nil
        }
        return host.presetReadout()
    }

    /// Loads `descriptor` into the AU for the given track and returns the captured
    /// state blob. Throws `PresetLoadingError.presetNotFound` if there is no match.
    func loadPreset(_ descriptor: AUPresetDescriptor, for trackID: UUID) throws -> Data? {
        let host = withStateLock { trackRuntime.audioOutputsByTrackID[trackID] }
        guard let host = host as? AudioInstrumentHost else {
            throw PresetLoadingError.presetNotFound
        }
        return try host.loadPreset(descriptor)
    }

    func capturedClipContent(
        trackID: UUID,
        lengthSteps: Int? = nil
    ) -> ClipContent? {
        tickState.capturedClipContent(trackID: trackID, lengthSteps: lengthSteps)
    }

    func captureSnapshot(trackID: UUID) -> CaptureSnapshot {
        tickState.captureSnapshot(trackID: trackID)
    }

    func recordAudioInputBufferForTesting(trackID: UUID, buffer: AVAudioPCMBuffer) {
        processAudioInputBuffer(trackID: trackID, buffer: buffer)
    }

    func setAuditionOverride(_ state: PseudoClipState?, for trackID: UUID) {
        tickState.setAuditionOverride(state, for: trackID)
        eventQueue.clear()
    }

    @discardableResult
    func saveRollingCapture(
        to project: inout Project,
        trackID: UUID,
        destinationSlotIndex: Int? = nil,
        lengthSteps: Int? = nil,
        name: String? = nil
    ) -> UUID? {
        return tickState.saveRollingCapture(
            to: &project,
            trackID: trackID,
            destinationSlotIndex: destinationSlotIndex,
            lengthSteps: lengthSteps,
            name: name
        )
    }

    private func apply(deltas: [ProjectDelta], documentModel: Project) {
        guard !deltas.isEmpty else {
            return
        }

        guard deltas.allSatisfy(\.isPhaseOneHotPath) else {
            applyBroadSync(documentModel: documentModel)
            return
        }

        var shouldInvalidatePreparedTick = false
        var shouldResetGeneratedStates = false
        for delta in deltas {
            switch delta {
            case let .trackMixChanged(trackID, mix):
                setMix(trackID: trackID, mix: mix)
                if trackID == documentModel.selectedTrackID {
                    currentTrackMix = mix
                }

            case let .mixerBusMixChanged(busID, mix):
                setMixerBusMix(busID: busID, mix: mix)

            case let .sendBusChanged(_, bus):
                apply(sendBus: bus)

            case let .selectedTrackChanged(trackID):
                let selectedTrack = documentModel.tracks.first(where: { $0.id == trackID }) ?? documentModel.selectedTrack
                selectedOutput = Self.effectiveDestination(for: trackID, in: documentModel).destination.kind
                currentTrackMix = selectedTrack.mix

            case let .trackOutputBusChanged(trackID, busID):
                setTrackOutputBus(trackID: trackID, busID: busID, documentModel: documentModel)

            case let .trackDestinationChanged(trackID, _):
                // Invalidate macro applier cache for this track so the next
                // prepared step re-resolves AUParameter references against
                // the newly-loaded AU.
                macroApplier.invalidateCache(for: trackID)
                applyBroadSync(documentModel: documentModel)
                return

            case .patternBanksChanged:
                shouldInvalidatePreparedTick = true
                shouldResetGeneratedStates = true

            case .clipPoolChanged:
                shouldInvalidatePreparedTick = true

            case .masterBusChanged:
                apply(masterBus: documentModel.masterBus)

            case .trackParameterChanged,
                 .tracksInsertedOrRemoved,
                 .trackGroupsChanged,
                 .routesChanged,
                 .busesChanged,
                 .phrasesChanged,
                 .layersChanged,
                 .coarseResync:
                applyBroadSync(documentModel: documentModel)
                return
            }
        }

        if shouldInvalidatePreparedTick || shouldResetGeneratedStates {
            tickState.invalidatePreparedTick(resetGeneratedStates: shouldResetGeneratedStates)
        }
    }

    private func applyBroadSync(documentModel: Project) {
        let selectedTrack = documentModel.selectedTrack
        selectedOutput = Self.effectiveDestination(for: selectedTrack.id, in: documentModel).destination.kind
        currentTrackMix = selectedTrack.mix
        router.applyRoutesSnapshot(documentModel.routes)
        applyMasterBusIfChanged(documentModel.masterBus)
        installMixerBuses(for: documentModel)
        mainAudioGraph.installSendBuses([documentModel.sendBusA, documentModel.sendBusB])

        do {
            if withStateLock({ trackRuntime.pipelineShape != Self.pipelineShape(for: documentModel) || executor == nil }) {
                try buildPipeline(for: documentModel)
            } else {
                syncTrackParams(for: documentModel)
                syncMidiOutputs(for: documentModel)
                syncAudioOutputs(for: documentModel)
                syncAudioInputRuntimes(for: documentModel)
                syncAudioInputRouting(for: documentModel)
            }
        } catch {
            NSLog("EngineController apply failed: \(error)")
        }
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
            let host = withStateLock { trackRuntime.audioOutputsByTrackID[selectedTrack.id] }
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
        case let .slicer(sliceSetID, _):
            let sliceSet = tickState.currentPlaybackSnapshot().sliceSet(id: sliceSetID)
            let count = sliceSet?.displaySliceCount ?? 0
            return count > 0 ? "Slicer • \(count) slices" : "Slicer • Choose a loop"
        case .inheritGroup, .none:
            return "No default output"
        }
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        if advanceAudioInputScheduling(at: tickIndex) {
            syncAudioInputRouting(for: currentDocumentModel)
        }

        let needsBootstrap = !tickState.isPrepared(for: tickIndex)
        if needsBootstrap {
            prepareTick(upcomingStep: tickIndex, now: now)
        }
        dispatchTick()
        prepareTick(upcomingStep: tickIndex &+ 1, now: now)
        tickState.markPreparedTick(tickIndex &+ 1)
    }

    private func prepareTick(upcomingStep: UInt64, now: TimeInterval) {
        let (
            executor,
            audioRuntimes,
            audioOutputs,
            generatorIDs,
            chordContexts,
            effectiveMutedTrackIDs
        ) = withStateLock {
            (
                self.executor,
                self.trackRuntime.audioTrackRuntimes,
                self.trackRuntime.audioOutputsByTrackID,
                self.trackRuntime.generatorIDsByTrackID,
                self.chordContextByLane,
                self.trackRuntime.effectiveMutedTrackIDs
            )
        }
        let prepareInputs = tickState.readPrepareInputs()
        let generatedStates = prepareInputs.generatedStates
        let clipCaptureService = prepareInputs.clipCaptureService
        let playbackSnapshot = prepareInputs.playbackSnapshot
        let auditionOverridesByTrackID = prepareInputs.auditionOverridesByTrackID

        assert(executor != nil, "EngineController.prepareTick called without an executor.")
        guard let executor else {
            return
        }
        let phraseStepCount = playbackSnapshot.phraseBuffer(for: playbackSnapshot.selectedPhraseID)?.stepCount ?? 1
        let stepInPhrase = Int(upcomingStep % UInt64(max(1, phraseStepCount)))
        let currentLayerSnapshot = playbackSnapshot.layerSnapshot(
            phraseID: playbackSnapshot.selectedPhraseID,
            stepInPhrase: stepInPhrase
        )

        // Dispatch resolved macro values to their destinations (AU params / sampler).
        // Phase 1b: reads snapshot-carried tracks, not currentDocumentModel.tracks.
        macroApplier.apply(currentLayerSnapshot.macroValues, tracks: playbackSnapshot.tracks)

        var nextGeneratedStates = generatedStates
        var nextClipCaptureService = clipCaptureService
        let harmonicSidechainChord = chordContexts["default"]
        var preparedNotesByBlockID: [BlockID: [NoteEvent]] = [:]
        // Phase 1b: iterate snapshot-carried tracks, not currentDocumentModel.tracks.
        for track in playbackSnapshot.tracks {
            guard let generatorBlockID = generatorIDs[track.id] else {
                continue
            }

            var rng = SystemRandomNumberGenerator()
            var state = nextGeneratedStates[track.id] ?? GeneratedSourceEvaluationState()
            let override = auditionOverridesByTrackID[track.id]
            let notes: [GeneratedNote]
            if let override {
                notes = Self.resolvedAuditionOverrideNotes(
                    for: override,
                    trackType: track.trackType,
                    stepIndex: stepInPhrase,
                    rng: &rng
                )
            } else {
                notes = Self.resolvedStepNotes(
                    for: track.id,
                    in: playbackSnapshot,
                    phraseID: playbackSnapshot.selectedPhraseID,
                    stepIndex: stepInPhrase,
                    chordContext: harmonicSidechainChord,
                    state: &state,
                    rng: &rng
                )
                nextGeneratedStates[track.id] = state
                nextClipCaptureService.append(trackID: track.id, stepIndex: Int(upcomingStep), notes: notes)
            }
            preparedNotesByBlockID[generatorBlockID] = notes.map(Self.noteEvent(from:))
        }
        let outputs = executor.tick(now: now, preparedNotesByBlockID: preparedNotesByBlockID)
        let newCurrentBPM = executor.currentBPM
        let completedStep = upcomingStep == 0 ? 0 : upcomingStep &- 1
        let newTransportPosition = Self.transportString(for: completedStep, stepsPerBar: stepsPerBar)

        tickState.commitPrepareOutputs(
            generatedStates: nextGeneratedStates,
            clipCaptureService: nextClipCaptureService,
            completedStep: completedStep
        )

        let triggeredNoteCount = outputs.values.reduce(0) { partial, ports in
            partial + ports.values.reduce(0) { nested, stream in
                if case let .notes(events) = stream {
                    return nested + events.count
                }
                return nested
            }
        }
        let newNoteTrigger: (uptime: TimeInterval, count: Int)? =
            triggeredNoteCount > 0 ? (now, triggeredNoteCount) : nil

        // Publish UI-observed state on the main thread so @Observable's
        // synchronous notification callbacks don't re-enter main while the
        // main thread is blocked in clock.stop()'s queue.sync.
        publishToMain { [weak self] in
            guard let self else { return }
            if self.currentBPM != newCurrentBPM {
                self.currentBPM = newCurrentBPM
            }
            self.transportTickIndex = completedStep
            self.transportPosition = newTransportPosition
            if let trigger = newNoteTrigger {
                self.lastNoteTriggerUptime = trigger.uptime
                self.lastNoteTriggerCount = trigger.count
            }
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

        // Sample/slicer dispatch → queue (drum tracks and any other track with sample-like destinations).
        // Phase 1b: iterate snapshot-carried tracks, not currentDocumentModel.tracks.
        for track in playbackSnapshot.tracks {
            guard !effectiveMutedTrackIDs.contains(track.id),
                  !currentLayerSnapshot.isMuted(track.id),
                  let generatorID = generatorIDs[track.id],
                  case let .notes(events)? = outputs[generatorID]?["notes"],
                  !events.isEmpty
            else { continue }
            switch track.destination {
            case let .sample(sampleID, settings):
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

            case let .slicer(sliceSetID, settings):
                EngineSlicerDispatcher.enqueueSliceTriggers(
                    for: events,
                    trackID: track.id,
                    sliceSetID: sliceSetID,
                    settings: settings,
                    snapshot: playbackSnapshot,
                    sampleLibrary: sampleLibrary,
                    sampleLibraryRoot: sampleLibraryRoot,
                    stepsPerBar: stepsPerBar,
                    bpm: executor.currentBPM,
                    now: now,
                    eventQueue: eventQueue
                )

            default:
                continue
            }
        }

        routerDispatch.beginTick(now: now)
        // Phase 1b: iterate snapshot-carried tracks, not currentDocumentModel.tracks.
        let trackInputs = playbackSnapshot.tracks.compactMap { track -> RouterTickInput? in
            guard !effectiveMutedTrackIDs.contains(track.id),
                  !currentLayerSnapshot.isMuted(track.id),
                  let generatorID = generatorIDs[track.id],
                  case let .notes(events)? = outputs[generatorID]?["notes"]
            else {
                return nil
            }

            return RouterTickInput(sourceTrack: track.id, notes: events, chordContext: nil)
        }
        router.tick(trackInputs)
        flushRoutedEvents(
            bpm: executor.currentBPM,
            snapshot: playbackSnapshot,
            layerSnapshot: currentLayerSnapshot,
            effectiveMutedTrackIDs: effectiveMutedTrackIDs
        )
    }

    private func dispatchTick() {
        let events = eventQueue.drain()
        let (audioOutputs, outputKeys) = withStateLock { (trackRuntime.audioOutputsByTrackID, trackRuntime.audioOutputKeysByTrackID) }

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
                publishToMain { [weak self] in
                    self?.chordContextByLane[lane] = chord
                }

            case .routedMIDI:
                break

            case let .sampleTrigger(trackID, sampleID, settings, _):
                guard let sample = sampleLibrary.sample(id: sampleID) else { continue }
                guard let url = try? sample.fileRef.resolve(libraryRoot: sampleLibraryRoot) else { continue }
                _ = sampleEngine.play(sampleURL: url, settings: settings, trackID: trackID, at: nil)

            case let .sliceTrigger(trackID, sampleURL, startFrame, endFrame, settings, reverse, stepParameters, _):
                _ = sampleEngine.playSlice(
                    sampleURL: sampleURL,
                    startFrame: AVAudioFramePosition(startFrame),
                    endFrame: AVAudioFramePosition(endFrame),
                    settings: settings,
                    trackID: trackID,
                    at: nil,
                    reverse: reverse,
                    stepParameters: stepParameters
                )
            }
        }
    }

    private func setTrackOutputBus(trackID: UUID, busID: UUID?, documentModel: Project) {
        guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else {
            return
        }

        if documentModel.selectedTrackID == trackID {
            selectedOutput = Self.effectiveDestination(for: trackID, in: documentModel).destination.kind
        }

        if track.trackType == .audioInput {
            updateAudioInputRoutingParameters(for: documentModel)
        }

        let host = withStateLock { trackRuntime.audioOutputsByTrackID[trackID] }
        host?.setOutputBusID(busID)

        switch track.destination {
        case .sample, .slicer:
            sampleEngine.setTrackOutputBus(trackID: trackID, busID: busID)
        default:
            break
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
            if trackRuntime.lastDestinationByOutputKey[outputKey] == destination {
                return false
            }
            trackRuntime.lastDestinationByOutputKey[outputKey] = destination
            return true
        }

        if shouldApply {
            host.setDestination(destination)
        }
    }

    func dispatch(_ event: RouterEvent) {
        routerDispatch.record(event)
    }

    private func buildPipeline(for documentModel: Project) throws {
        var blocks: [BlockID: Block] = [:]
        var wiring: [BlockID: [PortID: (BlockID, PortID)]] = [:]
        var generatorIDs: [UUID: BlockID] = [:]
        var midiOutBlocks: [UUID: MidiOut] = [:]
        var audioRuntimes: [UUID: AudioTrackRuntime] = [:]
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)

        for track in documentModel.tracks {
            let (effectiveDestination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            let generatorBlockID = Self.generatorBlockID(for: track.id)
            let generator = NoteGenerator(id: generatorBlockID, params: [:])
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
                    endpoint: effectiveMuteState.mutedTrackIDs.contains(track.id) ? nil : (port.flatMap(resolveEndpoint(named:)))
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
            case .internalSampler, .sample, .slicer, .inheritGroup, .none:
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
            trackRuntime.installPipeline(
                generatorIDs: generatorIDs,
                midiOutBlocks: midiOutBlocks,
                audioRuntimes: audioRuntimes,
                pipelineShape: Self.pipelineShape(for: documentModel)
            )
        }
        tickState.installPlaybackSnapshot(
            SequencerSnapshotCompiler.compile(project: documentModel),
            currentTrackIDs: Set(documentModel.tracks.map(\.id)),
            resetGeneratedStates: true
        )

        installMixerBuses(for: documentModel)
        mainAudioGraph.installSendBuses([documentModel.sendBusA, documentModel.sendBusB])
        syncAudioOutputs(for: documentModel)
        syncAudioInputRuntimes(for: documentModel)
        syncAudioInputRouting(for: documentModel)
        currentDocumentModel = documentModel
        selectedOutput = Self.effectiveDestination(for: documentModel.selectedTrack.id, in: documentModel).destination.kind
        currentTrackMix = documentModel.selectedTrack.mix
    }

    private func flushRoutedEvents(
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        for (destination, notes) in routerDispatch.noteEvents where !notes.isEmpty {
            flushRoutedNotes(
                notes,
                to: destination,
                bpm: bpm,
                snapshot: snapshot,
                layerSnapshot: layerSnapshot,
                effectiveMutedTrackIDs: effectiveMutedTrackIDs
            )
        }

        let midiDestinationsToTick = Set(routerDispatch.midiOutputs.keys).union(routerDispatch.midiNotes.keys)
        for destination in midiDestinationsToTick {
            guard case let .midi(port, channel, _) = destination,
                  let port,
                  let midiOut = routeMidiOut(for: destination, port: port, channel: channel)
            else {
                continue
            }

            let notes = routerDispatch.midiNotes[destination] ?? []
            _ = midiOut.tick(
                context: TickContext(
                    tickIndex: tickState.currentClockThreadTickIndex(),
                    bpm: bpm,
                    inputs: ["notes": .notes(notes)],
                    now: routerDispatch.dispatchNow,
                    preparedNotesByBlockID: [:]
                )
            )
        }

        for (destination, chord, lane) in routerDispatch.chords {
            guard case let .chordContext(broadcastTag) = destination else {
                continue
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: routerDispatch.dispatchNow,
                    payload: .chordContextBroadcast(
                        lane: broadcastTag ?? lane ?? "default",
                        chord: chord
                    )
                )
            )
        }
    }

    // Phase 1b: `snapshot` is passed from `prepareTick` so this function reads
    // snapshot-carried tracks rather than `currentDocumentModel.tracks`.
    // `currentDocumentModel` is not read on the tick path.
    private func flushRoutedNotes(
        _ notes: [NoteEvent],
        to destination: RouteDestination,
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        switch destination {
        case let .midi(port, channel, noteOffset):
            let adjustedNotes = notes.map { note in
                let shifted = min(max(Int(note.pitch) + noteOffset, 0), 127)
                return NoteEvent(
                    pitch: UInt8(shifted),
                    velocity: note.velocity,
                    length: note.length,
                    gate: note.gate,
                    voiceTag: note.voiceTag,
                    sliceParameters: note.sliceParameters
                )
            }
            routerDispatch.appendMIDINotes(
                adjustedNotes,
                to: .midi(port: port, channel: channel, noteOffset: noteOffset)
            )

        case let .voicing(trackID):
            guard let track = snapshot.tracks.first(where: { $0.id == trackID }) else {
                return
            }
            let resolved = snapshot.resolvedDestination(for: trackID)
            flushConcreteDestination(
                resolved.destination,
                notes: notes,
                bpm: bpm,
                pitchOffset: resolved.pitchOffset,
                track: track,
                snapshot: snapshot,
                layerSnapshot: layerSnapshot,
                effectiveMutedTrackIDs: effectiveMutedTrackIDs
            )

        case let .trackInput(trackID, tag):
            guard let track = snapshot.tracks.first(where: { $0.id == trackID }) else {
                return
            }
            _ = tag
            let resolved = snapshot.resolvedDestination(for: trackID)
            flushConcreteDestination(
                resolved.destination,
                notes: notes,
                bpm: bpm,
                pitchOffset: resolved.pitchOffset,
                track: track,
                snapshot: snapshot,
                layerSnapshot: layerSnapshot,
                effectiveMutedTrackIDs: effectiveMutedTrackIDs
            )

        case .chordContext:
            return
        }
    }

    private func flushConcreteDestination(
        _ destination: Destination,
        notes: [NoteEvent],
        bpm: Double,
        pitchOffset: Int = 0,
        track: StepSequenceTrack?,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        switch destination {
        case let .midi(port, channel, noteOffset):
            if let track, effectiveMutedTrackIDs.contains(track.id) {
                return
            }
            guard let port else {
                return
            }
            let adjustedNotes = Self.shifted(notes, by: pitchOffset + noteOffset)
            routerDispatch.appendMIDINotes(
                adjustedNotes,
                to: .midi(port: port, channel: channel, noteOffset: noteOffset)
            )

        case .auInstrument:
            guard let track,
                  !effectiveMutedTrackIDs.contains(track.id),
                  !layerSnapshot.isMuted(track.id),
                  trackRuntime.audioOutputsByTrackID[track.id] != nil
            else {
                return
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: routerDispatch.dispatchNow,
                    payload: .routedAU(
                        trackID: track.id,
                        destination: destination,
                        notes: Self.shifted(notes, by: pitchOffset),
                        bpm: bpm,
                        stepsPerBar: stepsPerBar
                    )
                )
            )

        case let .slicer(sliceSetID, settings):
            guard let track,
                  !effectiveMutedTrackIDs.contains(track.id),
                  !layerSnapshot.isMuted(track.id)
            else {
                return
            }
            EngineSlicerDispatcher.enqueueSliceTriggers(
                for: notes,
                trackID: track.id,
                sliceSetID: sliceSetID,
                settings: settings,
                snapshot: snapshot,
                sampleLibrary: sampleLibrary,
                sampleLibraryRoot: sampleLibraryRoot,
                stepsPerBar: stepsPerBar,
                bpm: bpm,
                now: routerDispatch.dispatchNow,
                eventQueue: eventQueue
            )

        case .internalSampler, .sample, .inheritGroup, .none:
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

        let midiOut = routerDispatch.midiOutputs[destination] ?? {
            let block = MidiOut(
                id: "route-\(destination.hashValue)",
                client: midiClient,
                endpoint: resolvedEndpoint
            )
            routerDispatch.midiOutputs[destination] = block
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

    private func processAudioInputBuffer(trackID: UUID, buffer: AVAudioPCMBuffer) {
        let summary = AudioInputCaptureStore.summarize(buffer: buffer)
        audioInputCaptureTransport.write(trackID: trackID, summary: summary)
    }

    private func startAudioInputCaptureDrainTimer() {
        guard audioInputCaptureDrainTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: audioInputCapturePublicationQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(33),
            repeating: .milliseconds(33),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.drainAudioInputCaptureTransport()
        }
        timer.resume()
        audioInputCaptureDrainTimer = timer
    }

    private func drainAudioInputCaptureTransport() {
        audioInputCaptureTransport.drain { trackID, summary in
            let snapshot = audioInputCaptureStore.process(summary: summary, trackID: trackID)
            publishAudioInputCaptureSnapshot(trackID: trackID, snapshot: snapshot)
        }
    }

    private func publishAudioInputCaptureSnapshot(trackID: UUID, snapshot: AudioInputCaptureSnapshot) {
        publishToMain { [weak self] in
            guard let self else { return }
            _ = self.updateAudioInputRuntime(trackID: trackID) { runtime in
                self.applyAudioInputCaptureSnapshot(snapshot, to: &runtime)
            }
        }
    }

    private func applyAudioInputCaptureSnapshot(
        _ snapshot: AudioInputCaptureSnapshot,
        to runtime: inout AudioInputTrackRuntime
    ) {
        guard snapshot.revision >= runtime.captureSnapshotRevision else {
            return
        }
        runtime.captureSnapshotRevision = snapshot.revision
        runtime.liveLevel = snapshot.liveLevel
        runtime.recordingProgress = snapshot.recordingProgress
        runtime.captureWaveformBuckets = snapshot.streamedWaveformBuckets
        runtime.waveformBuckets = snapshot.completedWaveformBuckets
    }

    private func readAudioInputCaptureStore<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: audioInputCapturePublicationQueueKey) != nil {
            drainAudioInputCaptureTransport()
            return body()
        }
        return audioInputCapturePublicationQueue.sync {
            self.drainAudioInputCaptureTransport()
            return body()
        }
    }

    private func syncTrackParams(for documentModel: Project) {
        // Note injection uses the typed preparedNotesByBlockID path only; no params to sync.
        // Reset generator evaluation state and prepared-tick index so the next prepareTick
        // re-evaluates from the new document model.
        tickState.invalidatePreparedTick(resetGeneratedStates: true)
    }

    private func syncMidiOutputs(for documentModel: Project) {
        let midiOutBlocks = withStateLock { trackRuntime.midiOutBlocksByTrackID }
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        for track in documentModel.tracks {
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            let nextEndpoint: MIDIEndpoint?
            if case let .midi(port, channel, noteOffset) = destination,
               !effectiveMuteState.mutedTrackIDs.contains(track.id)
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

    private func installMixerBuses(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        withStateLock {
            trackRuntime.installMuteState(effectiveMuteState)
        }
        mainAudioGraph.installMixerBuses(
            documentModel.buses,
            effectiveMuteByBusID: Dictionary(
                uniqueKeysWithValues: documentModel.buses.map {
                    ($0.id, effectiveMuteState.mutedBusIDs.contains($0.id))
                }
            )
        )
    }

    private func refreshEffectiveMixerState(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let audioOutputs = withStateLock { self.trackRuntime.audioOutputsByTrackID }
        withStateLock {
            trackRuntime.installMuteState(effectiveMuteState)
            for (trackID, runtime) in trackRuntime.audioTrackRuntimes {
                guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else { continue }
                trackRuntime.audioTrackRuntimes[trackID] = AudioTrackRuntime(
                    trackID: runtime.trackID,
                    generatorBlockID: runtime.generatorBlockID,
                    mix: Self.effectiveMix(for: track.mix, isMuted: effectiveMuteState.mutedTrackIDs.contains(trackID)),
                    destination: runtime.destination,
                    pitchOffset: runtime.pitchOffset
                )
            }
        }

        for track in documentModel.tracks {
            let effectiveMix = Self.effectiveMix(
                for: track.mix,
                isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id)
            )
            audioOutputs[track.id]?.setMix(effectiveMix)
            switch track.destination {
            case .sample, .slicer:
                sampleEngine.setTrackMix(
                    trackID: track.id,
                    level: effectiveMix.isMuted ? 0 : effectiveMix.clampedLevel,
                    pan: effectiveMix.clampedPan
                )
                sampleEngine.setTrackSends(trackID: track.id, sendA: effectiveMix.sendA, sendB: effectiveMix.sendB)
            default:
                continue
            }
        }
        syncMidiOutputs(for: documentModel)
        updateAudioInputRoutingParameters(for: documentModel)

        for bus in documentModel.buses {
            mainAudioGraph.setMixerBusMix(
                busID: bus.id,
                mix: bus.mix,
                effectiveMute: effectiveMuteState.mutedBusIDs.contains(bus.id)
            )
        }
    }

    private func syncAudioOutputs(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let desiredAudioTracks = documentModel.tracks.compactMap { track -> (StepSequenceTrack, Destination, Int, AudioOutputKey)? in
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            guard case .auInstrument = destination,
                  let key = Self.audioOutputKey(for: track, in: documentModel)
            else {
                return nil
            }
            return (track, destination, pitchOffset, key)
        }

        let previousOutputs = withStateLock { trackRuntime.audioOutputsByTrackID }
        let previousKeys = withStateLock { trackRuntime.audioOutputKeysByTrackID }
        let previousDestinations = withStateLock { trackRuntime.lastDestinationByOutputKey }
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
            host.setOutputBusID(track.outputBusID)
            host.setMix(Self.effectiveMix(for: track.mix, isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id)))
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
            trackRuntime.installAudioOutputs(
                outputs: nextOutputs,
                outputKeys: nextKeys,
                destinationsByOutputKey: nextDestinations,
                audioRuntimes: Dictionary(
                uniqueKeysWithValues: desiredAudioTracks.map {
                    (
                        $0.0.id,
                        AudioTrackRuntime(
                            trackID: $0.0.id,
                            generatorBlockID: trackRuntime.generatorIDsByTrackID[$0.0.id] ?? Self.generatorBlockID(for: $0.0.id),
                            mix: Self.effectiveMix(
                                for: $0.0.mix,
                                isMuted: effectiveMuteState.mutedTrackIDs.contains($0.0.id)
                            ),
                            destination: $0.1,
                            pitchOffset: $0.2
                        )
                    )
                }
                )
            )
        }

        removedHosts.forEach { $0.stop() }

        syncSampleMixers(for: documentModel)
    }

    private func syncAudioInputRuntimes(for documentModel: Project) {
        let desiredTracks = Array(documentModel.tracks.filter { $0.trackType == .audioInput }.prefix(1))
        let desiredIDs = Set(desiredTracks.map(\.id))
        readAudioInputCaptureStore {
            audioInputCaptureStore.keepOnly(trackIDs: desiredIDs)
        }

        withStateLock {
            var next = trackRuntime.audioInputRuntimes.filter { desiredIDs.contains($0.key) }
            for track in desiredTracks {
                var runtime = next[track.id]
                    ?? AudioInputTrackRuntime(
                        trackID: track.id,
                        recordBarLength: track.recordBarLength,
                        selectedInputChannel: track.inputChannel,
                        routeState: audioInputRouteState(for: track.inputChannel)
                    )
                runtime.recordBarLength = StepSequenceTrack.normalizedRecordBarLength(track.recordBarLength)
                runtime.selectedInputChannel = track.inputChannel
                runtime.routeState = audioInputRouteState(for: track.inputChannel)
                next[track.id] = runtime
            }

            if next != trackRuntime.audioInputRuntimes {
                trackRuntime.audioInputRuntimes = next
                audioInputRuntimeRevision &+= 1
            }
        }
    }

    private func syncAudioInputRouting(for documentModel: Project) {
        guard !bypassAudioInputRoutingSyncForTesting else { return }
        mainAudioGraph.syncAudioInputRoutings(audioInputRoutingRequests(for: documentModel))
    }

    private func updateAudioInputRoutingParameters(for documentModel: Project) {
        guard !bypassAudioInputRoutingSyncForTesting else { return }
        mainAudioGraph.updateAudioInputRoutingParameters(audioInputRoutingRequests(for: documentModel))
    }

    private func audioInputRoutingRequests(for documentModel: Project) -> [MainAudioGraph.AudioInputRoutingRequest] {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let runtimes = withStateLock { trackRuntime.audioInputRuntimes }
        return documentModel.tracks.compactMap { track -> MainAudioGraph.AudioInputRoutingRequest? in
            guard let runtime = runtimes[track.id] else { return nil }
            let mix = Self.effectiveMix(
                for: track.mix,
                isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id)
            )
            return MainAudioGraph.AudioInputRoutingRequest(
                trackID: track.id,
                source: Self.audioInputMonitorSource(for: runtime),
                selectedChannel: runtime.selectedInputChannel,
                outputBusID: track.outputBusID,
                mix: mix
            )
        }
    }

    private static func audioInputMonitorSource(for runtime: AudioInputTrackRuntime) -> MainAudioGraph.AudioInputMonitorSource {
        guard runtime.routeState == .available else { return .silent }
        switch runtime.activeMonitorMode {
        case .input:
            return .input
        case .loop:
            return runtime.hasRecordedLoop ? .loop : .silent
        }
    }

    private func advanceAudioInputScheduling(at tickIndex: UInt64) -> Bool {
        withStateLock {
            var didChange = false
            for trackID in trackRuntime.audioInputRuntimes.keys {
                guard var runtime = trackRuntime.audioInputRuntimes[trackID] else {
                    continue
                }
                let original = runtime

                if runtime.armState == .recording,
                   let endTick = runtime.captureEndTick,
                   tickIndex >= endTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    completeAudioInputCapture(&runtime, at: tickIndex)
                }

                if runtime.armState == .armed,
                   let startTick = runtime.pendingStartTick,
                   tickIndex >= startTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    beginAudioInputCapture(&runtime, at: tickIndex)
                }

                if runtime.armState == .recording,
                   let startTick = runtime.captureStartTick,
                   let endTick = runtime.captureEndTick,
                   tickIndex < endTick
                {
                    let span = max(1, endTick &- startTick)
                    let elapsed = min(tickIndex &- startTick, span)
                    applyAudioInputCaptureSnapshot(
                        readAudioInputCaptureStore {
                            audioInputCaptureStore.updateProgress(
                                trackID: runtime.trackID,
                                progress: Double(elapsed) / Double(span)
                            )
                        },
                        to: &runtime
                    )
                }

                if let loopStartTick = runtime.pendingLoopStartTick,
                   tickIndex >= loopStartTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    runtime.activeMonitorMode = .loop
                    runtime.pendingLoopStartTick = nil
                }

                if runtime != original {
                    trackRuntime.audioInputRuntimes[trackID] = runtime
                    didChange = true
                }
            }

            if didChange {
                audioInputRuntimeRevision &+= 1
            }
            return didChange
        }
    }

    private func beginAudioInputCapture(_ runtime: inout AudioInputTrackRuntime, at tickIndex: UInt64) {
        let bars = StepSequenceTrack.normalizedRecordBarLength(runtime.armedRecordBarLength ?? runtime.recordBarLength)
        let endTick = tickIndex &+ UInt64(bars * stepsPerBar)
        runtime.armState = .recording
        runtime.pendingStartTick = nil
        runtime.pendingStopTick = endTick
        runtime.captureStartTick = tickIndex
        runtime.captureEndTick = endTick
        runtime.armedRecordBarLength = bars
        runtime.transientFrameCount = 0
        runtime.activeMonitorMode = .input
        runtime.pendingLoopStartTick = nil
        applyAudioInputCaptureSnapshot(
            readAudioInputCaptureStore {
                audioInputCaptureStore.beginCapture(trackID: runtime.trackID)
            },
            to: &runtime
        )
    }

    private func completeAudioInputCapture(_ runtime: inout AudioInputTrackRuntime, at tickIndex: UInt64) {
        let bars = StepSequenceTrack.normalizedRecordBarLength(runtime.armedRecordBarLength ?? runtime.recordBarLength)
        let startTick = runtime.captureStartTick ?? tickIndex
        runtime.armState = .hasLoop
        runtime.pendingStartTick = nil
        runtime.pendingStopTick = nil
        runtime.captureStartTick = nil
        runtime.captureEndTick = nil
        runtime.armedRecordBarLength = nil
        runtime.recordedLoopID = UUID()
        runtime.recordedLoopBarLength = bars
        runtime.transientFrameCount = Int(tickIndex &- startTick)
        applyAudioInputCaptureSnapshot(
            readAudioInputCaptureStore {
                audioInputCaptureStore.completeCapture(trackID: runtime.trackID)
            },
            to: &runtime
        )
        if runtime.monitorMode == .loop {
            runtime.pendingLoopStartTick = nil
            runtime.activeMonitorMode = .loop
        }
    }

    private func updateAudioInputRuntime(
        trackID: UUID,
        update: (inout AudioInputTrackRuntime) -> Void
    ) -> Bool {
        withStateLock {
            guard var runtime = trackRuntime.audioInputRuntimes[trackID] else {
                return false
            }
            update(&runtime)
            trackRuntime.audioInputRuntimes[trackID] = runtime
            audioInputRuntimeRevision &+= 1
            return true
        }
    }

    private func audioInputRouteState(for channel: AudioInputChannel) -> AudioInputRouteState {
        Self.audioInputRouteState(for: channel, availableChannelCount: availableAudioInputChannelCount)
    }

    private var availableAudioInputChannelCount: Int {
        if let audioInputAvailableChannelCountOverrideForTesting {
            return max(0, audioInputAvailableChannelCountOverrideForTesting)
        }
        return mainAudioGraph.availableInputChannelCount
    }

    private func isAudioInputBarBoundary(_ tickIndex: UInt64) -> Bool {
        tickIndex % UInt64(stepsPerBar) == 0
    }

    private func nextAudioInputBarBoundary(after tickIndex: UInt64) -> UInt64 {
        let barLength = UInt64(stepsPerBar)
        let ticksIntoBar = tickIndex % barLength
        let ticksUntilNextBar = ticksIntoBar == 0 ? barLength : barLength - ticksIntoBar
        return tickIndex &+ ticksUntilNextBar
    }

    static func audioInputRouteState(
        for channel: AudioInputChannel,
        availableChannelCount: Int
    ) -> AudioInputRouteState {
        let requiredChannels: Int
        switch channel {
        case .mono1:
            requiredChannels = 1
        case .mono2, .stereo:
            requiredChannels = 2
        }
        return availableChannelCount >= requiredChannels ? .available : .silentUnavailable
    }

    /// Push per-track fader state to `sampleEngine`. Called from `syncAudioOutputs`
    /// every time the document model changes, which includes fader moves via the
    /// mixer UI. The engine prepares per-track mixers and voice pools here so
    /// tick-time sample dispatch never mutates the AVAudioEngine graph.
    private func syncSampleMixers(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        var sampleTrackIDs: Set<UUID> = []
        for track in documentModel.tracks {
            switch track.destination {
            case .sample, .slicer:
                break
            default:
                continue
            }
            sampleTrackIDs.insert(track.id)
            sampleEngine.prepareTrack(trackID: track.id)
            sampleEngine.setTrackOutputBus(trackID: track.id, busID: track.outputBusID)
            let mix = Self.effectiveMix(for: track.mix, isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id))
            sampleEngine.setTrackMix(
                trackID: track.id,
                level: mix.isMuted ? 0 : mix.clampedLevel,
                pan: mix.clampedPan
            )
            sampleEngine.setTrackSends(trackID: track.id, sendA: mix.sendA, sendB: mix.sendB)
        }

        let previouslyLiveTrackIDs = withStateLock { trackRuntime.liveSampleTrackIDs }
        for removed in previouslyLiveTrackIDs.subtracting(sampleTrackIDs) {
            sampleEngine.removeTrack(trackID: removed)
        }

        withStateLock { trackRuntime.liveSampleTrackIDs = sampleTrackIDs }
    }

    // `internal` (not private) so `@testable import` can exercise tick resolution from tests.
    static func resolvedStepNotes<R: RandomNumberGenerator>(
        for trackID: UUID,
        in playbackSnapshot: PlaybackSnapshot,
        phraseID: UUID,
        stepIndex: Int,
        chordContext: Chord?,
        state: inout GeneratedSourceEvaluationState,
        rng: inout R
    ) -> [GeneratedNote] {
        guard let resolved = playbackSnapshot.resolvedStep(
            phraseID: phraseID,
            trackID: trackID,
            stepInPhrase: stepIndex
        ),
        let program = playbackSnapshot.sourceProgram(for: trackID)
        else {
            return []
        }

        switch program.slotProgram(at: resolved.slotIndex) {
        case let .generator(generatorID, modifierGeneratorID, modifierBypassed):
            guard let generator = playbackSnapshot.generatorEntry(id: generatorID) else {
                return []
            }
            let sourceNotes = GeneratedSourceEvaluator.evaluateSourceStep(
                for: generator.params,
                stepIndex: stepIndex,
                clipChoices: playbackSnapshot.clipPool,
                rng: &rng
            )

            guard !modifierBypassed,
                  let processor = playbackSnapshot.generatorEntry(id: modifierGeneratorID)
            else {
                return sourceNotes
            }

            return GeneratedSourceEvaluator.processSourceNotes(
                sourceNotes,
                through: processor.params,
                stepIndex: stepIndex,
                clipChoices: playbackSnapshot.clipPool,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )

        case let .clip(clipID, modifierGeneratorID, modifierBypassed):
            guard let clip = playbackSnapshot.clipEntry(id: clipID) else {
                return []
            }

            let sourceNotes = GeneratedSourceEvaluator.resolveClipStep(
                for: clip,
                stepIndex: stepIndex,
                fillEnabled: resolved.fillEnabled,
                rng: &rng
            )

            guard !modifierBypassed,
                  let processor = playbackSnapshot.generatorEntry(id: modifierGeneratorID)
            else {
                return sourceNotes
            }

            return GeneratedSourceEvaluator.processSourceNotes(
                sourceNotes,
                through: processor.params,
                stepIndex: stepIndex,
                clipChoices: playbackSnapshot.clipPool,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )
        case .empty:
            return []
        }
    }

    private static func resolvedAuditionOverrideNotes<R: RandomNumberGenerator>(
        for state: PseudoClipState,
        trackType: TrackType,
        stepIndex: Int,
        rng: inout R
    ) -> [GeneratedNote] {
        let clip = ClipPoolEntry(
            id: state.sourceTrackID,
            name: "Audition Override",
            trackType: trackType,
            content: state.noteGrid
        )
        return GeneratedSourceEvaluator.resolveClipStep(
            for: clip,
            stepIndex: stepIndex,
            fillEnabled: false,
            rng: &rng
        )
    }

    private func flushAllPendingMIDINoteOffs(now: TimeInterval) {
        let midiOutBlocks = withStateLock { Array(trackRuntime.midiOutBlocksByTrackID.values) }
        midiOutBlocks.forEach { $0.flushPendingNoteOffs(now: now) }

        let routedOutputs = withStateLock { Array(routerDispatch.midiOutputs.values) }
        routedOutputs.forEach { $0.flushPendingNoteOffs(now: now) }
    }

    private func flushDetachedMIDINoteOffs(
        from previousDocument: Project,
        to nextDocument: Project,
        now: TimeInterval
    ) {
        let previousTracks = Dictionary(uniqueKeysWithValues: previousDocument.tracks.map { ($0.id, $0) })
        let nextTracks = Dictionary(uniqueKeysWithValues: nextDocument.tracks.map { ($0.id, $0) })
        let previousMuteState = Self.effectiveMixerMuteState(for: previousDocument)
        let nextMuteState = Self.effectiveMixerMuteState(for: nextDocument)
        let midiOutBlocks = withStateLock { trackRuntime.midiOutBlocksByTrackID }

        for (trackID, previousTrack) in previousTracks {
            let previousEffective = Self.effectiveDestination(for: trackID, in: previousDocument).destination
            guard case .midi = previousEffective,
                  !previousMuteState.mutedTrackIDs.contains(previousTrack.id)
            else {
                continue
            }

            let nextTrack = nextTracks[trackID]
            let nextEffective = nextTrack.map { _ in
                Self.effectiveDestination(for: trackID, in: nextDocument).destination
            }
            let stillTargetsPrimaryMIDI = nextTrack?.mix.isMuted == false && {
                guard !nextMuteState.mutedTrackIDs.contains(trackID) else {
                    return false
                }
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

        let routedOutputs = withStateLock { routerDispatch.midiOutputs }
        for destination in detachedRoutedDestinations {
            routedOutputs[destination]?.flushPendingNoteOffs(now: now)
        }

        withStateLock {
            routerDispatch.removeOutputs(for: detachedRoutedDestinations)
        }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func syncMasterBusPerformanceOverlay(for masterBus: MasterBusState) {
        let normalizedOverlay = masterBusPerformanceOverlay.normalized(for: masterBus)
        if normalizedOverlay != masterBusPerformanceOverlay {
            masterBusPerformanceOverlay = normalizedOverlay
        }
    }

    private func applyMasterBusIfChanged(_ masterBus: MasterBusState) {
        let normalized = masterBus.normalized()
        syncMasterBusPerformanceOverlay(for: normalized)
        guard masterBusHost.appliedState != normalized else {
            return
        }
        masterBusHost.apply(normalized)
    }
}

extension EngineController: EngineLifecycleControlling {}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
