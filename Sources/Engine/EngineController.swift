import AVFoundation
import Foundation
import Observation

/// DEBUG mechanism for the tick-path contract (architecture verdict
/// 2026-06-12 §1): **nothing on the tick/audio path may synchronously wait
/// on main, ever.** `EngineController.processTick` marks its thread for the
/// whole tick scope; every sync-to-main helper (MainAudioGraph.performOnMain*
/// and the direct `DispatchQueue.main.sync` sites in Sources/Audio) reports
/// here before parking on main.
///
/// Default behaviour on violation is a TRAP (assertionFailure) in DEBUG.
/// No waived hops remain: the last one — the audio-input capture-format
/// read at record start — now reads a lock-protected snapshot that main
/// publishes at every graph reconfiguration point
/// (`MainAudioGraph.audioInputCaptureFormat`), and the SamplerFilterNode
/// parameter setters via TrackMacroApplier are fire-and-forget. Tests
/// install `violationHandlerForTesting` to observe violations without
/// crashing the test host and to positively prove the detector fires
/// (TickPathMainIsolationTests). Compiles to no-ops in release.
///
/// `reportImminentDeadlock` (lock re-entry / hop-under-lock) also TRAPS in
/// DEBUG: the alternative is a guaranteed wedge a few instructions later.
enum TickPathMainSyncGuard {
    #if DEBUG
    private static let markerKey = "ai.sequencer.SequencerAI.TickPathMainSyncGuard.isOnTickPath"
    private static let stateLockDepthKey = "ai.sequencer.SequencerAI.TickPathMainSyncGuard.stateLockDepth"

    /// True while the current thread is executing the tick path.
    static var isOnTickPath: Bool {
        get { (Thread.current.threadDictionary[markerKey] as? Bool) ?? false }
        set { Thread.current.threadDictionary[markerKey] = newValue }
    }

    /// Per-thread `EngineController.stateLock` hold depth. Maintained by
    /// `EngineController.withStateLock` (NSLock has no owner readout).
    /// Shared here — not private to EngineController — so the sync-to-main
    /// hop helpers in Sources/Audio can assert the mirror-image of the
    /// graphLock rule: no synchronous main hop while stateLock is held
    /// (deadlock class D1).
    static var stateLockDepthForCurrentThread: Int {
        get { (Thread.current.threadDictionary[stateLockDepthKey] as? Int) ?? 0 }
        set { Thread.current.threadDictionary[stateLockDepthKey] = newValue }
    }

    /// Test hook: receives every violation context instead of the log, so
    /// tests can pin the "no tick-path main-sync" contract (and positively
    /// prove the detector fires).
    static var violationHandlerForTesting: ((String) -> Void)?
    #endif

    /// Marks the current thread as the tick path for the duration of `body`.
    static func withTickPathMarker<T>(_ body: () -> T) -> T {
        #if DEBUG
        let wasMarked = isOnTickPath
        isOnTickPath = true
        defer { isOnTickPath = wasMarked }
        #endif
        return body()
    }

    /// Call immediately before any synchronous dispatch to main. Skips when
    /// already on main (an inline call, not a wait). Fires for two distinct
    /// contract breaks:
    /// - the calling thread is the tick path (tempo-sag/deadlock class D2);
    /// - the calling thread holds `stateLock` (deadlock class D1 — main may
    ///   be parked in `withStateLock`, so it can never drain the sync hop).
    static func assertNotSyncingToMainFromTickPath(_ context: @autoclosure () -> String) {
        #if DEBUG
        guard !Thread.isMainThread else { return }
        if isOnTickPath {
            report(context())
        }
        if stateLockDepthForCurrentThread > 0 {
            report("\(context()) while holding stateLock (deadlock class D1)")
        }
        #endif
    }

    /// Reports an imminent-deadlock lock-discipline violation (e.g. a
    /// non-recursive lock about to be re-locked by its owning thread).
    /// Unlike the tick-path log-by-default policy, this TRAPS in DEBUG when
    /// no test handler is installed: the alternative is a guaranteed wedge a
    /// few instructions later, and a crash with a message beats a silent
    /// hang. Compiles to a no-op in release.
    static func reportImminentDeadlock(_ context: @autoclosure () -> String) {
        #if DEBUG
        let resolvedContext = context()
        if let handler = violationHandlerForTesting {
            handler(resolvedContext)
            return
        }
        assertionFailure("[TickPathMainSyncGuard] IMMINENT DEADLOCK: \(resolvedContext)")
        #endif
    }

