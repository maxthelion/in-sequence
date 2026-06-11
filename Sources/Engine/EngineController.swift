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

    struct NoteRepeatRuntimeSnapshot: Equatable, Sendable {
        let trackID: UUID
        let engagedAtTickIndex: UInt64
        let interval: NoteRepeatInterval
        let capturedStep: NoteRepeatCapturedStep?
    }

    struct NoteRepeatCapturedStep: Equatable, Sendable {
        let stepIndex: UInt64
        let notes: [NoteEvent]
    }

    struct NoteRepeatScheduledOutput: Equatable, Sendable {
        let stepIndex: UInt64
        let scheduledHostTime: TimeInterval
        let noteCount: Int
    }

    private struct PhraseNavigationState: Equatable {
        var currentPhraseID: UUID?
        var queuedPhraseID: UUID?
        var basisPhraseID: UUID?
        var phraseCycleStartTick: UInt64 = 0
        var currentPhraseCompletedCycles: Int = 0
    }

    private struct ActiveNoteRepeatRuntime: Equatable, Sendable {
        let trackID: UUID
        let engagedAtTickIndex: UInt64
        let interval: NoteRepeatInterval
        let capturedStep: NoteRepeatCapturedStep?
        var scheduledOutputs: [NoteRepeatScheduledOutput] = []

        var snapshot: NoteRepeatRuntimeSnapshot {
            NoteRepeatRuntimeSnapshot(
                trackID: trackID,
                engagedAtTickIndex: engagedAtTickIndex,
                interval: interval,
                capturedStep: capturedStep
            )
        }
    }

    private struct PendingStepOrderTogglePayload: Equatable {
        var request: StepOrderPendingToggleRequest
        var enabledMapValues: [UInt8]?
    }

    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let sharedAudioOutput: TrackPlaybackSink?
    private let audioOutputFactory: (() -> TrackPlaybackSink)?
    private let mainAudioGraph: MainAudioGraph
    private let masterBusHost: MasterBusHosting
    private let stepsPerBar: Int
    private let stateLock = NSLock()
    @ObservationIgnored
    private let phraseNavigationLock = NSLock()
    @ObservationIgnored
    private let stepOrderPendingLock = NSLock()
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
    private let audioInputCapturePCMWriterSlot = AudioInputCapturePCMWriterSlot()
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
    /// Destination for completed audio-input captures. Nil (the default for
    /// engine-only constructions, e.g. unit tests) disables persistence; the
    /// production document session injects `RecordingLibrary.shared`.
    private let recordingLibrary: RecordingLibrary?
    /// Recording WAV/sidecar writes happen here — never on the tick queue or
    /// main. Utility QoS: a late library write must not compete with audio.
    private let recordingPersistenceQueue = DispatchQueue(
        label: "ai.sequencer.SequencerAI.RecordingPersistence",
        qos: .utility
    )

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    /// Main-published mirror of the transport tick for UI observation.
    /// Engine-internal code must read `currentTransportTick` instead: this
    /// property is written via publishToMain, so tick-queue readers would see
    /// stale values (and race the main-thread write).
    private(set) var transportTickIndex: UInt64 = 0
    /// Cross-thread source of truth for the transport tick, written on the
    /// tick queue at prepare time.
    private let transportTickAtomic = AtomicInt64(0)

    var currentTransportTick: UInt64 {
        UInt64(bitPattern: transportTickAtomic.load())
    }
    private(set) var transportPosition = "1:1:1"
    private(set) var transportMode: TransportMode = .free
    private(set) var lastNoteTriggerUptime: TimeInterval = 0
    private(set) var lastNoteTriggerCount: Int = 0
    private(set) var executor: Executor?
    private(set) var selectedOutput: Destination.Kind
    private(set) var masterBusPerformanceOverlay = MasterBusPerformanceOverlayState()
    private(set) var audioInputRuntimeRevision = 0
    /// Narrow UI publisher for note-repeat runtime state (engage/release —
    /// gesture rate, never tick rate). `noteRepeatRuntimeSnapshot(for:)`
    /// reads it so playhead-leaf views re-evaluate on engage/release without
    /// the page observing any tick-rate state (architecture verdict §2:
    /// high-frequency state goes through narrow dedicated publishers).
    private(set) var noteRepeatRuntimeUIRevision = 0

    private var currentTrackMix = TrackMixSettings.default
    private var currentDocumentModel: Project = .empty
    private let tickState = TickStateBuffer(playbackSnapshot: SequencerSnapshotCompiler.compile(state: .empty))
    private let trackRuntime = TrackRuntimeRegistry()
    private let routerDispatch = RouterDispatchState()
    @ObservationIgnored
    private var phraseNavigationState = PhraseNavigationState()
    @ObservationIgnored
    private var activeNoteRepeatsByTrackID: [UUID: ActiveNoteRepeatRuntime] = [:]
    @ObservationIgnored
    private var preparedNoteRepeatCapturesByStepIndex: [UInt64: [UUID: NoteRepeatCapturedStep]] = [:]
    @ObservationIgnored
    private var currentNoteRepeatCapturesByTrackID: [UUID: NoteRepeatCapturedStep] = [:]
    @ObservationIgnored
    private var pendingStepOrderTogglePayload: PendingStepOrderTogglePayload?
    @ObservationIgnored
    var stepOrderToggleAppliedHandler: ((StepOrderPendingToggleRequest) -> Void)?
    /// Main-only @Observable mirror for UI. The tick queue must read
    /// `chordContextByLaneEngine` (under stateLock) instead: a one-sided
    /// lock on the reader synchronizes nothing against the main-thread
    /// writer (data race R2).
    private(set) var chordContextByLane: [String: Chord] = [:]
    /// Engine-side copy, guarded by `stateLock` on both sides; written at
    /// dispatch time on the tick queue, read by `prepareTick`.
    @ObservationIgnored
    private var chordContextByLaneEngine: [String: Chord] = [:]

    private(set) var currentPhraseID: UUID?
    private(set) var queuedPhraseID: UUID?
    private(set) var basisPhraseID: UUID?
    private(set) var stepOrderPendingToggle: StepOrderPendingToggleRequest?

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

    private func scheduledAudioTime(for scheduledHostTime: TimeInterval) -> AVAudioTime {
        AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(0, scheduledHostTime)))
    }

    private func publishNoteActivity(uptime: TimeInterval, count: Int) {
        guard count > 0 else {
            return
        }

        publishToMain { [weak self] in
            guard let self else { return }
            guard uptime >= self.lastNoteTriggerUptime else { return }
            self.lastNoteTriggerUptime = uptime
            self.lastNoteTriggerCount = count
        }
    }

    private func mutatePhraseNavigationState(
        _ body: (inout PhraseNavigationState) -> Void
    ) -> PhraseNavigationState? {
        phraseNavigationLock.lock()
        defer { phraseNavigationLock.unlock() }
        let previousState = phraseNavigationState
        body(&phraseNavigationState)
        let updatedState = phraseNavigationState
        return updatedState == previousState ? nil : updatedState
    }

    private func publishPhraseNavigationStateIfChanged(_ state: PhraseNavigationState?) {
        guard let state else { return }
        publishToMain { [weak self] in
            guard let self else { return }
            var didPublish = false
            if self.currentPhraseID != state.currentPhraseID {
                self.currentPhraseID = state.currentPhraseID
                didPublish = true
            }
            if self.queuedPhraseID != state.queuedPhraseID {
                self.queuedPhraseID = state.queuedPhraseID
                didPublish = true
            }
            if self.basisPhraseID != state.basisPhraseID {
                self.basisPhraseID = state.basisPhraseID
                didPublish = true
            }
            if didPublish {
                self.phraseNavigationPublicationCountForTesting += 1
            }
        }
    }

    private func firstValidPhraseID(in snapshot: PlaybackSnapshot) -> UUID? {
        if snapshot.phraseBuffer(for: snapshot.selectedPhraseID) != nil {
            return snapshot.selectedPhraseID
        }
        return snapshot.phraseOrder.first { snapshot.phraseBuffer(for: $0) != nil }
    }

    private func validPhraseID(_ phraseID: UUID?, in snapshot: PlaybackSnapshot) -> UUID? {
        guard let phraseID,
              snapshot.phraseBuffer(for: phraseID) != nil
        else {
            return nil
        }
        return phraseID
    }

    private func nextValidPhraseID(after phraseID: UUID, in snapshot: PlaybackSnapshot) -> UUID? {
        let validPhraseIDs = snapshot.phraseOrder.filter { snapshot.phraseBuffer(for: $0) != nil }
        guard !validPhraseIDs.isEmpty else {
            return nil
        }
        guard let currentIndex = validPhraseIDs.firstIndex(of: phraseID) else {
            return validPhraseIDs.first
        }
        return validPhraseIDs[(currentIndex + 1) % validPhraseIDs.count]
    }

    private func nextPhraseCycleStartTick() -> UInt64 {
        tickState.currentPreparedTickIndex() ?? currentTransportTick
    }

    private func initializePhraseNavigationForPlaybackStart(snapshot: PlaybackSnapshot, cycleStartTick: UInt64) {
        let fallbackPhraseID = firstValidPhraseID(in: snapshot)
        let updatedState = mutatePhraseNavigationState { state in
            state.currentPhraseID = fallbackPhraseID
            if validPhraseID(state.queuedPhraseID, in: snapshot) == nil {
                state.queuedPhraseID = nil
            }
            state.basisPhraseID = validPhraseID(state.queuedPhraseID, in: snapshot)
                ?? validPhraseID(state.currentPhraseID, in: snapshot)
                ?? fallbackPhraseID
            state.phraseCycleStartTick = cycleStartTick
            state.currentPhraseCompletedCycles = 0
        }
        publishPhraseNavigationStateIfChanged(updatedState)
    }

    private func clearQueuedPhraseOnStop(snapshot: PlaybackSnapshot) {
        let fallbackPhraseID = firstValidPhraseID(in: snapshot)
        let updatedState = mutatePhraseNavigationState { state in
            state.queuedPhraseID = nil
            if validPhraseID(state.currentPhraseID, in: snapshot) == nil {
                state.currentPhraseID = fallbackPhraseID
                state.currentPhraseCompletedCycles = 0
            }
            state.basisPhraseID = fallbackPhraseID
        }
        publishPhraseNavigationStateIfChanged(updatedState)
    }

    private func reconcilePhraseNavigation(
        snapshot: PlaybackSnapshot,
        cycleStartTickForChangedCurrent: UInt64
    ) {
        let fallbackPhraseID = firstValidPhraseID(in: snapshot)
        let updatedState = mutatePhraseNavigationState { state in
            let previousCurrentPhraseID = state.currentPhraseID
            if validPhraseID(state.currentPhraseID, in: snapshot) == nil {
                state.currentPhraseID = fallbackPhraseID
            }
            if state.currentPhraseID != previousCurrentPhraseID {
                state.phraseCycleStartTick = cycleStartTickForChangedCurrent
                state.currentPhraseCompletedCycles = 0
            }
            if validPhraseID(state.queuedPhraseID, in: snapshot) == nil {
                state.queuedPhraseID = nil
            }
            if validPhraseID(state.basisPhraseID, in: snapshot) == nil {
                state.basisPhraseID = isRunning
                    ? (state.queuedPhraseID ?? state.currentPhraseID ?? fallbackPhraseID)
                    : fallbackPhraseID
            }
            if !isRunning, state.queuedPhraseID == nil {
                state.basisPhraseID = fallbackPhraseID
            }
        }
        publishPhraseNavigationStateIfChanged(updatedState)
    }

    private func playbackPhraseForPrepare(
        upcomingStep: UInt64,
        snapshot: PlaybackSnapshot
    ) -> (phraseID: UUID, stepInPhrase: Int, didEnterPhraseBoundary: Bool, completedPhraseID: UUID?) {
        let fallbackPhraseID = firstValidPhraseID(in: snapshot)
        var playbackPhraseID = fallbackPhraseID ?? snapshot.selectedPhraseID
        var stepInPhrase = 0
        var didEnterPhraseBoundary = false
        var completedPhraseID: UUID?
        let updatedState = mutatePhraseNavigationState { state in
            if validPhraseID(state.currentPhraseID, in: snapshot) == nil {
                state.currentPhraseID = fallbackPhraseID
                state.phraseCycleStartTick = upcomingStep
                state.currentPhraseCompletedCycles = 0
            }
            if validPhraseID(state.queuedPhraseID, in: snapshot) == nil {
                state.queuedPhraseID = nil
            }

            playbackPhraseID = state.currentPhraseID ?? fallbackPhraseID ?? snapshot.selectedPhraseID
            let phraseBuffer = snapshot.phraseBuffer(for: playbackPhraseID)
                ?? snapshot.phraseBuffer(for: snapshot.selectedPhraseID)
            let phraseStepCount = phraseBuffer?.stepCount ?? 1
            stepInPhrase = Self.phraseLocalStep(
                upcomingStep: upcomingStep,
                cycleStartTick: state.phraseCycleStartTick,
                stepCount: phraseStepCount
            )

            if stepInPhrase == 0, upcomingStep != state.phraseCycleStartTick {
                didEnterPhraseBoundary = true
                completedPhraseID = playbackPhraseID
                if let queuedPhraseID = state.queuedPhraseID,
                   snapshot.phraseBuffer(for: queuedPhraseID) != nil {
                    state.currentPhraseID = queuedPhraseID
                    state.queuedPhraseID = nil
                    state.basisPhraseID = queuedPhraseID
                    state.phraseCycleStartTick = upcomingStep
                    state.currentPhraseCompletedCycles = 0
                    playbackPhraseID = queuedPhraseID
                    stepInPhrase = 0
                } else if let phraseBuffer {
                    state.queuedPhraseID = nil
                    let completedCycles = state.currentPhraseCompletedCycles + 1
                    if phraseBuffer.loopEnabled || phraseBuffer.repeatCount == 0 {
                        state.phraseCycleStartTick = upcomingStep
                        state.currentPhraseCompletedCycles = 0
                    } else if completedCycles < phraseBuffer.repeatCount {
                        state.phraseCycleStartTick = upcomingStep
                        state.currentPhraseCompletedCycles = completedCycles
                    } else if let nextPhraseID = nextValidPhraseID(after: playbackPhraseID, in: snapshot) {
                        state.currentPhraseID = nextPhraseID
                        state.basisPhraseID = nextPhraseID
                        state.phraseCycleStartTick = upcomingStep
                        state.currentPhraseCompletedCycles = 0
                        playbackPhraseID = nextPhraseID
                        stepInPhrase = 0
                    } else {
                        state.phraseCycleStartTick = upcomingStep
                        state.currentPhraseCompletedCycles = 0
                    }
                } else if state.queuedPhraseID != nil {
                    state.queuedPhraseID = nil
                }
            }
            if validPhraseID(state.basisPhraseID, in: snapshot) == nil {
                state.basisPhraseID = state.queuedPhraseID ?? state.currentPhraseID ?? fallbackPhraseID
            }
        }
        publishPhraseNavigationStateIfChanged(updatedState)
        return (playbackPhraseID, stepInPhrase, didEnterPhraseBoundary, completedPhraseID)
    }

    private func pendingStepOrderPayload() -> PendingStepOrderTogglePayload? {
        stepOrderPendingLock.lock()
        defer { stepOrderPendingLock.unlock() }
        return pendingStepOrderTogglePayload
    }

    private func clearPendingStepOrderPayload(matching phraseID: UUID? = nil) -> StepOrderPendingToggleRequest? {
        stepOrderPendingLock.lock()
        defer { stepOrderPendingLock.unlock() }
        guard let payload = pendingStepOrderTogglePayload,
              phraseID == nil || payload.request.phraseID == phraseID
        else {
            return nil
        }
        pendingStepOrderTogglePayload = nil
        return payload.request
    }

    private func publishPendingStepOrderToggle(_ request: StepOrderPendingToggleRequest?) {
        publishToMain { [weak self] in
            self?.stepOrderPendingToggle = request
        }
    }

    private func applyPendingStepOrderToggleAtPhraseBoundary(
        completedPhraseID: UUID,
        enteredPhraseID: UUID,
        in snapshot: PlaybackSnapshot
    ) -> (snapshot: PlaybackSnapshot, appliedRequest: StepOrderPendingToggleRequest?) {
        guard let payload = pendingStepOrderPayload() else {
            return (snapshot, nil)
        }
        guard let phraseBuffer = snapshot.phraseBuffer(for: payload.request.phraseID) else {
            _ = clearPendingStepOrderPayload(matching: payload.request.phraseID)
            publishPendingStepOrderToggle(nil)
            return (snapshot, nil)
        }

        let stepOrderMap: [UInt8]?
        if payload.request.requestedEnabled {
            guard let values = payload.enabledMapValues,
                  StepOrderMap.isValidValues(values),
                  phraseBuffer.stepCount == StepOrderMap.stepCount
            else {
                _ = clearPendingStepOrderPayload(matching: payload.request.phraseID)
                publishPendingStepOrderToggle(nil)
                return (snapshot, nil)
            }
            stepOrderMap = values
        } else {
            stepOrderMap = nil
        }
        guard payload.request.phraseID == completedPhraseID ||
            payload.request.phraseID == enteredPhraseID
        else {
            return (snapshot, nil)
        }

        _ = clearPendingStepOrderPayload(matching: payload.request.phraseID)
        publishPendingStepOrderToggle(nil)
        let updatedPhraseBuffer = phraseBuffer.withStepOrderMap(stepOrderMap)
        return (snapshot.replacingPhraseBuffer(updatedPhraseBuffer), payload.request)
    }

    private static func phraseLocalStep(upcomingStep: UInt64, cycleStartTick: UInt64, stepCount: Int) -> Int {
        let resolvedStepCount = UInt64(max(1, stepCount))
        guard upcomingStep >= cycleStartTick else {
            return Int(upcomingStep % resolvedStepCount)
        }
        return Int((upcomingStep - cycleStartTick) % resolvedStepCount)
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
        publishesAudioInputCapture: Bool = false,
        recordingLibrary: RecordingLibrary? = nil
    ) {
        self.mainAudioGraph = mainAudioGraph
        self.sampleEngine = sampleEngine ?? SamplePlaybackEngine(audioGraph: mainAudioGraph)
        self.sampleLibrary = sampleLibrary
        self.recordingLibrary = recordingLibrary
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
        DevActivity.trace(DevActivity.engine, "EngineController.start")

        initializePhraseNavigationForPlaybackStart(
            snapshot: tickState.currentPlaybackSnapshot(),
            cycleStartTick: 0
        )
        let hosts = withStateLock { Array(trackRuntime.audioOutputsByTrackID.values) }
        hosts.forEach { $0.startIfNeeded() }
        try? sampleEngine.start()

        prepareTick(upcomingStep: 0, now: ProcessInfo.processInfo.systemUptime)
        promotePreparedNoteRepeatCapture(for: 0)
        tickState.markPreparedTick(0)
        isRunning = true
        clock.start { [weak self] tickIndex, now in
            self?.processTick(tickIndex: tickIndex, now: now)
        }
    }

    func stop() {
        DevActivity.trace(DevActivity.engine, "EngineController.stop (isRunning=\(isRunning))")
        let now = ProcessInfo.processInfo.systemUptime
        guard isRunning else {
            clearNoteRepeatCaptureCaches()
            clearAllNoteRepeats(now: now)
            return
        }

        clearAllNoteRepeats(now: now)
        flushAllPendingMIDINoteOffs(now: now)
        DevActivity.trace(DevActivity.clock, "TickClock.stop requested (joins tick queue)")
        clock.stop()
        DevActivity.trace(DevActivity.clock, "TickClock.stop returned")
        let hosts = withStateLock { Array(trackRuntime.audioOutputsByTrackID.values) }
        hosts.forEach { $0.stop() }
        isRunning = false
        lastNoteTriggerUptime = 0
        lastNoteTriggerCount = 0
        sampleEngine.stop()
        tickState.resetRuntimeState()
        clearNoteRepeatCaptureCaches()
        clearAllNoteRepeats(now: now)
        clearQueuedPhraseOnStop(snapshot: tickState.currentPlaybackSnapshot())
    }

    /// Master render to file — records what reaches the master output.
    @discardableResult
    func startMasterRender(to url: URL) -> Bool {
        mainAudioGraph.startMasterRender(to: url)
    }

    @discardableResult
    func stopMasterRender() -> URL? {
        mainAudioGraph.stopMasterRender()
    }

    var isMasterRenderActive: Bool {
        mainAudioGraph.isMasterRenderActive
    }

    func applyAudioDeviceUIDs(inputUID: String?, outputUID: String?) throws -> AudioDeviceApplyResult {
        DevActivity.trace(DevActivity.audioGraph, "applyAudioDeviceUIDs input=\(inputUID ?? "nil") output=\(outputUID ?? "nil")")
        let result: AudioDeviceApplyResult
        if let audioDeviceApplyOverrideForTesting {
            result = try audioDeviceApplyOverrideForTesting(inputUID, outputUID)
        } else {
            result = try mainAudioGraph.applyAudioDeviceUIDs(inputUID: inputUID, outputUID: outputUID)
        }

        // The new input device can expose a different channel count, so the
        // audio-input route states (and ARM availability in the UI) must be
        // recomputed against it.
        refreshAudioInputRouteStates()
        return result
    }

    /// Called after the user grants microphone access so route states and
    /// graph connections reflect the now-usable input device.
    func microphoneAccessChanged() {
        refreshAudioInputRouteStates()
    }

    /// Recompute every audio-input runtime's route state against the current
    /// device's channel count, then resync graph routing.
    private func refreshAudioInputRouteStates() {
        let inputTrackIDs = withStateLock { Array(trackRuntime.audioInputRuntimes.keys) }
        for trackID in inputTrackIDs {
            _ = updateAudioInputRuntime(trackID: trackID) { runtime in
                runtime.routeState = audioInputRouteState(for: runtime.selectedInputChannel)
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
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

    enum AudioInputRecordQuantize: String, CaseIterable, Equatable, Sendable {
        case bar
        case phrase
    }

    @discardableResult
    func armAudioInput(
        trackID: UUID,
        quantize: AudioInputRecordQuantize = .bar,
        pendingStartTick: UInt64? = nil
    ) -> Bool {
        let selectedInputChannel = withStateLock { trackRuntime.audioInputRuntimes[trackID]?.selectedInputChannel }
        guard let selectedInputChannel,
              audioInputRouteState(for: selectedInputChannel) == .available
        else {
            syncAudioInputRouting(for: currentDocumentModel)
            return false
        }

        let scheduledStartTick = pendingStartTick ?? {
            switch quantize {
            case .bar:
                return nextAudioInputBarBoundary(after: currentTransportTick)
            case .phrase:
                return nextAudioInputPhraseBoundary(after: currentTransportTick)
            }
        }()
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.armState = .armed
            runtime.pendingStartTick = scheduledStartTick
            runtime.pendingStopTick = nil
            runtime.pendingLoopStartTick = nil
            runtime.captureStartTick = nil
            runtime.captureEndTick = nil
            runtime.armedRecordBarLength = runtime.recordBarLength
            runtime.scheduledLoopPlaybackID = nil
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
                audioInputCapturePCMWriterSlot.install(nil)
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
                runtime.scheduledLoopPlaybackID = nil
            case .loop:
                if runtime.hasRecordedLoop {
                    if runtime.activeMonitorMode != .loop {
                        runtime.pendingLoopStartTick = nextAudioInputBarBoundary(after: currentTransportTick)
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
            runtime.recordedLibraryAssetID = nil
            runtime.scheduledLoopPlaybackID = nil
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
            audioInputCapturePCMWriterSlot.install(nil)
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
    var audioInputCapturePlanOverrideForTesting: ((_ trackID: UUID, _ bars: Int) -> AudioInputCapturePlan?)?
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
        let now = ProcessInfo.processInfo.systemUptime
        let hosts = withStateLock { Self.uniqueHosts(Array(trackRuntime.audioOutputsByTrackID.values)) }
        if isRunning {
            clearAllNoteRepeats(now: now)
            flushAllPendingMIDINoteOffs(now: now)
            clock.stop()
            isRunning = false
            lastNoteTriggerUptime = 0
            lastNoteTriggerCount = 0
        } else if tickState.hasPreparedTick() {
            clearAllNoteRepeats(now: now)
            clock.stop()
        } else {
            clearAllNoteRepeats(now: now)
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

    func engageNoteRepeat(trackID: UUID) {
        let snapshot = tickState.currentPlaybackSnapshot()
        guard supportsNoteRepeat(trackID: trackID, in: snapshot),
              let track = snapshot.tracks.first(where: { $0.id == trackID })
        else {
            return
        }

        cleanupNoteRepeats(for: [trackID], now: ProcessInfo.processInfo.systemUptime, clearActiveState: true)
        withStateLock {
            activeNoteRepeatsByTrackID[trackID] = ActiveNoteRepeatRuntime(
                trackID: trackID,
                engagedAtTickIndex: currentTransportTick,
                interval: track.noteRepeatInterval,
                capturedStep: currentNoteRepeatCapturesByTrackID[trackID]
            )
        }
        publishNoteRepeatRuntimeUIRevision()
        invalidatePreparedNoteRepeatScheduling()
    }

    func releaseNoteRepeat(trackID: UUID) {
        cleanupNoteRepeats(for: [trackID], now: ProcessInfo.processInfo.systemUptime, clearActiveState: true)
        invalidatePreparedNoteRepeatScheduling()
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
        reconcilePhraseNavigation(
            snapshot: compiledSnapshot,
            cycleStartTickForChangedCurrent: nextPhraseCycleStartTick()
        )
        clearNoteRepeatCaptureCaches()
        reconcileNoteRepeats(with: compiledSnapshot)
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
        reconcilePhraseNavigation(
            snapshot: playbackSnapshot,
            cycleStartTickForChangedCurrent: nextPhraseCycleStartTick()
        )
        clearNoteRepeatCaptureCaches()
        reconcileNoteRepeats(with: playbackSnapshot)
    }

    func apply(trackFillPreview snapshot: TrackFillPreviewPlaybackSnapshot) {
        tickState.installTrackFillPreviewSnapshot(snapshot)
        eventQueue.clear()
        clearNoteRepeatCaptureCaches()
    }

    /// Exposes the current playback snapshot for test assertions.
    /// Do not use in production code — read the published observable state instead.
    var currentPlaybackSnapshotForTesting: PlaybackSnapshot {
        tickState.currentPlaybackSnapshot()
    }

    var currentTrackFillPreviewSnapshotForTesting: TrackFillPreviewPlaybackSnapshot {
        tickState.currentTrackFillPreviewSnapshot()
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

    func noteRepeatRuntimeSnapshot(for trackID: UUID) -> NoteRepeatRuntimeSnapshot? {
        // Register the narrow revision so SwiftUI bodies calling this update
        // on engage/release (the snapshot's backing dict is intentionally
        // @ObservationIgnored — it mutates on the tick queue).
        _ = noteRepeatRuntimeUIRevision
        return withStateLock { activeNoteRepeatsByTrackID[trackID]?.snapshot }
    }

    func noteRepeatScheduledOutputsForTesting(for trackID: UUID) -> [NoteRepeatScheduledOutput] {
        withStateLock { activeNoteRepeatsByTrackID[trackID]?.scheduledOutputs ?? [] }
    }

    func pendingRepeatOwnedEventCountForTesting(trackID: UUID) -> Int {
        eventQueue.repeatOwnedEventCount(for: trackID)
    }

    var activeNoteRepeatTrackIDsForTesting: Set<UUID> {
        withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
    }

    @ObservationIgnored
    private(set) var phraseNavigationPublicationCountForTesting = 0

    var currentPhraseCompletedCyclesForTesting: Int {
        phraseNavigationLock.lock()
        defer { phraseNavigationLock.unlock() }
        return phraseNavigationState.currentPhraseCompletedCycles
    }

    @discardableResult
    func queuePhrase(_ phraseID: UUID) -> Bool {
        guard isRunning else {
            return false
        }

        let snapshot = tickState.currentPlaybackSnapshot()
        guard snapshot.phraseBuffer(for: phraseID) != nil else {
            reconcilePhraseNavigation(
                snapshot: snapshot,
                cycleStartTickForChangedCurrent: nextPhraseCycleStartTick()
            )
            return false
        }

        let updatedState = mutatePhraseNavigationState { state in
            state.queuedPhraseID = phraseID
            state.basisPhraseID = phraseID
        }
        publishPhraseNavigationStateIfChanged(updatedState)
        return true
    }

    @discardableResult
    func requestStepOrderEnabled(
        _ enabled: Bool,
        phraseID: UUID,
        enabledMapValues: [UInt8]? = nil
    ) -> Bool {
        guard isRunning else {
            return false
        }
        if enabled {
            guard let enabledMapValues,
                  StepOrderMap.isValidValues(enabledMapValues)
            else {
                return false
            }
        }

        let request = StepOrderPendingToggleRequest(phraseID: phraseID, requestedEnabled: enabled)
        stepOrderPendingLock.lock()
        pendingStepOrderTogglePayload = PendingStepOrderTogglePayload(
            request: request,
            enabledMapValues: enabled ? enabledMapValues : nil
        )
        stepOrderPendingLock.unlock()
        publishPendingStepOrderToggle(request)
        return true
    }

    func clearPendingStepOrderToggle(phraseID: UUID? = nil) {
        guard clearPendingStepOrderPayload(matching: phraseID) != nil else {
            return
        }
        publishPendingStepOrderToggle(nil)
    }

    @discardableResult
    func refreshPendingStepOrderEnabledMapValues(phraseID: UUID, enabledMapValues: [UInt8]) -> Bool {
        guard StepOrderMap.isValidValues(enabledMapValues) else {
            return false
        }

        stepOrderPendingLock.lock()
        defer { stepOrderPendingLock.unlock() }
        guard var payload = pendingStepOrderTogglePayload,
              payload.request.phraseID == phraseID,
              payload.request.requestedEnabled
        else {
            return false
        }

        payload.enabledMapValues = enabledMapValues
        pendingStepOrderTogglePayload = payload
        return true
    }

    @discardableResult
    func switchPhraseNow(_ phraseID: UUID) -> Bool {
        let snapshot = tickState.currentPlaybackSnapshot()
        guard snapshot.phraseBuffer(for: phraseID) != nil else {
            reconcilePhraseNavigation(
                snapshot: snapshot,
                cycleStartTickForChangedCurrent: nextPhraseCycleStartTick()
            )
            return false
        }

        let cycleStartTick = nextPhraseCycleStartTick()
        let updatedState = mutatePhraseNavigationState { state in
            state.currentPhraseID = phraseID
            state.queuedPhraseID = nil
            state.basisPhraseID = phraseID
            state.phraseCycleStartTick = cycleStartTick
            state.currentPhraseCompletedCycles = 0
        }
        invalidatePreparedPlaybackOutput(resetGeneratedStates: true)
        eventQueue.clear()
        publishPhraseNavigationStateIfChanged(updatedState)
        return true
    }

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

    /// Live level publisher for one mixer strip (track, bus, or send
    /// return) — the per-channel counterpart of `masterMeterPublisher`.
    func channelMeterPublisher(for id: ChannelMeterID) -> MasterMeterPublisher {
        mainAudioGraph.channelMeterBank.publisher(for: id)
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
        clearNoteRepeatCaptureCaches()
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
            invalidatePreparedPlaybackOutput(resetGeneratedStates: shouldResetGeneratedStates)
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
        if selectedTrack.trackType == .audioInput {
            return audioInputStatusSummary(for: selectedTrack)
        }
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

    /// Audio-input tracks have no note destination, so the generic summary
    /// used to claim "No default output"; describe the monitor routing
    /// instead, in the panel's Live/Buffer vocabulary.
    private func audioInputStatusSummary(for track: StepSequenceTrack) -> String {
        guard let runtime = audioInputRuntime(for: track.id) else {
            return "Audio In • Connecting"
        }
        if runtime.routeState == .silentUnavailable {
            return "Audio In • No input device"
        }
        let muted = track.mix.isMuted ? " (Muted)" : ""
        switch runtime.armState {
        case .armed:
            return "Audio In • Armed, records at next bar\(muted)"
        case .recording:
            let bars = runtime.armedRecordBarLength ?? runtime.recordBarLength
            return "Audio In • Recording \(bars) bar\(bars == 1 ? "" : "s")\(muted)"
        case .idle, .hasLoop:
            break
        }
        switch runtime.activeMonitorMode {
        case .input:
            return "Audio In • Live monitor\(muted)"
        case .loop:
            guard let bars = runtime.recordedLoopBarLength else {
                return "Audio In • Buffer\(muted)"
            }
            return "Audio In • Buffer (\(bars) bar\(bars == 1 ? "" : "s"))\(muted)"
        }
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        // Audio-input graph work hops to main FIRE-AND-FORGET (inline when
        // already on main, e.g. synchronous test drivers). A synchronous
        // main hop from the tick queue here closes the D2 deadlock cycle
        // against main's clock.stop()/setBPM queue.sync — the same class
        // SamplePlaybackEngine already fixed. This also moves the
        // `currentDocumentModel` read onto main, where it is mutated (R1).
        if advanceAudioInputScheduling(at: tickIndex) {
            publishToMain { [weak self] in
                guard let self else { return }
                self.syncAudioInputRouting(for: self.currentDocumentModel)
            }
        }
        // Outside the didChange branch: a loop schedule that failed once
        // (player transiently disconnected after a resync) must retry on
        // every tick, not wait for the next unrelated state change —
        // observed as permanently silent buffer playback.
        if hasPendingAudioInputLoopSchedule {
            publishToMain { [weak self] in
                guard let self else { return }
                if !self.scheduleActiveAudioInputLoopPlayback() {
                    self.syncAudioInputRouting(for: self.currentDocumentModel)
                }
            }
        }

        let needsBootstrap = !tickState.isPrepared(for: tickIndex)
        if needsBootstrap {
            prepareTick(upcomingStep: tickIndex, now: now)
        }
        promotePreparedNoteRepeatCapture(for: tickIndex)
        scheduleActiveNoteRepeatsForCurrentTick(tickIndex: tickIndex, now: now)
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
            effectiveMutedTrackIDs,
            activeNoteRepeatTrackIDs
        ) = withStateLock {
            (
                self.executor,
                self.trackRuntime.audioTrackRuntimes,
                self.trackRuntime.audioOutputsByTrackID,
                self.trackRuntime.generatorIDsByTrackID,
                self.chordContextByLaneEngine,
                self.trackRuntime.effectiveMutedTrackIDs,
                Set(self.activeNoteRepeatsByTrackID.keys)
            )
        }
        let prepareInputs = tickState.readPrepareInputs()
        let generatedStates = prepareInputs.generatedStates
        let clipCaptureService = prepareInputs.clipCaptureService
        var playbackSnapshot = prepareInputs.playbackSnapshot
        let trackFillPreview = prepareInputs.trackFillPreview
        let auditionOverridesByTrackID = prepareInputs.auditionOverridesByTrackID

        assert(executor != nil, "EngineController.prepareTick called without an executor.")
        guard let executor else {
            return
        }
        let playbackPhrase = playbackPhraseForPrepare(upcomingStep: upcomingStep, snapshot: playbackSnapshot)
        if playbackPhrase.didEnterPhraseBoundary, let completedPhraseID = playbackPhrase.completedPhraseID {
            let boundaryApplication = applyPendingStepOrderToggleAtPhraseBoundary(
                completedPhraseID: completedPhraseID,
                enteredPhraseID: playbackPhrase.phraseID,
                in: playbackSnapshot
            )
            if boundaryApplication.snapshot != playbackSnapshot {
                playbackSnapshot = boundaryApplication.snapshot
                tickState.installPlaybackSnapshot(
                    boundaryApplication.snapshot,
                    currentTrackIDs: Set(boundaryApplication.snapshot.tracks.map(\.id))
                )
            }
            if let appliedRequest = boundaryApplication.appliedRequest {
                stepOrderToggleAppliedHandler?(appliedRequest)
            }
        }
        let activePhraseID = playbackPhrase.phraseID
        let stepInPhrase = playbackPhrase.stepInPhrase
        let currentLayerSnapshot = playbackSnapshot.layerSnapshot(
            phraseID: activePhraseID,
            stepInPhrase: stepInPhrase
        )

        // Dispatch resolved macro values to their destinations (AU params / sampler).
        // Phase 1b: reads snapshot-carried tracks, not currentDocumentModel.tracks.
        macroApplier.apply(currentLayerSnapshot.macroValues, tracks: playbackSnapshot.tracks)

        var nextGeneratedStates = generatedStates
        var nextClipCaptureService = clipCaptureService
        let harmonicSidechainChord = chordContexts["default"]
        var preparedNotesByBlockID: [BlockID: [NoteEvent]] = [:]
        var capturableNotesByBlockID: [BlockID: [NoteEvent]] = [:]
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
                    phraseID: activePhraseID,
                    stepIndex: stepInPhrase,
                    chordContext: harmonicSidechainChord,
                    trackFillPreview: trackFillPreview,
                    state: &state,
                    rng: &rng
                )
                nextGeneratedStates[track.id] = state
                nextClipCaptureService.append(trackID: track.id, stepIndex: Int(upcomingStep), notes: notes)
            }
            let noteEvents = notes.map(Self.noteEvent(from:))
            capturableNotesByBlockID[generatorBlockID] = noteEvents
            preparedNotesByBlockID[generatorBlockID] = activeNoteRepeatTrackIDs.contains(track.id) ? [] : noteEvents
        }
        let outputs = executor.tick(now: now, preparedNotesByBlockID: preparedNotesByBlockID)
        recordPreparedNoteRepeatCaptures(
            stepIndex: upcomingStep,
            generatorIDsByTrackID: generatorIDs,
            preparedNotesByBlockID: capturableNotesByBlockID
        )
        let newCurrentBPM = executor.currentBPM
        let completedStep = upcomingStep == 0 ? 0 : upcomingStep &- 1
        // Written here on the tick queue so cross-thread readers
        // (currentTransportTick) see the fresh value immediately; the
        // observable mirror below still publishes on main.
        transportTickAtomic.store(Int64(bitPattern: completedStep))
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
        }
        publishNoteActivity(uptime: now, count: triggeredNoteCount)

        for runtime in audioRuntimes.values
            where !runtime.mix.isMuted
                && !currentLayerSnapshot.isMuted(runtime.trackID)
                && !activeNoteRepeatTrackIDs.contains(runtime.trackID)
        {
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
                  !activeNoteRepeatTrackIDs.contains(track.id),
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
                  !activeNoteRepeatTrackIDs.contains(track.id),
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
                // TrackPlaybackSink is immediate-only today. The queued host time is
                // retained for ownership/cancellation evidence; sink-level AU timing
                // needs a future contract extension before it can be claimed.
                host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

            case let .routedAU(trackID, destination, notes, bpm, stepsPerBar):
                guard let host = audioOutputs[trackID] else {
                    continue
                }
                applyDestinationIfNeeded(destination, trackID: trackID, host: host, outputKeys: outputKeys)
                // Routed AU output shares the immediate TrackPlaybackSink contract.
                host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

            case let .chordContextBroadcast(lane, chord):
                // Engine copy under stateLock at dispatch time (tick queue);
                // the @Observable mirror publishes on main (R2).
                withStateLock {
                    chordContextByLaneEngine[lane] = chord
                }
                publishToMain { [weak self] in
                    self?.chordContextByLane[lane] = chord
                }

            case .routedMIDI:
                break

            case let .sampleTrigger(trackID, sampleID, settings, _):
                guard let sample = sampleLibrary.sample(id: sampleID) else { continue }
                guard let url = try? sample.fileRef.resolve(libraryRoot: sampleLibraryRoot) else { continue }
                _ = sampleEngine.play(
                    sampleURL: url,
                    settings: settings,
                    trackID: trackID,
                    at: scheduledAudioTime(for: event.scheduledHostTime)
                )

            case let .sliceTrigger(trackID, sampleURL, startFrame, endFrame, settings, reverse, stepParameters, _):
                _ = sampleEngine.playSlice(
                    sampleURL: sampleURL,
                    startFrame: AVAudioFramePosition(startFrame),
                    endFrame: AVAudioFramePosition(endFrame),
                    settings: settings,
                    trackID: trackID,
                    at: scheduledAudioTime(for: event.scheduledHostTime),
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
        clearAllNoteRepeats()
        clearNoteRepeatCaptureCaches()
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
        effectiveMutedTrackIDs: Set<UUID>,
        repeatOwnerTrackID: UUID? = nil
    ) {
        for (destination, notes) in routerDispatch.noteEvents where !notes.isEmpty {
            flushRoutedNotes(
                notes,
                to: destination,
                bpm: bpm,
                snapshot: snapshot,
                layerSnapshot: layerSnapshot,
                effectiveMutedTrackIDs: effectiveMutedTrackIDs,
                repeatOwnerTrackID: repeatOwnerTrackID
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
                    ),
                    repeatOwnerTrackID: repeatOwnerTrackID
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
        effectiveMutedTrackIDs: Set<UUID>,
        repeatOwnerTrackID: UUID? = nil
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
                effectiveMutedTrackIDs: effectiveMutedTrackIDs,
                repeatOwnerTrackID: repeatOwnerTrackID
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
                effectiveMutedTrackIDs: effectiveMutedTrackIDs,
                repeatOwnerTrackID: repeatOwnerTrackID
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
        effectiveMutedTrackIDs: Set<UUID>,
        repeatOwnerTrackID: UUID? = nil
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
                    ),
                    repeatOwnerTrackID: repeatOwnerTrackID
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
                eventQueue: eventQueue,
                repeatOwnerTrackID: repeatOwnerTrackID
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
        let copyReceipt = audioInputCapturePCMWriterSlot.copy(trackID: trackID, from: buffer)
        audioInputCaptureTransport.write(
            trackID: trackID,
            packet: AudioInputCaptureBufferPacket(
                summary: summary,
                captureWriterID: copyReceipt?.writerID,
                copiedFrameCount: copyReceipt?.frameCount ?? 0
            )
        )
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
        audioInputCaptureTransport.drain { trackID, packet in
            let snapshot = audioInputCaptureStore.process(packet: packet, trackID: trackID)
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
        invalidatePreparedPlaybackOutput(resetGeneratedStates: true)
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

        // Meter registration (roadmap 29): each host meters the set of
        // tracks it currently plays — shared hosts publish one stream to
        // every strip they back.
        var meterTrackIDsByHost: [ObjectIdentifier: (host: TrackPlaybackSink, trackIDs: Set<UUID>)] = [:]
        for (trackID, host) in nextOutputs {
            meterTrackIDsByHost[ObjectIdentifier(host), default: (host, [])].trackIDs.insert(trackID)
        }
        for entry in meterTrackIDsByHost.values {
            entry.host.setMeterTrackIDs(entry.trackIDs)
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
        if desiredIDs.isEmpty {
            audioInputCapturePCMWriterSlot.install(nil)
        }
        readAudioInputCaptureStore {
            audioInputCaptureStore.keepOnly(trackIDs: desiredIDs)
        }

        let changed = withStateLock {
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
                return true
            }
            return false
        }
        if changed {
            // @Observable bump outside stateLock and on main
            // (see updateAudioInputRuntime).
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
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

    /// Cheap tick-side probe: true when some recorded loop still needs a
    /// playback schedule. The actual scheduling work hops to main (it talks
    /// to the audio graph), so the tick queue only pays the hop when there
    /// is something to do.
    private var hasPendingAudioInputLoopSchedule: Bool {
        withStateLock {
            trackRuntime.audioInputRuntimes.values.contains { runtime in
                runtime.activeMonitorMode == .loop
                    && runtime.recordedLoopID != nil
                    && runtime.scheduledLoopPlaybackID != runtime.recordedLoopID
            }
        }
    }

    /// Returns false when any pending loop schedule attempt failed (the
    /// caller rebuilds routing so the next tick's retry finds a wired
    /// player); true when nothing was pending or all attempts succeeded.
    @discardableResult
    private func scheduleActiveAudioInputLoopPlayback() -> Bool {
        var allSucceeded = true
        let candidates = withStateLock {
            trackRuntime.audioInputRuntimes.values.compactMap { runtime -> (UUID, UUID)? in
                guard runtime.activeMonitorMode == .loop,
                      let recordedLoopID = runtime.recordedLoopID,
                      runtime.scheduledLoopPlaybackID != recordedLoopID
                else {
                    return nil
                }
                return (runtime.trackID, recordedLoopID)
            }
        }

        for (trackID, loopID) in candidates {
            guard let buffer = readAudioInputCaptureStore({
                audioInputCaptureStore.completedLoopPlaybackBuffer(trackID: trackID)
            }) else {
                continue
            }
            guard mainAudioGraph.scheduleAudioInputLoopPlayback(trackID: trackID, buffer: buffer) else {
                allSucceeded = false
                continue
            }
            _ = updateAudioInputRuntime(trackID: trackID) { runtime in
                guard runtime.recordedLoopID == loopID else { return }
                runtime.scheduledLoopPlaybackID = loopID
            }
        }
        return allSucceeded
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
        // D1: capture plans resolve the graph's capture format through a
        // synchronous main hop. That hop MUST happen before stateLock is
        // taken — the tick queue parking in main.sync while holding
        // stateLock deadlocks against any main-thread withStateLock reader
        // (the input panel reads at meter rate).
        let capturePlans = resolveAudioInputCapturePlans(at: tickIndex)
        let didChange = advanceAudioInputSchedulingLocked(at: tickIndex, capturePlans: capturePlans)
        if didChange {
            // @Observable bump outside stateLock (see updateAudioInputRuntime),
            // and on main because this runs from the tick queue.
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
            }
        }
        return didChange
    }

    /// Pre-resolves the capture plan for every track whose recording would
    /// begin at this tick, BEFORE `stateLock` is taken (see D1 note above).
    /// The runtime is re-validated under the lock; a plan resolved for a
    /// track whose state moved on in the meantime is simply unused.
    private func resolveAudioInputCapturePlans(at tickIndex: UInt64) -> [UUID: AudioInputCapturePlan] {
        guard isAudioInputBarBoundary(tickIndex) else { return [:] }
        let beginCandidates: [(trackID: UUID, bars: Int)] = withStateLock {
            trackRuntime.audioInputRuntimes.values.compactMap { runtime in
                guard runtime.armState == .armed,
                      let startTick = runtime.pendingStartTick,
                      tickIndex >= startTick
                else {
                    return nil
                }
                let bars = StepSequenceTrack.normalizedRecordBarLength(
                    runtime.armedRecordBarLength ?? runtime.recordBarLength
                )
                return (runtime.trackID, bars)
            }
        }

        var plans: [UUID: AudioInputCapturePlan] = [:]
        for candidate in beginCandidates {
            plans[candidate.trackID] = audioInputCapturePlan(trackID: candidate.trackID, bars: candidate.bars)
        }
        return plans
    }

    private func advanceAudioInputSchedulingLocked(
        at tickIndex: UInt64,
        capturePlans: [UUID: AudioInputCapturePlan]
    ) -> Bool {
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
                    beginAudioInputCapture(&runtime, at: tickIndex, capturePlan: capturePlans[trackID])
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

            return didChange
        }
    }

    /// `capturePlan` is resolved by the caller OUTSIDE `stateLock`
    /// (`resolveAudioInputCapturePlans`): the plan requires the graph's
    /// capture format, a synchronous main hop that must never run while the
    /// tick queue holds the lock (D1).
    private func beginAudioInputCapture(
        _ runtime: inout AudioInputTrackRuntime,
        at tickIndex: UInt64,
        capturePlan: AudioInputCapturePlan?
    ) {
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
        let captureWriter = capturePlan.flatMap {
            AudioInputCapturePCMWriter(trackID: runtime.trackID, plan: $0)
        }
        audioInputCapturePCMWriterSlot.install(captureWriter)
        let captureStart = readAudioInputCaptureStore {
            audioInputCaptureStore.beginCapture(trackID: runtime.trackID, writer: captureWriter)
        }
        applyAudioInputCaptureSnapshot(
            captureStart,
            to: &runtime
        )
    }

    private func audioInputCapturePlan(trackID: UUID, bars: Int) -> AudioInputCapturePlan? {
        if let override = audioInputCapturePlanOverrideForTesting {
            return override(trackID, bars)
        }

        // CONTRACT (D1): the capture-format read below is a synchronous main
        // hop; performing it while holding stateLock deadlocks the app the
        // moment recording begins at a bar boundary.
        debugAssertNotHoldingStateLock("audioInputCaptureFormat read")
        guard let format = mainAudioGraph.audioInputCaptureFormat(trackID: trackID) else {
            return nil
        }

        let beatsPerBar = 4.0
        let durationSeconds = (Double(bars) * beatsPerBar * 60.0) / max(currentBPM, 1)
        let expectedFrameCount = Int((durationSeconds * format.sampleRate).rounded(.up))
        let tapSlackFrameCount = 4096
        return AudioInputCapturePlan(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            maximumFrameCount: max(1, expectedFrameCount + tapSlackFrameCount)
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
        runtime.recordedLibraryAssetID = nil
        runtime.scheduledLoopPlaybackID = nil
        runtime.transientFrameCount = Int(tickIndex &- startTick)
        let completedPCM = readAudioInputCaptureStore { () -> AudioInputCapturedPCM? in
            applyAudioInputCaptureSnapshot(
                audioInputCaptureStore.completeCapture(trackID: runtime.trackID),
                to: &runtime
            )
            return audioInputCaptureStore.completedLoopPCM(trackID: runtime.trackID)
        }
        audioInputCapturePCMWriterSlot.install(nil)
        // Persist the take into the global recording library. We only capture
        // the PCM reference here (value type, COW); the file write happens on
        // the persistence queue — never on this tick path and never on main.
        schedulePersistCapturedRecording(pcm: completedPCM, trackID: runtime.trackID, barCount: bars)
        // Auto-switch to Buffer the moment the take completes (owner
        // direction): the captured loop becomes what you hear; Live is one
        // toggle away. Completion lands on a bar boundary, so entry is
        // immediate.
        runtime.monitorMode = .loop
        runtime.pendingLoopStartTick = nil
        runtime.activeMonitorMode = .loop
    }

    /// Test observation of the async recording persistence (success or
    /// failure). Invoked on the main thread after the runtime tag lands.
    var recordingPersistenceObserverForTesting: ((Result<RecordingAsset, Error>) -> Void)?

    /// Write a completed capture into the recording library. Name/BPM are
    /// main-published state, so they resolve on main; the blocking file IO
    /// runs on `recordingPersistenceQueue`. A write failure traces to the
    /// activity log and leaves the in-memory loop untouched — the session
    /// keeps playing from memory.
    private func schedulePersistCapturedRecording(
        pcm: AudioInputCapturedPCM?,
        trackID: UUID,
        barCount: Int
    ) {
        guard let recordingLibrary else { return }
        guard let pcm, pcm.frameCount > 0 else {
            DevActivity.trace(DevActivity.library, "recording persist skipped: no PCM for track \(trackID)")
            return
        }

        publishToMain { [weak self] in
            guard let self else { return }
            let trackName = self.currentDocumentModel.tracks.first(where: { $0.id == trackID })?.name ?? "Audio Input"
            let bpm = self.currentBPM
            self.recordingPersistenceQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let asset = try recordingLibrary.storeRecording(
                        pcm: pcm,
                        sourceTrackName: trackName,
                        barCount: barCount,
                        bpm: bpm
                    )
                    DevActivity.trace(DevActivity.library, "recording persisted: \(asset.fileName)")
                    self.publishToMain { [weak self] in
                        guard let self else { return }
                        _ = self.updateAudioInputRuntime(trackID: trackID) { runtime in
                            runtime.recordedLibraryAssetID = asset.id
                        }
                        // Recordings double as samples; rescan so pickers see
                        // the new take without an app restart.
                        self.sampleLibrary.reload()
                        self.recordingPersistenceObserverForTesting?(.success(asset))
                    }
                } catch {
                    NSLog("[EngineController] recording persist failed (loop keeps playing from memory): \(error)")
                    DevActivity.trace(DevActivity.library, "recording persist FAILED: \(error)")
                    self.publishToMain { [weak self] in
                        self?.recordingPersistenceObserverForTesting?(.failure(error))
                    }
                }
            }
        }
    }

    private func updateAudioInputRuntime(
        trackID: UUID,
        update: (inout AudioInputTrackRuntime) -> Void
    ) -> Bool {
        let updated = withStateLock {
            guard var runtime = trackRuntime.audioInputRuntimes[trackID] else {
                return false
            }
            update(&runtime)
            trackRuntime.audioInputRuntimes[trackID] = runtime
            return true
        }
        if updated {
            // The @Observable revision bump must happen OUTSIDE stateLock:
            // Observation's willSet can synchronously re-evaluate SwiftUI
            // bodies, and those bodies read engine state through the same
            // lock — observed as a main-thread deadlock the moment live
            // input levels started publishing at 60Hz.
            //
            // AND it must happen ON MAIN (D4): this is called from the tick
            // queue (loop-playback bookkeeping), and an off-main write to
            // @Observable storage runs observer callbacks on the tick thread
            // — the runtime-confirmed deadlock class when main is parked in
            // clock.stop()'s queue.sync. publishToMain runs inline when
            // already on main, preserving synchronous test drivers.
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
            }
        }
        return updated
    }

    private func audioInputRouteState(for channel: AudioInputChannel) -> AudioInputRouteState {
        Self.audioInputRouteState(for: channel, availableChannelCount: availableAudioInputChannelCount)
    }

    /// Device input channel count for UI affordances (input selector,
    /// arm-availability messaging).
    var audioInputAvailableChannels: Int {
        availableAudioInputChannelCount
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

    /// Next phrase-cycle boundary for quantized record starts. Uses the live
    /// phrase navigation state (cycle start tick + current phrase length);
    /// falls back to the next bar when no phrase is playing. A queued phrase
    /// switch after arming can move the actual boundary — v1 records at the
    /// boundary scheduled at arm time.
    private func nextAudioInputPhraseBoundary(after tickIndex: UInt64) -> UInt64 {
        let (cycleStart, phraseID): (UInt64, UUID?) = {
            phraseNavigationLock.lock()
            defer { phraseNavigationLock.unlock() }
            return (phraseNavigationState.phraseCycleStartTick, phraseNavigationState.currentPhraseID)
        }()

        let snapshot = tickState.currentPlaybackSnapshot()
        guard let phraseID,
              let buffer = snapshot.phraseBuffer(for: phraseID),
              buffer.stepCount > 0
        else {
            return nextAudioInputBarBoundary(after: tickIndex)
        }

        let phraseLength = UInt64(buffer.stepCount)
        let sinceCycleStart = tickIndex >= cycleStart ? tickIndex &- cycleStart : 0
        let intoPhrase = sinceCycleStart % phraseLength
        let ticksUntilBoundary = intoPhrase == 0 ? phraseLength : phraseLength - intoPhrase
        return tickIndex &+ ticksUntilBoundary
    }

    /// Push the document's record length into the live runtime so the next
    /// arm uses it without waiting for a full document apply.
    @discardableResult
    func setAudioInputRecordBarLength(trackID: UUID, bars: Int) -> Bool {
        DevActivity.trace(DevActivity.engine, "setAudioInputRecordBarLength bars=\(bars)")
        return updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.recordBarLength = StepSequenceTrack.normalizedRecordBarLength(bars)
        }
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
        // Any input at all is routable: mono/stereo is a property of the
        // track's content, never a hardware requirement. A stereo selection
        // on a mono device duplicates; a mono selection beyond the device's
        // channels clamps. The meters reveal one-sided signals.
        availableChannelCount >= 1 ? .available : .silentUnavailable
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
        trackFillPreview: TrackFillPreviewPlaybackSnapshot = .inactive,
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
                stepIndex: resolved.sourceStepIndex,
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
                stepIndex: resolved.sourceStepIndex,
                clipChoices: playbackSnapshot.clipPool,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )

        case let .clip(clipID, modifierGeneratorID, modifierBypassed):
            guard let clip = playbackSnapshot.clipEntry(id: clipID) else {
                return []
            }

            let effectiveFillEnabled = resolved.fillEnabled || trackFillPreview.isActive(for: trackID)
            let sourceNotes = GeneratedSourceEvaluator.resolveClipStep(
                for: clip,
                stepIndex: resolved.sourceStepIndex,
                fillEnabled: effectiveFillEnabled,
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
                stepIndex: resolved.sourceStepIndex,
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
        #if DEBUG
        Self.stateLockDepthForCurrentThread += 1
        defer { Self.stateLockDepthForCurrentThread -= 1 }
        #endif
        return body()
    }

    // MARK: - Debug lock-order assertions
    //
    // CONTRACT: no synchronous main-thread hop (performOnMain* in the audio
    // graph) may be reachable while stateLock is held — the mirror image of
    // the documented graphLock rule. Violations are the D1 deadlock class.

    #if DEBUG
    /// Per-thread stateLock hold depth (DEBUG only). NSLock has no owner
    /// readout, so withStateLock maintains this for the assertion below.
    private static let stateLockDepthKey = "ai.sequencer.SequencerAI.EngineController.stateLockDepth"

    private static var stateLockDepthForCurrentThread: Int {
        get { (Thread.current.threadDictionary[stateLockDepthKey] as? Int) ?? 0 }
        set { Thread.current.threadDictionary[stateLockDepthKey] = newValue }
    }

    /// Test hook: receives the context string instead of trapping, so tests
    /// can pin the "no main hop under stateLock" contract.
    var stateLockHoldViolationHandlerForTesting: ((String) -> Void)?

    var isHoldingStateLockForTesting: Bool {
        Self.stateLockDepthForCurrentThread > 0
    }

    /// Test-only positive control: proves the held-lock detector fires, so
    /// the "no violation" contract tests cannot pass vacuously.
    func simulateMainHopUnderStateLockForTesting() {
        withStateLock {
            debugAssertNotHoldingStateLock("simulated main hop")
        }
    }
    #endif

    /// Asserts (DEBUG) that the calling thread does not hold `stateLock`.
    /// Call before any code path that synchronously hops to main.
    private func debugAssertNotHoldingStateLock(_ context: String) {
        #if DEBUG
        guard Self.stateLockDepthForCurrentThread > 0 else { return }
        if let handler = stateLockHoldViolationHandlerForTesting {
            handler(context)
        } else {
            assertionFailure("\(context) must not run while holding stateLock (deadlock class D1)")
        }
        #endif
    }

    private func clearAllNoteRepeats(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let trackIDs = withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
        cleanupNoteRepeats(for: trackIDs, now: now, clearActiveState: true)
    }

    private func clearNoteRepeatCaptureCaches() {
        withStateLock {
            preparedNoteRepeatCapturesByStepIndex.removeAll()
            currentNoteRepeatCapturesByTrackID.removeAll()
        }
    }

    private func invalidatePreparedPlaybackOutput(resetGeneratedStates: Bool) {
        tickState.invalidatePreparedTick(resetGeneratedStates: resetGeneratedStates)
        clearNoteRepeatCaptureCaches()
    }

    private func invalidatePreparedNoteRepeatScheduling() {
        tickState.invalidatePreparedTick(resetGeneratedStates: false)
        eventQueue.clear()
    }

    private func scheduleActiveNoteRepeatsForCurrentTick(tickIndex: UInt64, now: TimeInterval) {
        let (executor, effectiveMutedTrackIDs) = withStateLock {
            (self.executor, self.trackRuntime.effectiveMutedTrackIDs)
        }
        guard let executor else {
            return
        }

        let snapshot = tickState.currentPlaybackSnapshot()
        let playbackPhrase = playbackPhraseForPrepare(upcomingStep: tickIndex, snapshot: snapshot)
        let layerSnapshot = snapshot.layerSnapshot(
            phraseID: playbackPhrase.phraseID,
            stepInPhrase: playbackPhrase.stepInPhrase
        )
        scheduleActiveNoteRepeats(
            anchorTickIndex: tickIndex,
            anchorHostTime: now,
            bpm: executor.currentBPM,
            snapshot: snapshot,
            layerSnapshot: layerSnapshot,
            effectiveMutedTrackIDs: effectiveMutedTrackIDs
        )
    }

    private func scheduleActiveNoteRepeats(
        anchorTickIndex: UInt64,
        anchorHostTime: TimeInterval,
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        let activeRepeats = withStateLock { Array(activeNoteRepeatsByTrackID.values) }
        guard !activeRepeats.isEmpty else {
            return
        }

        let secondsPerStep = Self.secondsPerStep(bpm: bpm, stepsPerBar: stepsPerBar)
        var noteActivityCount = 0
        var latestNoteActivityHostTime = anchorHostTime
        for activeRepeat in activeRepeats {
            guard supportsNoteRepeat(trackID: activeRepeat.trackID, in: snapshot),
                  let capturedStep = activeRepeat.capturedStep,
                  !capturedStep.notes.isEmpty,
                  let track = snapshot.tracks.first(where: { $0.id == activeRepeat.trackID }),
                  !effectiveMutedTrackIDs.contains(activeRepeat.trackID),
                  !layerSnapshot.isMuted(activeRepeat.trackID)
            else {
                continue
            }

            // Slower-than-step rates (1/4, 1/8) fire on every Nth step.
            // Engagement lands between ticks, so the first firing step is the
            // first tick after engagedAtTickIndex; the stride counts from it.
            let stepStride = activeRepeat.interval.v1StepStride
            if stepStride > 1 {
                let firstFiringTick = activeRepeat.engagedAtTickIndex + 1
                guard anchorTickIndex >= firstFiringTick,
                      (anchorTickIndex - firstFiringTick) % UInt64(stepStride) == 0
                else {
                    continue
                }
            }

            let triggerCount = activeRepeat.interval.v1TriggerCountPerStep
            let triggerSpacing = secondsPerStep / Double(max(1, triggerCount))
            var scheduledOutputs: [NoteRepeatScheduledOutput] = []

            for triggerIndex in 0..<triggerCount {
                let scheduledHostTime = anchorHostTime + (Double(triggerIndex) * triggerSpacing)
                dispatchNoteRepeatOutput(
                    notes: capturedStep.notes,
                    for: track,
                    at: scheduledHostTime,
                    anchorTickIndex: anchorTickIndex,
                    bpm: bpm,
                    snapshot: snapshot,
                    layerSnapshot: layerSnapshot,
                    effectiveMutedTrackIDs: effectiveMutedTrackIDs
                )
                scheduledOutputs.append(
                    NoteRepeatScheduledOutput(
                        stepIndex: anchorTickIndex,
                        scheduledHostTime: scheduledHostTime,
                        noteCount: capturedStep.notes.count
                    )
                )
                noteActivityCount += capturedStep.notes.count
                latestNoteActivityHostTime = max(latestNoteActivityHostTime, scheduledHostTime)
            }

            recordScheduledNoteRepeatOutputs(scheduledOutputs, for: activeRepeat.trackID)
        }
        publishNoteActivity(uptime: latestNoteActivityHostTime, count: noteActivityCount)
    }

    private func dispatchNoteRepeatOutput(
        notes: [NoteEvent],
        for track: StepSequenceTrack,
        at scheduledHostTime: TimeInterval,
        anchorTickIndex: UInt64,
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        let resolved = snapshot.resolvedDestination(for: track.id)
        switch resolved.destination {
        case let .midi(port, channel, noteOffset):
            guard port != nil,
                  let midiOut = withStateLock({ trackRuntime.midiOutBlocksByTrackID[track.id] })
            else {
                break
            }
            midiOut.apply(paramKey: "channel", value: .number(Double(channel)))
            midiOut.apply(paramKey: "noteOffset", value: .number(Double(noteOffset + resolved.pitchOffset)))
            _ = midiOut.tick(
                context: TickContext(
                    tickIndex: anchorTickIndex,
                    bpm: bpm,
                    inputs: ["notes": .notes(notes)],
                    now: scheduledHostTime,
                    preparedNotesByBlockID: [:]
                )
            )

        case .auInstrument:
            let audioOutputs = withStateLock { trackRuntime.audioOutputsByTrackID }
            guard audioOutputs[track.id] != nil else {
                break
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: scheduledHostTime,
                    payload: .trackAU(
                        trackID: track.id,
                        destination: resolved.destination,
                        notes: Self.shifted(notes, by: resolved.pitchOffset),
                        bpm: bpm,
                        stepsPerBar: stepsPerBar
                    ),
                    repeatOwnerTrackID: track.id
                )
            )

        case let .sample(sampleID, settings):
            for _ in notes {
                eventQueue.enqueue(
                    ScheduledEvent(
                        scheduledHostTime: scheduledHostTime,
                        payload: .sampleTrigger(
                            trackID: track.id,
                            sampleID: sampleID,
                            settings: settings,
                            scheduledHostTime: scheduledHostTime
                        ),
                        repeatOwnerTrackID: track.id
                    )
                )
            }

        case let .slicer(sliceSetID, settings):
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
                now: scheduledHostTime,
                eventQueue: eventQueue,
                repeatOwnerTrackID: track.id
            )

        case .internalSampler, .inheritGroup, .none:
            break
        }

        routerDispatch.beginTick(now: scheduledHostTime)
        router.tick([RouterTickInput(sourceTrack: track.id, notes: notes, chordContext: nil)])
        flushRoutedEvents(
            bpm: bpm,
            snapshot: snapshot,
            layerSnapshot: layerSnapshot,
            effectiveMutedTrackIDs: effectiveMutedTrackIDs,
            repeatOwnerTrackID: track.id
        )
    }

    private func recordScheduledNoteRepeatOutputs(
        _ outputs: [NoteRepeatScheduledOutput],
        for trackID: UUID
    ) {
        guard !outputs.isEmpty else {
            return
        }

        withStateLock {
            guard var activeRepeat = activeNoteRepeatsByTrackID[trackID] else {
                return
            }
            activeRepeat.scheduledOutputs.append(contentsOf: outputs)
            if activeRepeat.scheduledOutputs.count > 64 {
                activeRepeat.scheduledOutputs = Array(activeRepeat.scheduledOutputs.suffix(64))
            }
            activeNoteRepeatsByTrackID[trackID] = activeRepeat
        }
    }

    private func cleanupNoteRepeats(
        for trackIDs: Set<UUID>,
        now: TimeInterval,
        clearActiveState: Bool
    ) {
        guard !trackIDs.isEmpty else {
            return
        }

        eventQueue.cancelRepeatOwnedEvents(for: trackIDs)
        flushRepeatPendingOutput(for: trackIDs, now: now)

        let didClearActiveState = withStateLock {
            var didRemove = false
            for trackID in trackIDs {
                if clearActiveState {
                    didRemove = activeNoteRepeatsByTrackID.removeValue(forKey: trackID) != nil || didRemove
                } else if var activeRepeat = activeNoteRepeatsByTrackID[trackID] {
                    activeRepeat.scheduledOutputs.removeAll()
                    activeNoteRepeatsByTrackID[trackID] = activeRepeat
                }
            }
            return didRemove
        }
        if didClearActiveState {
            publishNoteRepeatRuntimeUIRevision()
        }
    }

    /// Bump the narrow note-repeat UI publisher. Outside stateLock and on
    /// main, same contract as `audioInputRuntimeRevision` (Observation's
    /// willSet can synchronously re-enter SwiftUI bodies that read engine
    /// state through the same lock).
    private func publishNoteRepeatRuntimeUIRevision() {
        publishToMain { [weak self] in
            self?.noteRepeatRuntimeUIRevision &+= 1
        }
    }

    private func flushRepeatPendingOutput(for trackIDs: Set<UUID>, now: TimeInterval) {
        let (midiOutBlocks, routedOutputs) = withStateLock {
            (
                trackRuntime.midiOutBlocksByTrackID,
                routerDispatch.midiOutputs
            )
        }

        for trackID in trackIDs {
            midiOutBlocks[trackID]?.flushPendingNoteOffs(now: now)
        }

        // Routed MIDI outputs are destination-owned rather than source-track-owned today.
        // Repeats therefore use a conservative no-leak cleanup contract for routed note-offs.
        routedOutputs.values.forEach { $0.flushPendingNoteOffs(now: now) }
    }

    private func recordPreparedNoteRepeatCaptures(
        stepIndex: UInt64,
        generatorIDsByTrackID: [UUID: BlockID],
        preparedNotesByBlockID: [BlockID: [NoteEvent]]
    ) {
        let captures: [UUID: NoteRepeatCapturedStep] = Dictionary(
            uniqueKeysWithValues: generatorIDsByTrackID.compactMap { trackID, blockID -> (UUID, NoteRepeatCapturedStep)? in
                guard let notes = preparedNotesByBlockID[blockID] else {
                    return nil
                }
                return (trackID, NoteRepeatCapturedStep(stepIndex: stepIndex, notes: notes))
            }
        )
        withStateLock {
            preparedNoteRepeatCapturesByStepIndex[stepIndex] = captures
            let oldestRetainedStep = stepIndex > 4 ? stepIndex - 4 : 0
            preparedNoteRepeatCapturesByStepIndex = preparedNoteRepeatCapturesByStepIndex.filter {
                $0.key >= oldestRetainedStep
            }
        }
    }

    private func promotePreparedNoteRepeatCapture(for stepIndex: UInt64) {
        withStateLock {
            currentNoteRepeatCapturesByTrackID = preparedNoteRepeatCapturesByStepIndex[stepIndex] ?? [:]
            preparedNoteRepeatCapturesByStepIndex = preparedNoteRepeatCapturesByStepIndex.filter { $0.key >= stepIndex }
        }
    }

    private func reconcileNoteRepeats(with snapshot: PlaybackSnapshot) {
        // Copy the keys out first: supportsNoteRepeat acquires
        // phraseNavigationLock, and holding stateLock across it would pin a
        // stateLock → phraseNavigationLock ordering for the whole codebase.
        let activeTrackIDs = withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
        let unsupportedTrackIDs = activeTrackIDs.filter { trackID in
            !supportsNoteRepeat(trackID: trackID, in: snapshot)
        }
        if !unsupportedTrackIDs.isEmpty {
            cleanupNoteRepeats(
                for: unsupportedTrackIDs,
                now: ProcessInfo.processInfo.systemUptime,
                clearActiveState: true
            )
        }
    }

    private func supportsNoteRepeat(trackID: UUID, in snapshot: PlaybackSnapshot) -> Bool {
        guard snapshot.tracks.contains(where: { $0.id == trackID }),
              let position = noteRepeatPlaybackPosition(in: snapshot),
              let resolved = snapshot.resolvedStep(
                  phraseID: position.phraseID,
                  trackID: trackID,
                  stepInPhrase: position.stepInPhrase
              ),
              let program = snapshot.sourceProgram(for: trackID)
        else {
            return false
        }

        switch program.slotProgram(at: resolved.slotIndex) {
        case let .clip(clipID, _, _):
            return snapshot.clipEntry(id: clipID) != nil
        case .generator, .empty:
            return false
        }
    }

    private func noteRepeatPlaybackPosition(in snapshot: PlaybackSnapshot) -> (phraseID: UUID, stepInPhrase: Int)? {
        phraseNavigationLock.lock()
        let currentPhraseID = phraseNavigationState.currentPhraseID
        phraseNavigationLock.unlock()

        let phraseID = validPhraseID(currentPhraseID, in: snapshot) ?? firstValidPhraseID(in: snapshot) ?? snapshot.selectedPhraseID
        guard let phraseBuffer = snapshot.phraseBuffer(for: phraseID) else {
            return nil
        }

        let stepCount = max(1, phraseBuffer.stepCount)
        return (phraseID, Int(currentTransportTick % UInt64(stepCount)))
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