    #if DEBUG
    private static func report(_ resolvedContext: String) {
        if let handler = violationHandlerForTesting {
            handler(resolvedContext)
            return
        }
        assertionFailure(
            "[TickPathMainSyncGuard] VIOLATION: \(resolvedContext) synchronously waits " +
            "on main from the tick path (tempo-sag/deadlock class, architecture " +
            "verdict §1). Nothing on the tick path may wait on main — publish a " +
            "main-side snapshot or go fire-and-forget instead."
        )
    }
    #endif
}

enum AudioPluginChoiceScanState: Equatable {
    case idle
    case scanning
    case ready(instrumentCount: Int, effectCount: Int)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .idle:
            return "Plug-ins ready"
        case .scanning:
            return "Scanning plug-ins..."
        case let .ready(instrumentCount, effectCount):
            return "\(instrumentCount) instruments, \(effectCount) effects"
        }
    }
}

struct AudioPluginChoiceScanResult: Equatable {
    let instrumentCount: Int
    let effectCount: Int
}

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

    struct PhraseNavigationState: Equatable {
        var currentPhraseID: UUID?
        var queuedPhraseID: UUID?
        var basisPhraseID: UUID?
        var phraseCycleStartTick: UInt64 = 0
        var currentPhraseCompletedCycles: Int = 0
    }

    struct ActiveNoteRepeatRuntime: Equatable, Sendable {
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
    let sharedAudioOutput: TrackPlaybackSink?
    let audioOutputFactory: (() -> TrackPlaybackSink)?
    let mainAudioGraph: MainAudioGraph
    private let masterBusHost: MasterBusHosting
    let stepsPerBar: Int
    private let stateLock = NSLock()
    @ObservationIgnored
    let phraseNavigationLock = NSLock()
    @ObservationIgnored
    private let stepOrderPendingLock = NSLock()
    private let documentApplyLock = NSLock()
    @ObservationIgnored
    lazy var router = MIDIRouter(dispatcher: self)

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    let eventQueue = EventQueue()
    let sampleEngine: SamplePlaybackSink
    let sampleAssetCache: SampleAssetCache
    let audioInputCaptureStore = AudioInputCaptureStore()
    let audioInputCaptureTransport = AudioInputCaptureSummaryRing(capacity: 1024)
    let audioInputCapturePCMWriterSlot = AudioInputCapturePCMWriterSlot()
    let audioInputCapturePublicationQueue = DispatchQueue(
        label: "ai.sequencer.SequencerAI.AudioInputCapturePublication"
    )
    let audioInputCapturePublicationQueueKey = DispatchSpecificKey<Void>()
    private let publishesAudioInputCapture: Bool
    var audioInputCaptureDrainTimer: DispatchSourceTimer?
    // Initialized at end of init() after `self` is fully available.
    private var macroApplier: TrackMacroApplier!
    @ObservationIgnored
    private let audioPluginChoiceRescanner: () -> AudioPluginChoiceScanResult
    let sampleLibrary: AudioSampleLibrary
    var sampleLibraryRoot: URL { sampleLibrary.libraryRoot }
    /// Destination for completed audio-input captures. Nil (the default for
    /// engine-only constructions, e.g. unit tests) disables persistence; the
    /// production document session injects `RecordingLibrary.shared`.
    let recordingLibrary: RecordingLibrary?
    /// Recording WAV/sidecar writes happen here — never on the tick queue or
    /// main. Utility QoS: a late library write must not compete with audio.
    let recordingPersistenceQueue = DispatchQueue(
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
    var selectedOutput: Destination.Kind
    private(set) var masterBusPerformanceOverlay = MasterBusPerformanceOverlayState()
    var audioInputRuntimeRevision = 0
    /// Narrow UI publisher for note-repeat runtime state (engage/release —
    /// gesture rate, never tick rate). `noteRepeatRuntimeSnapshot(for:)`
    /// reads it so playhead-leaf views re-evaluate on engage/release without
    /// the page observing any tick-rate state (architecture verdict §2:
    /// high-frequency state goes through narrow dedicated publishers).
    var noteRepeatRuntimeUIRevision = 0

    var currentTrackMix = TrackMixSettings.default
    // Access widened from `private` for the carve-up extension files
    // (EngineControllerStatus.swift etc.) — same module, no semantic change.
    var currentDocumentModel: Project = .empty
    let tickState = TickStateBuffer(playbackSnapshot: SequencerSnapshotCompiler.compile(state: .empty))
    let trackRuntime = TrackRuntimeRegistry()
    let routerDispatch = RouterDispatchState()
    @ObservationIgnored
    var phraseNavigationState = PhraseNavigationState()
    @ObservationIgnored
    var activeNoteRepeatsByTrackID: [UUID: ActiveNoteRepeatRuntime] = [:]
    @ObservationIgnored
    var preparedNoteRepeatCapturesByStepIndex: [UInt64: [UUID: NoteRepeatCapturedStep]] = [:]
    @ObservationIgnored
    var currentNoteRepeatCapturesByTrackID: [UUID: NoteRepeatCapturedStep] = [:]
    @ObservationIgnored
    private var pendingStepOrderTogglePayload: PendingStepOrderTogglePayload?
    @ObservationIgnored
    var stepOrderToggleAppliedHandler: ((StepOrderPendingToggleRequest) -> Void)?
    /// Quantised perform toggles (perform/setup split slice 2): lock-protected
    /// scheduler shared by main (arm/cancel) and the tick queue (boundary
    /// commit). The @Observable mirrors below publish on main.
    @ObservationIgnored
    private let quantisedToggleScheduler = QuantisedToggleScheduler()
    /// Invoked on the tick path when armed changes commit at a bar boundary
    /// (same contract as `stepOrderToggleAppliedHandler`: the installed
    /// handler hops to main itself, fire-and-forget).
    @ObservationIgnored
    var quantisedToggleCommittedHandler: (([QuantisedToggleChange]) -> Void)?
    /// Main-published mirror of the armed (pending) quantised changes for UI.
    private(set) var quantisedPendingChanges: [QuantisedToggleChange] = []
    /// Main-published mirror of the tracks whose cued fill bar is playing.
    private(set) var quantisedFillCueActiveTrackIDs: Set<UUID> = []
    /// Main-only @Observable mirror for UI. The tick queue must read
    /// `chordContextByLaneEngine` (under stateLock) instead: a one-sided
    /// lock on the reader synchronizes nothing against the main-thread
    /// writer (data race R2).
    private(set) var chordContextByLane: [String: Chord] = [:]
    private(set) var audioPluginChoiceScanState: AudioPluginChoiceScanState = .idle
    @ObservationIgnored
    private var audioPluginChoiceFixtureInstruments: [AudioInstrumentChoice]?
    @ObservationIgnored
    private var audioPluginChoiceFixtureEffects: [AudioEffectChoice]?
    /// Engine-side copy, guarded by `stateLock` on both sides; written at
    /// dispatch time on the tick queue, read by `prepareTick`.
    @ObservationIgnored
    private var chordContextByLaneEngine: [String: Chord] = [:]

    private(set) var currentPhraseID: UUID?
    private(set) var queuedPhraseID: UUID?
    private(set) var basisPhraseID: UUID?
    private(set) var stepOrderPendingToggle: StepOrderPendingToggleRequest?

    func log(_ message: String) {
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
    func publishToMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            // realtime-allow-main-async: UI mirrors are published asynchronously after tick-state writes. Test: RealtimePathLintTests.
            DispatchQueue.main.async(execute: body)
        }
    }

    /// Test-only: when set, replaces the host-time conversion for scheduled
    /// audio events. The offline render harness drives `processTick` with a
    /// synthetic timeline and maps event times onto the manual-rendering
    /// sample clock (or returns nil for "play at the next rendered frame").
    /// Production never sets this.
    @ObservationIgnored
    var scheduledAudioTimeOverrideForTesting: ((TimeInterval) -> AVAudioTime?)?

    private func scheduledAudioTime(for scheduledHostTime: TimeInterval) -> AVAudioTime? {
        if let scheduledAudioTimeOverrideForTesting {
            return scheduledAudioTimeOverrideForTesting(scheduledHostTime)
        }
        return AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(0, scheduledHostTime)))
    }

    private func stepDurationSeconds(bpm: Double) -> TimeInterval {
        (60.0 / max(1, bpm)) * (4.0 / Double(max(1, stepsPerBar)))
    }

    func publishNoteActivity(uptime: TimeInterval, count: Int) {
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

    func firstValidPhraseID(in snapshot: PlaybackSnapshot) -> UUID? {
        if snapshot.phraseBuffer(for: snapshot.selectedPhraseID) != nil {
            return snapshot.selectedPhraseID
        }
        return snapshot.phraseOrder.first { snapshot.phraseBuffer(for: $0) != nil }
    }

    func validPhraseID(_ phraseID: UUID?, in snapshot: PlaybackSnapshot) -> UUID? {
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

    private func applyPhraseSceneState(phraseID: UUID?, snapshot: PlaybackSnapshot) {
        guard let phraseID else { return }
        var masterBus = currentDocumentModel.masterBus
        if let sceneState = snapshot.phraseBuffer(for: phraseID)?.sceneState {
            masterBus.setABSelection(MasterBusABSelection(
                sceneAID: sceneState.sceneAID,
                sceneBID: sceneState.sceneBID,
                crossfader: sceneState.crossfader
            ))
        }
        applyMasterBusIfChanged(masterBus)
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
        applyPhraseSceneState(phraseID: updatedState?.currentPhraseID ?? fallbackPhraseID, snapshot: snapshot)
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

    func playbackPhraseForPrepare(
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
        applyPhraseSceneState(phraseID: playbackPhraseID, snapshot: snapshot)
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
        sampleAssetCache: SampleAssetCache = SampleAssetCache(),
        sampleLibrary: AudioSampleLibrary = .shared,
        masterBusHost: MasterBusHosting = MasterBusHost(),
        publishesAudioInputCapture: Bool = false,
        recordingLibrary: RecordingLibrary? = nil,
        audioPluginChoiceRescanner: @escaping () -> AudioPluginChoiceScanResult = {
            let instruments = AudioInstrumentChoiceCache.shared.rescanChoices()
            let effects = AudioEffectChoiceCache.shared.rescanChoices()
            return AudioPluginChoiceScanResult(
                instrumentCount: instruments.count,
                effectCount: effects.count
            )
        }
    ) {
        self.mainAudioGraph = mainAudioGraph
        self.sampleEngine = sampleEngine ?? SamplePlaybackEngine(audioGraph: mainAudioGraph)
        self.sampleAssetCache = sampleAssetCache
        self.sampleLibrary = sampleLibrary
        self.recordingLibrary = recordingLibrary
        self.masterBusHost = masterBusHost
        self.midiClient = client
        self.endpoint = endpoint
        self.sharedAudioOutput = audioOutput
        self.audioOutputFactory = audioOutputFactory
        self.audioPluginChoiceRescanner = audioPluginChoiceRescanner
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

    /// Test-only: identical to `start()` minus starting the wall-clock
    /// TickClock. The caller drives `processTick(tickIndex:now:)` manually
    /// with a synthetic timeline (offline render harness). `stop()` tears
    /// down as usual — `clock.stop()` is a no-op when the clock never ran.
    func startTransportWithoutClockForTesting(now: TimeInterval) {
        guard !isRunning, executor != nil else {
            return
        }
        DevActivity.trace(DevActivity.engine, "EngineController.startTransportWithoutClockForTesting")

        initializePhraseNavigationForPlaybackStart(
            snapshot: tickState.currentPlaybackSnapshot(),
            cycleStartTick: 0
        )
        let hosts = withStateLock { Array(trackRuntime.audioOutputsByTrackID.values) }
        hosts.forEach { $0.startIfNeeded() }
        try? sampleEngine.start()

        prepareTick(upcomingStep: 0, now: now)
        promotePreparedNoteRepeatCapture(for: 0)
        tickState.markPreparedTick(0)
        isRunning = true
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
        // Stopped audio means no more meter taps fire; snap every mixer
        // meter (master + channels + buses) to zero so they don't freeze on
        // their last value.
        mainAudioGraph.resetMetersToSilence()
        tickState.resetRuntimeState()
        clearNoteRepeatCaptureCaches()
        clearAllNoteRepeats(now: now)
        clearQueuedPhraseOnStop(snapshot: tickState.currentPlaybackSnapshot())
        // Armed quantised changes have no boundary to wait for once the
        // transport stops; overrides/cues lose their timeline with it.
        resetQuantisedToggles()
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
        applyPlaybackSnapshotCallCountAtomic.increment()
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
    /// Atomic backing: PlaybackSnapshotConcurrencyTests applies snapshots
    /// from concurrent workers by design, and the plain `+= 1` was an
    /// unsynchronized read-modify-write (2026-06-12 TSan lane finding 4).
    @ObservationIgnored
    private let applyPlaybackSnapshotCallCountAtomic = AtomicInt64(0)

    var applyPlaybackSnapshotCallCount: Int {
        Int(applyPlaybackSnapshotCallCountAtomic.load())
    }

    /// Counter for test observation of scoped send-bus authored updates.
    var sendBusApplyCallCount: Int = 0

    /// Last fixed send-bus states seen through scoped authored updates.
    var sendBusStates: [SendBusID: SendBusState] = [
        .sendA: .sendA,
        .sendB: .sendB,
    ]

    /// Test hook: exposes whether the internal event queue is empty.
    /// Use to assert that prepared events were cleared after a snapshot swap.
    var eventQueueIsEmpty: Bool { eventQueue.isEmpty }

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

    // MARK: - Quantised perform toggles

    /// Arm a quantised toggle for the next bar boundary, or cancel it when
    /// the same (kind, track) is already armed. Rejected while the transport
    /// is stopped — there is no boundary to wait for, so callers apply the
    /// change immediately instead (the step-order fallback shape).
    @discardableResult
    func armQuantisedToggle(_ change: QuantisedToggleChange) -> QuantisedToggleArmResult {
        guard isRunning else {
            return .rejected
        }
        let result = quantisedToggleScheduler.armOrCancel(change)
        publishQuantisedPendingChanges()
        return result
    }

    /// Cancels every armed (not yet committed) change. Committed state —
    /// live mute overrides and the playing cue bar — is unaffected.
    func cancelAllQuantisedToggles() {
        quantisedToggleScheduler.cancelAllArmed()
        publishQuantisedPendingChanges()
    }

    /// Main confirms the committed mute changes are encoded in an installed
    /// playback snapshot (the session staged the document record), retiring
    /// the live tick-path overrides.
    func confirmQuantisedMuteApplied(trackIDs: [UUID]) {
        quantisedToggleScheduler.confirmMuteApplied(trackIDs: trackIDs)
    }

    /// Main confirms committed fill-flag changes are encoded in an installed
    /// playback snapshot (the session staged the document record), retiring
    /// the live tick-path overrides.
    func confirmQuantisedFillFlagApplied(trackIDs: [UUID]) {
        quantisedToggleScheduler.confirmFillFlagApplied(trackIDs: trackIDs)
    }

    /// Main confirms committed pattern changes are encoded in an installed
    /// playback snapshot (the session staged the document record), retiring
    /// the live tick-path slot overrides.
    func confirmQuantisedPatternApplied(trackIDs: [UUID]) {
        quantisedToggleScheduler.confirmPatternApplied(trackIDs: trackIDs)
    }

    /// Full reset for document replacement: armed changes, live overrides,
    /// and cue bars all refer to state that no longer exists.
    func resetQuantisedToggles() {
        quantisedToggleScheduler.resetRuntime()
        publishQuantisedPendingChanges()
        publishQuantisedFillCueActiveTrackIDs([])
    }

    /// Pending mute target for UI (armed, not yet committed), or nil.
    func quantisedPendingMuteTarget(for trackID: UUID) -> Bool? {
        for change in quantisedPendingChanges {
            switch change {
            case let .mute(changeTrackID, muted, _) where changeTrackID == trackID:
                return muted
            case let .lengthLimitedMute(changeTrackID, muted, _, _, _) where changeTrackID == trackID:
                return muted
            default:
                continue
            }
        }
        return nil
    }

    /// True when a fill cue is armed (pending) for the track.
    func hasQuantisedPendingFillCue(for trackID: UUID) -> Bool {
        quantisedPendingChanges.contains { change in
            if case let .fillCue(changeTrackID) = change {
                return changeTrackID == trackID
            }
            return false
        }
    }

    var quantisedMuteOverridesForTesting: [UUID: Bool] {
        quantisedToggleScheduler.activeMuteOverrides()
    }

    var quantisedFillFlagOverridesForTesting: [UUID: Bool] {
        quantisedToggleScheduler.activeFillFlagOverrides()
    }

    var quantisedPatternSlotOverridesForTesting: [UUID: Int] {
        quantisedToggleScheduler.activePatternSlotOverrides()
    }

    func quantisedFillCueIsActiveForTesting(trackID: UUID, atTick tick: UInt64) -> Bool {
        quantisedToggleScheduler.activeFillCueTrackIDs(atTick: tick).contains(trackID)
    }

    private func publishQuantisedPendingChanges() {
        let changes = quantisedToggleScheduler.armedChanges()
        publishToMain { [weak self] in
            guard let self, self.quantisedPendingChanges != changes else { return }
            self.quantisedPendingChanges = changes
        }
    }

    private func publishQuantisedFillCueActiveTrackIDs(_ trackIDs: Set<UUID>) {
        publishToMain { [weak self] in
            guard let self, self.quantisedFillCueActiveTrackIDs != trackIDs else { return }
            self.quantisedFillCueActiveTrackIDs = trackIDs
        }
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
        applyPhraseSceneState(phraseID: phraseID, snapshot: snapshot)
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

    func auditionMasterABSelection(_ selection: MasterBusABSelection) {
        var masterBus = currentDocumentModel.masterBus
        masterBus.setABSelection(selection)
        applyMasterBusIfChanged(masterBus)
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
        if let audioPluginChoiceFixtureInstruments {
            return audioPluginChoiceFixtureInstruments
        }
        if audioPluginChoiceScanState.isScanning,
           let choices = AudioInstrumentChoiceCache.shared.currentChoicesIfAvailable
        {
            return choices
        }
        // `AudioInstrumentHost` snapshots its instrument list at init from the cache, so it
        // cannot reflect a runtime rescan. Read the live cache directly unless a non-host
        // sink (e.g. a test/mock) is supplying its own list.
        if let sharedAudioOutput, !(sharedAudioOutput is AudioInstrumentHost) {
            return sharedAudioOutput.availableInstruments
        }
        return AudioInstrumentChoice.defaultChoices
    }

    var availableAudioEffects: [AudioEffectChoice] {
        if let audioPluginChoiceFixtureEffects {
            return audioPluginChoiceFixtureEffects
        }
        if audioPluginChoiceScanState.isScanning,
           let choices = AudioEffectChoiceCache.shared.currentChoicesIfAvailable
        {
            return choices
        }
        return AudioEffectChoice.defaultChoices
    }

    func rescanAudioPluginChoices() {
        guard !audioPluginChoiceScanState.isScanning else { return }
        audioPluginChoiceScanState = .scanning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.audioPluginChoiceRescanner()
            self.publishToMain {
                self.audioPluginChoiceScanState = .ready(
                    instrumentCount: result.instrumentCount,
                    effectCount: result.effectCount
                )
            }
        }
    }

    @MainActor
    func setAudioPluginChoiceFixtureForVisualAutomation(
        instruments: [AudioInstrumentChoice],
        effects: [AudioEffectChoice],
        scanState: AudioPluginChoiceScanState
    ) {
        guard VisualScenarioCommandRunner.isConfigured else { return }
        audioPluginChoiceFixtureInstruments = instruments
        audioPluginChoiceFixtureEffects = effects
        audioPluginChoiceScanState = scanState
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

    func setAuditionOverride(_ state: PseudoClipState?, for trackID: UUID) {
        tickState.setAuditionOverride(state, for: trackID)
        clearNoteRepeatCaptureCaches()
        eventQueue.clear()
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
            // After syncAudioOutputs / buildPipeline: every track's output
            // source node is registered, so the graph can resolve each track
            // and splice its FX insert chain.
            syncTrackInserts(for: documentModel)
        } catch {
            NSLog("EngineController apply failed: \(error)")
        }
    }

    func effectiveDestination(for trackID: UUID) -> (destination: Destination, pitchOffset: Int) {
        Self.effectiveDestination(for: trackID, in: currentDocumentModel)
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        // The whole tick scope runs under the DEBUG tick-path marker: any
        // synchronous main hop reached from here trips
        // TickPathMainSyncGuard (architecture verdict §1).
        let started = SequencerTimingProbe.isEnabled ? ProcessInfo.processInfo.systemUptime : 0
        let eventCount = TickPathMainSyncGuard.withTickPathMarker {
            processTickMarked(tickIndex: tickIndex, now: now)
        }
        if SequencerTimingProbe.isEnabled {
            SequencerTimingProbe.processTick(
                tickIndex: tickIndex,
                duration: ProcessInfo.processInfo.systemUptime - started,
                eventCount: eventCount
            )
        }
    }

    private func processTickMarked(tickIndex: UInt64, now: TimeInterval) -> Int {
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
        let eventCount = dispatchTick()
        let nextStepBPM = withStateLock { executor?.currentBPM } ?? clock.bpm
        prepareTick(upcomingStep: tickIndex &+ 1, now: now, scheduledHostTime: now + stepDurationSeconds(bpm: nextStepBPM))
        tickState.markPreparedTick(tickIndex &+ 1)
        return eventCount
    }

    private func prepareTick(
        upcomingStep: UInt64,
        now: TimeInterval,
        scheduledHostTime explicitScheduledHostTime: TimeInterval? = nil
    ) {
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

        // Quantised perform toggles: armed changes group-commit on the tick
        // that crosses the bar boundary, BEFORE this tick's notes/mutes are
        // resolved — the first step of the new bar already plays the new
        // state. Handler dispatch mirrors stepOrderToggleAppliedHandler
        // (the installed handler hops to main itself, fire-and-forget).
        let committedQuantisedChanges = quantisedToggleScheduler.commitAtBarBoundary(
            upcomingTick: upcomingStep,
            ticksPerBar: stepsPerBar
        )
        if !committedQuantisedChanges.isEmpty {
            publishQuantisedPendingChanges()
            quantisedToggleCommittedHandler?(committedQuantisedChanges)
        }
        let quantisedMuteOverrides = quantisedToggleScheduler.activeMuteOverrides()
        let quantisedFillFlagOverrides = quantisedToggleScheduler.activeFillFlagOverrides()
        let quantisedPatternSlotOverrides = quantisedToggleScheduler.activePatternSlotOverrides()
        let quantisedFillCueTrackIDs = quantisedToggleScheduler.activeFillCueTrackIDs(atTick: upcomingStep)
        publishQuantisedFillCueActiveTrackIDs(quantisedFillCueTrackIDs)

        var currentLayerSnapshot = playbackSnapshot.layerSnapshot(
            phraseID: activePhraseID,
            stepInPhrase: stepInPhrase
        )
        if !quantisedMuteOverrides.isEmpty {
            currentLayerSnapshot = currentLayerSnapshot.applyingMuteOverrides(quantisedMuteOverrides)
        }

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
                    quantisedFillFlagOverrides: quantisedFillFlagOverrides,
                    quantisedPatternSlotOverrides: quantisedPatternSlotOverrides,
                    quantisedFillCueTrackIDs: quantisedFillCueTrackIDs,
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
        let eventScheduledHostTime = explicitScheduledHostTime ?? now
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
                    scheduledHostTime: eventScheduledHostTime,
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
            switch playbackSnapshot.resolvedDestination(for: track.id).destination {
            case let .sample(sampleID, settings):
                for _ in events {
                    eventQueue.enqueue(ScheduledEvent(
                        scheduledHostTime: eventScheduledHostTime,
                        payload: .sampleTrigger(
                            trackID: track.id,
                            sampleID: sampleID,
                            settings: settings,
                            scheduledHostTime: eventScheduledHostTime
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
                    stepsPerBar: stepsPerBar,
                    bpm: executor.currentBPM,
                    scheduledHostTime: eventScheduledHostTime,
                    eventQueue: eventQueue
                )

            default:
                continue
            }
        }

        routerDispatch.beginTick(now: eventScheduledHostTime)
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

    private func dispatchTick() -> Int {
        let events = eventQueue.drain()
        let (audioOutputs, outputKeys) = withStateLock { (trackRuntime.audioOutputsByTrackID, trackRuntime.audioOutputKeysByTrackID) }

        for event in events {
            let dispatchNow = SequencerTimingProbe.isEnabled ? ProcessInfo.processInfo.systemUptime : 0
            switch event.payload {
            case let .trackAU(trackID, destination, notes, bpm, stepsPerBar):
                SequencerTimingProbe.eventDispatch(
                    kind: "track-au",
                    trackID: trackID,
                    scheduled: event.scheduledHostTime,
                    actual: dispatchNow
                )
                guard let host = audioOutputs[trackID] else {
                    continue
                }
                applyDestinationIfNeeded(destination, trackID: trackID, host: host, outputKeys: outputKeys)
                // TrackPlaybackSink is immediate-only today. The queued host time is
                // retained for ownership/cancellation evidence; sink-level AU timing
                // needs a future contract extension before it can be claimed.
                host.play(noteEvents: notes, bpm: bpm, stepsPerBar: stepsPerBar)

            case let .routedAU(trackID, destination, notes, bpm, stepsPerBar):
                SequencerTimingProbe.eventDispatch(
                    kind: "routed-au",
                    trackID: trackID,
                    scheduled: event.scheduledHostTime,
                    actual: dispatchNow
                )
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
                SequencerTimingProbe.eventDispatch(
                    kind: "sample",
                    trackID: trackID,
                    scheduled: event.scheduledHostTime,
                    actual: dispatchNow
                )
                guard let sampleAsset = sampleAssetCache.asset(sampleID: sampleID, trackID: trackID) else {
                    SampleTriggerTrace.drop(trackID: trackID, sampleID: sampleID, reason: "missing-prepared-asset")
                    continue
                }
                SampleTriggerTrace.dispatch(
                    trackID: trackID,
                    sampleID: sampleID,
                    sampleURL: sampleAsset.url,
                    scheduledHostTime: event.scheduledHostTime,
                    gain: settings.gain
                )
                _ = sampleEngine.play(
                    sampleAsset: sampleAsset,
                    settings: settings,
                    trackID: trackID,
                    at: scheduledAudioTime(for: event.scheduledHostTime)
                )

            case let .sliceTrigger(trackID, sampleID, startFrame, endFrame, settings, reverse, stepParameters, _):
                SequencerTimingProbe.eventDispatch(
                    kind: "slice",
                    trackID: trackID,
                    scheduled: event.scheduledHostTime,
                    actual: dispatchNow
                )
                guard let sampleAsset = sampleAssetCache.asset(sampleID: sampleID, trackID: trackID) else {
                    SampleTriggerTrace.drop(trackID: trackID, sampleID: sampleID, reason: "missing-prepared-asset")
                    continue
                }
                _ = sampleEngine.playSlice(
                    sampleAsset: sampleAsset,
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
        return events.count
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

    func flushRoutedEvents(
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
                stepsPerBar: stepsPerBar,
                bpm: bpm,
                scheduledHostTime: routerDispatch.dispatchNow,
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

    func resolveEndpoint(named port: MIDIEndpointName) -> MIDIEndpoint? {
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

    /// Test observation of the async recording persistence (success or
    /// failure). Invoked on the main thread after the runtime tag lands.
    var recordingPersistenceObserverForTesting: ((Result<RecordingAsset, Error>) -> Void)?

    // `internal` (not private) so `@testable import` can exercise tick resolution from tests.
    static func resolvedStepNotes<R: RandomNumberGenerator>(
        for trackID: UUID,
        in playbackSnapshot: PlaybackSnapshot,
        phraseID: UUID,
        stepIndex: Int,
        chordContext: Chord?,
        trackFillPreview: TrackFillPreviewPlaybackSnapshot = .inactive,
        quantisedFillFlagOverrides: [UUID: Bool] = [:],
        quantisedPatternSlotOverrides: [UUID: Int] = [:],
        quantisedFillCueTrackIDs: Set<UUID> = [],
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

        let effectiveSlotIndex = quantisedPatternSlotOverrides[trackID] ?? resolved.slotIndex

        switch program.slotProgram(at: effectiveSlotIndex) {
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

            let effectiveFillEnabled = quantisedFillFlagOverrides[trackID]
                ?? (resolved.fillEnabled
                    || trackFillPreview.isActive(for: trackID)
                    || quantisedFillCueTrackIDs.contains(trackID))
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

    // Access widened from `private` for the carve-up extension files.
    func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        #if DEBUG
        TickPathMainSyncGuard.stateLockDepthForCurrentThread += 1
        defer { TickPathMainSyncGuard.stateLockDepthForCurrentThread -= 1 }
        #endif
        return body()
    }

    // MARK: - Debug lock-order assertions
    //
    // CONTRACT: no synchronous main-thread hop (performOnMain* in the audio
    // graph) may be reachable while stateLock is held — the mirror image of
    // the documented graphLock rule. Violations are the D1 deadlock class.
    //
    // The per-thread hold depth lives on TickPathMainSyncGuard so the shared
    // hop helpers in Sources/Audio enforce the same contract at the actual
    // sync-dispatch sites (wave 2d generalization of the wave-1 assertion).

    #if DEBUG
    /// Test hook: receives the context string instead of trapping, so tests
    /// can pin the "no main hop under stateLock" contract.
    var stateLockHoldViolationHandlerForTesting: ((String) -> Void)?

    var isHoldingStateLockForTesting: Bool {
        TickPathMainSyncGuard.stateLockDepthForCurrentThread > 0
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
        guard TickPathMainSyncGuard.stateLockDepthForCurrentThread > 0 else { return }
        if let handler = stateLockHoldViolationHandlerForTesting {
            handler(context)
        } else {
            assertionFailure("\(context) must not run while holding stateLock (deadlock class D1)")
        }
        #endif
    }

    func invalidatePreparedPlaybackOutput(resetGeneratedStates: Bool) {
        tickState.invalidatePreparedTick(resetGeneratedStates: resetGeneratedStates)
        clearNoteRepeatCaptureCaches()
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
