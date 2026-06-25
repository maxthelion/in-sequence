import AVFoundation
import Foundation
import Observation

final class MainAudioGraph {
    enum AudioInputMonitorSource: Equatable {
        case input
        case loop
        case silent
    }

    struct AudioInputRoutingRequest: Equatable {
        let trackID: UUID
        let source: AudioInputMonitorSource
        let selectedChannel: AudioInputChannel
        let outputBusID: UUID?
        let mix: TrackMixSettings
    }

    struct AudioInputRoutingReadout {
        let trackID: UUID
        let selectedChannel: AudioInputChannel
        let requestedSource: AudioInputMonitorSource
        let connectedSource: AudioInputMonitorSource
        let outputMixer: AVAudioMixerNode
        let loopPlayer: AVAudioPlayerNode
        let dryDestination: AVAudioNode?
        let outputVolume: Float
        let pan: Float
        let scheduledLoopFrameCount: AVAudioFrameCount?
        let scheduledLoopChannelCount: AVAudioChannelCount?
        let scheduledLoopSampleRate: Double?
        let loopPlaybackScheduleCount: Int
    }

    struct MasterChain {
        var nodes: [AVAudioNode]
        var gain: Double
    }

    struct TrackSendLevels: Equatable {
        var sendA: Double
        var sendB: Double

        static let zero = TrackSendLevels(sendA: 0, sendB: 0)

        var clampedSendA: Float { Float(sendA.clamped(to: 0...1)) }
        var clampedSendB: Float { Float(sendB.clamped(to: 0...1)) }
    }

    struct MasterBranchReadout {
        var nodes: [AVAudioNode]
        var gain: Float
    }

    struct TrackSendReadout {
        let dryDestination: AVAudioNode
        let sendFanoutNode: AVAudioMixerNode?
        let sendAGainNode: AVAudioMixerNode?
        let sendBGainNode: AVAudioMixerNode?
        let sendAGain: Float
        let sendBGain: Float
        let sendFanoutDestinations: [AVAudioNode]
        let sendADestination: AVAudioNode?
        let sendBDestination: AVAudioNode?
    }

    let engine: AVAudioEngine
    let preMasterMixer: AVAudioMixerNode
    let masterMeterPublisher: MasterMeterPublisher
    /// Per-strip meters (tracks, mixer buses, send returns) — roadmap 29.
    let channelMeterBank: ChannelMeterBank
    private let audioDeviceOwner: AudioDeviceOwning
    private(set) var masterBranchesForTesting: [MasterBranchReadout] = []
    private(set) var postBlendMasterInsertNodesForTesting: [AVAudioNode] = []
    private(set) var masterOutputGainForTesting: Float = 1
    private(set) var masterMeterTapPointForTesting: MasterMeterTapPoint?
    private(set) var masterMeterTapInstallCountForTesting = 0
    private(set) var masterMeterTapRemoveCountForTesting = 0
    private(set) var audioInputFullRoutingSyncCountForTesting = 0
    private(set) var audioInputScopedRoutingUpdateCountForTesting = 0
    /// Counts installSendBuses passes that actually changed topology (engine
    /// stop/reinstall/start). Value-only send-FX changes must not bump this.
    private(set) var sendBusTopologyInstallCountForTesting = 0
    /// Counts live track-output rewires. Zero-send mix value changes must
    /// not bump this (mixer-latency cause 2).
    private(set) var reconnectTrackOutputCountForTesting = 0
    var audioInputCaptureHandlerInstalledForTesting: Bool {
        lockGraphLock()
        defer { unlockGraphLock() }
        return audioInputCaptureHandler != nil
    }

    private let graphLock = NSLock()

    // MARK: - graphLock acquisition tracking (DEBUG lock-discipline net)
    //
    // graphLock is NON-RECURSIVE and (by documented convention) only ever
    // taken inside main-thread closures. Two contract breaks both end in a
    // hard wedge, so they are asserted at the acquisition/hop sites:
    // - re-locking graphLock on a thread that already holds it (sampled
    //   live 2026-06-11: send-bus "+ Add FX" — an AU instantiation callback
    //   re-entered installSendBus inline under the held lock);
    // - synchronously dispatching to main while holding graphLock from off
    //   main (the comment at every lock site: "holding graphLock across
    //   DispatchQueue.main.sync is a lock-order deadlock waiting to happen").

    #if DEBUG
    /// Per-thread, per-instance graphLock hold depth (NSLock has no owner
    /// readout). Instance-scoped key: multiple MainAudioGraph instances
    /// coexist in the test process.
    private let graphLockDepthKey = "ai.sequencer.SequencerAI.MainAudioGraph.graphLockDepth.\(UUID().uuidString)"

    private var graphLockDepthForCurrentThread: Int {
        get { (Thread.current.threadDictionary[graphLockDepthKey] as? Int) ?? 0 }
        set { Thread.current.threadDictionary[graphLockDepthKey] = newValue }
    }

    /// Test-only positive control: proves the re-entry detector fires, so
    /// "no violation" assertions in churn tests cannot pass vacuously.
    func simulateGraphLockReentryForTesting() {
        lockGraphLock()
        defer { unlockGraphLock() }
        debugAssertGraphLockNotHeldByCurrentThread(
            "simulated graphLock re-entry"
        )
    }
    #endif

    /// Asserts (DEBUG) that the calling thread does not already hold
    /// `graphLock` — re-locking would self-deadlock.
    private func debugAssertGraphLockNotHeldByCurrentThread(_ context: @autoclosure () -> String) {
        #if DEBUG
        guard graphLockDepthForCurrentThread > 0 else { return }
        TickPathMainSyncGuard.reportImminentDeadlock(
            "\(context()): graphLock is non-recursive and already held by this thread " +
            "(self-deadlock, send-bus Add-FX class)"
        )
        #endif
    }

    /// Asserts (DEBUG) that the calling thread does not hold `graphLock`
    /// before a synchronous hop to main. Called by the performOnMain*
    /// helpers (wave 2d: the prose rule at every lock site, mechanized).
    private func debugAssertNotHoldingGraphLockForMainHop(_ context: @autoclosure () -> String) {
        #if DEBUG
        guard graphLockDepthForCurrentThread > 0 else { return }
        TickPathMainSyncGuard.reportImminentDeadlock(
            "\(context()) must not sync-dispatch to main while holding graphLock " +
            "(lock-order deadlock)"
        )
        #endif
    }

    /// All graphLock acquisitions go through here (DEBUG re-entry assertion
    /// + hold-depth tracking; plain `lock()` in release).
    private func lockGraphLock() {
        debugAssertGraphLockNotHeldByCurrentThread("MainAudioGraph.lockGraphLock")
        graphLock.lock()
        #if DEBUG
        graphLockDepthForCurrentThread += 1
        #endif
    }

    private func unlockGraphLock() {
        #if DEBUG
        graphLockDepthForCurrentThread -= 1
        #endif
        graphLock.unlock()
    }
    private var audioInputCaptureHandler: ((UUID, AVAudioPCMBuffer) -> Void)?
    private let postBlendMixer = AVAudioMixerNode()
    private let finalOutputMixer = AVAudioMixerNode()
    private var managedMasterNodes: [AVAudioNode] = []
    private var managedMasterGainMixers: [AVAudioMixerNode] = []
    private var mixerBusHosts: [UUID: MixerBusHost] = [:]
    private var sendBusHosts: [SendBusID: SendBusHost] = [:]
    /// Per-track FX insert chains, keyed by trackID. Spliced between a track's
    /// output source node and its dry/sends destinations in
    /// `reconnectTrackOutputOnMain`. The source node is resolved via
    /// `trackMeterSources` (every track subsystem already registers its
    /// terminal node there at connect time).
    private var trackInsertChainHosts: [UUID: TrackInsertChainHost] = [:]
    /// Latest authored chain per track, retained so an AU-load re-entry or a
    /// source-node (re)registration can rebuild without the document round-trip.
    private var trackInsertChainsByTrackID: [UUID: [TrackFXInsert]] = [:]
    /// Counts track insert-chain topology rebuilds (engine stop/rebuild/start).
    /// Value-only insert changes (e.g. a bypass toggle on an installed chain)
    /// must not bump this.
    private(set) var trackInsertChainTopologyInstallCountForTesting = 0
    /// Injectable factory for AU-effect inserts so tests can drive the AU path
    /// without touching the real component registry.
    var trackInsertAUFactoryForTesting: AUAudioUnitFactory?
    private var trackOutputDestinationsForTesting: [ObjectIdentifier: AVAudioNode] = [:]
    private var trackOutputRoutings: [ObjectIdentifier: TrackOutputRouting] = [:]
    private var trackSendNodes: [ObjectIdentifier: TrackSendNodes] = [:]
    private var trackSendDestinationsForTesting: [ObjectIdentifier: TrackSendDestinations] = [:]
    private var audioInputRoutingHosts: [UUID: AudioInputRoutingHost] = [:]
    /// Tick-path-readable snapshot of each audio-input host's capture format
    /// (the input format of its output mixer). The format only changes when
    /// the graph reconfigures — host install/teardown/source rewires, device
    /// applies, engine-resetting topology installs — all of which happen on
    /// main, so main publishes via `publishAudioInputCaptureFormatsOnMain()`
    /// at those sites and the tick path reads the snapshot WITHOUT a
    /// synchronous main hop (this was the last waived TickPathMainSyncGuard
    /// hop; the guard now traps). Leaf lock: held only for the dictionary
    /// copy, never while taking graphLock or dispatching.
    private let audioInputCaptureFormatSnapshotLock = NSLock()
    private var audioInputCaptureFormatSnapshot: [UUID: AVAudioFormat] = [:]
    private var isStarted = false
    private var isMasterMeterTapInstalled = false
    private let masterMeterTapGeneration = AtomicInt32(0)
    private var areChannelMeterTapsInstalled = false
    private var channelMeterTappedNodes: [ObjectIdentifier: AVAudioNode] = [:]
    private var trackMeterSources: [UUID: AVAudioNode] = [:]
    private let channelMeterTapGeneration = AtomicInt32(0)
    private(set) var channelMeterTapInstallCountForTesting = 0
    private(set) var channelMeterTapRemoveCountForTesting = 0
    private let masterRenderLock = NSLock()
    private var masterRenderFile: AVAudioFile?
    private var masterRenderURL: URL?

    private struct TrackOutputRouting {
        let source: AVAudioNode
        var busID: UUID?
        var sendLevels: TrackSendLevels
    }

    private struct TrackSendNodes {
        let fanout: AVAudioMixerNode
        let sendA: AVAudioMixerNode
        let sendB: AVAudioMixerNode
    }

    private struct TrackSendDestinations {
        var fanout: [AVAudioNode]
        var sendA: AVAudioNode?
        var sendB: AVAudioNode?
    }

    private final class AudioInputRoutingHost {
        let trackID: UUID
        let outputMixer = AVAudioMixerNode()
        let loopPlayer = AVAudioPlayerNode()
        var requestedSource: AudioInputMonitorSource = .silent
        var connectedSource: AudioInputMonitorSource = .silent
        var selectedChannel: AudioInputChannel = .stereo(firstChannel: 0)
        var outputBusID: UUID?
        var isCaptureTapInstalled = false
        var scheduledLoopFrameCount: AVAudioFrameCount?
        var scheduledLoopChannelCount: AVAudioChannelCount?
        var scheduledLoopSampleRate: Double?
        var loopPlaybackScheduleCount = 0
        let captureTapGeneration = AtomicInt32(0)

        init(trackID: UUID) {
            self.trackID = trackID
        }
    }

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        masterMeterPublisher: MasterMeterPublisher = MasterMeterPublisher(),
        channelMeterBank: ChannelMeterBank = ChannelMeterBank(),
        audioDeviceOwner: AudioDeviceOwning = CoreAudioHALDeviceOwner()
    ) {
        self.engine = engine
        self.masterMeterPublisher = masterMeterPublisher
        self.channelMeterBank = channelMeterBank
        self.audioDeviceOwner = audioDeviceOwner
        self.preMasterMixer = AVAudioMixerNode()

        // One meter pump for the whole app: the master publisher rides the
        // channel bank's single main-queue timer (F6).
        channelMeterBank.registerAuxiliaryPublisher(masterMeterPublisher)

        performOnMain {
            // Visual-automation/capture: render offline so the engine never
            // connects to the CoreAudio HAL. This MUST happen while the engine
            // is stopped and BEFORE any node is attached/connected and BEFORE
            // the first `mainMixerNode` access below — `mainMixerNode`/
            // `outputNode` instantiate the HAL IO unit on access, which raises
            // the macOS mic TCC prompt and hangs the unattended capture
            // harness. Enabling manual rendering here keeps the IO unit (and
            // thus the prompt) from ever being created. Gated behind the
            // automation flag, so normal launches are unaffected.
            // Self-activating: the capture harness exports
            // SEQUENCER_AI_VISUAL_COMMAND_FILE to the app, so detect automation
            // directly here (no AppDelegate wiring needed — keeps this fix
            // self-contained in the audio layer). The static flag remains for
            // tests / explicit opt-in.
            let inVisualAutomation = Self.useManualRenderingForAutomation
                || ProcessInfo.processInfo.environment["SEQUENCER_AI_VISUAL_COMMAND_FILE"] != nil
            // Headless real-HAL gate (automation-only): the offline-render force
            // above exists solely to avoid the mic-TCC prompt that the HAL IO
            // unit raises. For SAMPLE-ONLY / output-only fixtures there is no
            // audio INPUT, so the mic prompt never applies and the real HAL can
            // run headless. The deadlock class we hunt only manifests on the
            // live HAL (engine.connect synchronizes with the render thread), so
            // the self-test rig sets SEQUENCER_AI_HEADLESS_REAL_HAL=1 to SKIP
            // the offline force and drive the command channel on the real
            // device. Absent the flag, behaviour is unchanged (offline forced).
            let headlessRealHAL = ProcessInfo.processInfo
                .environment["SEQUENCER_AI_HEADLESS_REAL_HAL"] == "1"
            if inVisualAutomation, headlessRealHAL {
                NSLog("[MainAudioGraph] SEQUENCER_AI_HEADLESS_REAL_HAL=1 — offline-render force SKIPPED; running on real HAL device")
                DevActivity.trace(DevActivity.harness, "MainAudioGraph headless real-HAL: offline force skipped")
            }
            if inVisualAutomation, !headlessRealHAL {
                guard let manualFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
                    NSLog("[MainAudioGraph] manual-rendering enable SKIPPED: could not build 44.1k/2ch format")
                    return
                }
                do {
                    try self.engine.enableManualRenderingMode(
                        .offline,
                        format: manualFormat,
                        maximumFrameCount: 4096
                    )
                    NSLog("[MainAudioGraph] manual-rendering (offline) ENABLED for automation — HAL IO unit suppressed")
                    DevActivity.trace(DevActivity.harness, "MainAudioGraph manual-rendering enabled for automation")
                } catch {
                    NSLog("[MainAudioGraph] manual-rendering enable FAILED: %@", String(describing: error))
                }
            }

            self.engine.attach(self.preMasterMixer)
            self.engine.attach(self.postBlendMixer)
            self.engine.attach(self.finalOutputMixer)
            self.engine.connect(self.preMasterMixer, to: self.postBlendMixer, format: nil)
            self.engine.connect(self.postBlendMixer, to: self.finalOutputMixer, format: nil)
            self.engine.connect(self.finalOutputMixer, to: self.engine.mainMixerNode, format: nil)
            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()
        }
    }

    deinit {
        channelMeterBank.stopPublishing()
        performOnMain {
            self.removeMasterMeterTapIfNeeded()
        }
    }

    /// Snaps every meter (master + all channel strips) to silence. Called
    /// when the transport stops so meters drop to zero instead of freezing
    /// on their last value. Touches only the meter publishers (no graph
    /// nodes, no graphLock), so it is safe on the main/engine thread.
    func resetMetersToSilence() {
        // The master publisher rides the bank as an auxiliary, so this one
        // call zeros it alongside the channel strips.
        channelMeterBank.resetAllToSilence()
    }

    func attach(_ node: AVAudioNode) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.attach")
        performOnMain {
            guard node.engine == nil else { return }
            self.engine.attach(node)
        }
    }

    func detach(_ node: AVAudioNode) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.detach")
        performOnMain {
            guard node.engine === self.engine else { return }
            // A node leaving the graph takes its meter registration with it.
            self.removeChannelMeterTapIfInstalled(on: node)
            self.trackMeterSources = self.trackMeterSources.filter { $0.value !== node }
            self.engine.disconnectNodeInput(node)
            self.engine.disconnectNodeOutput(node)
            self.engine.detach(node)
        }
    }

    func connect(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat? = nil) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.connect")
        performOnMain {
            self.engine.connect(
                source,
                to: destination,
                fromBus: 0,
                toBus: self.inputBus(for: destination),
                format: format
            )
        }
    }

    func disconnectOutput(_ node: AVAudioNode) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.disconnectOutput")
        performOnMain {
            self.removeTrackSendNodes(for: node)
            self.engine.disconnectNodeOutput(node)
        }
    }

    /// Disconnect a node's inputs without the track-output send-node teardown
    /// side effect of `disconnectOutput`. Used by `TrackInsertChainHost` to
    /// detach an insert from its upstream neighbour during a chain rebuild.
    func disconnectInput(_ node: AVAudioNode) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.disconnectInput")
        performOnMain {
            self.engine.disconnectNodeInput(node)
        }
    }

    var sendReturnDestinationForTesting: AVAudioNode {
        finalOutputMixer
    }

    /// Live input may only be touched once the user has already granted mic
    /// access. Touching `engine.inputNode` without a grant raises the system
    /// TCC prompt (or kills the app without a usage description) — and debug
    /// builds are ad-hoc signed, so grants do not survive rebuilds. The QA
    /// capture harness must never block on that prompt; routes fall back to
    /// silent/unavailable until the UI's explicit request flow runs.
    /// xcodebuild's test host accesses input promptlessly, so engine tests
    /// opt back in via the override.
    static var liveAudioInputAuthorizedOverrideForTesting: Bool?

    static var liveAudioInputAuthorized: Bool {
        liveAudioInputAuthorizedOverrideForTesting
            ?? (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    /// Tests that assert input-routing bookkeeping set this so the `.input`
    /// monitor source marks itself connected WITHOUT touching
    /// `engine.inputNode` — real input access from tests both risks the TCC
    /// prompt and has been observed stalling for minutes inside CoreAudio.
    static var simulateAudioInputConnectionForTesting = false

    /// Set true by the visual-automation/capture launch path BEFORE any
    /// MainAudioGraph is built. When set, init puts the AVAudioEngine into
    /// offline manual-rendering mode, so the engine renders to a buffer and
    /// never connects to the CoreAudio HAL. This avoids instantiating an
    /// input-capable IO unit — `mainMixerNode`/`outputNode` access otherwise
    /// triggers `GetIOUnit -> AudioComponentInstanceNew -> mic check`, which
    /// raises the macOS TCC microphone prompt and hangs the unattended capture
    /// harness. Gated entirely behind automation: normal launches are
    /// unaffected (flag stays false).
    static var useManualRenderingForAutomation = false

    /// True while the underlying AVAudioEngine is running. Player nodes throw
    /// NSException (uncatchable from Swift) if started against a stopped
    /// engine — callers must check this before `play()`.
    var isEngineRunning: Bool {
        engine.isRunning
    }

    /// True when `node` can be started right now: the engine is running and
    /// the node is still attached and connected. AVAudioPlayerNode.play()
    /// throws an uncatchable NSException for a detached/disconnected node
    /// even on a running engine (seen when a document re-apply tears voices
    /// down while a queued play closure is in flight).
    func isNodePlayableNow(_ node: AVAudioNode) -> Bool {
        engine.isRunning
            && node.engine === engine
            && !engine.outputConnectionPoints(for: node, outputBus: 0).isEmpty
    }

    var availableInputChannelCount: Int {
        guard Self.liveAudioInputAuthorized else { return 0 }
        return Int(engine.inputNode.inputFormat(forBus: 0).channelCount)
    }

    func syncAudioInputRoutings(_ requests: [AudioInputRoutingRequest]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            // Registered after the unlock defer, so it runs first (LIFO):
            // the snapshot publishes under graphLock, before any other
            // routing pass can interleave. Covers both the scoped-update
            // early return and the full rebuild below.
            defer { self.publishAudioInputCaptureFormatsOnMain() }
            if self.canUpdateAudioInputRoutingParametersOnMain(requests) {
                self.applyAudioInputRoutingParametersOnMain(requests)
                self.audioInputScopedRoutingUpdateCountForTesting += 1
                return
            }

            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

            let requestedIDs = Set(requests.map(\.trackID))
            for trackID in self.audioInputRoutingHosts.keys.filter({ !requestedIDs.contains($0) }) {
                self.teardownAudioInputRoutingOnMain(trackID: trackID)
            }

            for request in requests {
                self.installAudioInputRoutingOnMain(request)
            }

            self.audioInputFullRoutingSyncCountForTesting += 1
            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            // Live input monitoring needs a running engine even when the
            // transport is stopped — without this, the input tap never
            // delivers a buffer and the level meters sit silent until the
            // user happens to press play.
            let wantsLiveAudio = !Self.simulateAudioInputConnectionForTesting
                && requests.contains { $0.source != .silent }
            if wasRunning || wantsLiveAudio {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    func setAudioInputCaptureHandler(_ handler: ((UUID, AVAudioPCMBuffer) -> Void)?) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.audioInputCaptureHandler = handler
            for host in self.audioInputRoutingHosts.values {
                if handler == nil {
                    self.removeAudioInputCaptureTapOnMain(host: host)
                } else {
                    self.installAudioInputCaptureTapIfNeededOnMain(host: host)
                }
            }
        }
    }

    func updateAudioInputRoutingParameters(_ requests: [AudioInputRoutingRequest]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.applyAudioInputRoutingParametersOnMain(requests)
            self.audioInputScopedRoutingUpdateCountForTesting += 1
            self.publishAudioInputCaptureFormatsOnMain()
        }
    }

    /// Tick-path safe: reads the lock-protected snapshot published by main
    /// at every graph reconfiguration point — NO synchronous main hop (this
    /// read at record start was the last waived TickPathMainSyncGuard hop).
    /// A snapshot miss during an in-flight reconfigure returns nil, which
    /// fails the capture plan cleanly (recording proceeds without a PCM
    /// writer) instead of blocking the tick queue on main.
    func audioInputCaptureFormat(trackID: UUID) -> AVAudioFormat? {
        audioInputCaptureFormatSnapshotLock.withLock {
            audioInputCaptureFormatSnapshot[trackID]
        }
    }

    /// Recomputes the capture-format snapshot from the live hosts. Must run
    /// on main (hosts and node connections only mutate on main); callers in
    /// the routing/install paths hold graphLock, which is fine — the
    /// snapshot lock is a leaf. Call after ANY mutation that can change a
    /// host's connected source or its output mixer's input format: routing
    /// syncs (install/teardown/source rewires, including the simulation-flag
    /// behavior baked in at connect time), scoped parameter updates, send/
    /// mixer-bus topology installs (engine stop/rebuild/start), device
    /// applies (hardware format change), and the loop-play failure path
    /// (forces a host back to silent outside a sync).
    @MainActor
    private func publishAudioInputCaptureFormatsOnMain() {
        var formats: [UUID: AVAudioFormat] = [:]
        for (trackID, host) in audioInputRoutingHosts where host.connectedSource != .silent {
            let format = host.outputMixer.inputFormat(forBus: 0)
            guard format.sampleRate > 0,
                  format.channelCount > 0
            else {
                continue
            }
            formats[trackID] = format
        }
        audioInputCaptureFormatSnapshotLock.withLock {
            audioInputCaptureFormatSnapshot = formats
        }
    }

    @discardableResult
    func scheduleAudioInputLoopPlayback(trackID: UUID, buffer: AVAudioPCMBuffer) -> Bool {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard let host = self.audioInputRoutingHosts[trackID],
                  host.connectedSource == .loop,
                  buffer.frameLength > 0
            else {
                return false
            }

            host.loopPlayer.stop()
            // The buffer must match the player's CONNECTION format — both
            // scheduleBuffer and play() throw uncatchable NSExceptions on a
            // mismatch (observed: mono-interface capture vs the stereo
            // default connection; rewiring a running graph also throws at
            // play). Convert the buffer instead of touching the graph.
            let connectionFormat = host.loopPlayer.outputFormat(forBus: 0)
            guard let playbackBuffer = buffer.convertingForPlayback(to: connectionFormat) else {
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "loop schedule dropped: cannot convert \(buffer.format) to \(connectionFormat)"
                )
                return false
            }
            if let exception = SEQRunCatchingObjCException({
                host.loopPlayer.scheduleBuffer(playbackBuffer, at: nil, options: .loops, completionHandler: nil)
            }) {
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "loop schedule dropped: \(exception.name.rawValue): \(exception.reason ?? "no reason")"
                )
                return false
            }
            if self.engine.isRunning || self.isStarted, self.isNodePlayableNow(host.loopPlayer) {
                if let exception = SEQRunCatchingObjCException({ host.loopPlayer.play() }) {
                    DevActivity.trace(
                        DevActivity.audioGraph,
                        "loop play dropped: \(exception.name.rawValue): \(exception.reason ?? "no reason")"
                    )
                    // Force the next routing sync to rebuild this host's
                    // chain from scratch — the scoped path would skip it
                    // and the player would stay disconnected forever.
                    host.requestedSource = .silent
                    host.connectedSource = .silent
                    // Source changed outside a routing sync: keep the
                    // tick-path capture-format snapshot honest.
                    self.publishAudioInputCaptureFormatsOnMain()
                    return false
                }
            }
            host.scheduledLoopFrameCount = buffer.frameLength
            host.scheduledLoopChannelCount = buffer.format.channelCount
            host.scheduledLoopSampleRate = buffer.format.sampleRate
            host.loopPlaybackScheduleCount += 1
            return true
        }
    }

    func installMixerBuses(_ buses: [MixerBus], effectiveMuteByBusID: [UUID: Bool] = [:]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            // LIFO: publishes under graphLock after any topology rebuild —
            // an engine stop/rebuild/start can renegotiate node formats.
            defer { self.publishAudioInputCaptureFormatsOnMain() }
            // R2 (fixed-superset): rebuild mixer-bus topology on the LIVE engine
            // — no stop/start. Each bus's inputMixer (track destination) is
            // stable across insert changes; only the insert chain + terminal
            // wiring rebuilds. The master meter tap on finalOutputMixer is
            // unaffected and is not bounced.
            let nextIDs = Set(buses.map(\.id))
            let removedIDs = self.mixerBusHosts.keys.filter { !nextIDs.contains($0) }
            for busID in removedIDs {
                self.mixerBusHosts[busID]?.teardown(from: self)
                self.mixerBusHosts.removeValue(forKey: busID)
            }

            for bus in MixerBus.normalizedCollection(buses) {
                let host = self.mixerBusHosts[bus.id] ?? MixerBusHost(id: bus.id)
                self.mixerBusHosts[bus.id] = host
                host.install(bus: bus, in: self, effectiveMute: effectiveMuteByBusID[bus.id] ?? bus.mix.isMuted)
            }

            self.reconnectMixerBusTerminalsOnMain()

            // Re-wire every track whose output feeds a mixer bus, mirroring
            // installSendBuses. A freshly created bus host (or one whose
            // topology just rebuilt — inserts added/removed) is a NEW input
            // mixer / new terminal node; a track routed to it via a separate
            // hot-path connectTrackOutput either landed on the placeholder
            // preMaster fallback (host did not exist yet) or now points at a
            // stale node. Without this pass the track→bus→master chain is
            // never (re)established and the bus stays silent — routing to a
            // just-created bus produced no sound while master worked. Resolving
            // each routing against the live host here closes that gap. Runs on
            // main under graphLock during a topology install only; no work is
            // added to the render callback (Performance-Time Mutation Rule).
            for routing in self.trackOutputRoutings.values
                where routing.busID != nil && routing.source.engine === self.engine {
                self.reconnectTrackOutputOnMain(routing)
            }

            self.installMasterMeterTapIfNeeded()
        }
    }

    func setMixerBusMix(busID: UUID, mix: BusMixSettings, effectiveMute: Bool) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.mixerBusHosts[busID]?.applyMix(mix, effectiveMute: effectiveMute)
        }
    }

    func setMixerBusParameters(bus: MixerBus, effectiveMute: Bool) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.mixerBusHosts[bus.id]?.applyParameters(bus: bus, effectiveMute: effectiveMute)
        }
    }

    func installSendBuses(_ sendBuses: [SendBusState]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            // LIFO: publishes under graphLock after any topology rebuild —
            // an engine stop/rebuild/start can renegotiate node formats.
            defer { self.publishAudioInputCaptureFormatsOnMain() }

            let busesByID = Dictionary(uniqueKeysWithValues: sendBuses.map { ($0.id, $0) })
            var installs: [(host: SendBusHost, state: SendBusState)] = []
            for id in SendBusID.allCases {
                let state = (busesByID[id] ?? SendBusState(id: id)).normalized(expectedID: id)
                let host = self.sendBusHosts[id] ?? SendBusHost(id: id)
                self.sendBusHosts[id] = host
                installs.append((host, state))
            }

            // Value-only fast path: when no host's node topology changes
            // (e.g. a send-FX wet/cutoff slider drag), configure the
            // installed nodes in place and leave the engine RUNNING. The
            // stop/reinstall/reconnect/start cycle below at drag rate was
            // mixer-latency cause 3 (audible dropouts per mouse-move).
            let needsTopologyChange = installs.contains { $0.host.needsTopologyChange(for: $0.state) }
            guard needsTopologyChange else {
                for (host, state) in installs {
                    host.install(sendBus: state, in: self)
                }
                return
            }

            self.sendBusTopologyInstallCountForTesting += 1
            // R2 (fixed-superset): rebuild send-bus insert chains on the LIVE
            // engine — no stop/start. A send bus's inputMixer (the node tracks
            // route to) is stable across insert changes, so only the chain
            // behind it rebuilds; the master meter tap on finalOutputMixer is
            // unaffected and is not bounced. Tracks are re-resolved so R0's
            // persistent fanout is (re)established when a send destination
            // first appears.
            for (host, state) in installs {
                host.install(sendBus: state, in: self)
            }

            for routing in self.trackOutputRoutings.values where routing.source.engine === self.engine {
                self.reconnectTrackOutputOnMain(routing)
            }

            self.installMasterMeterTapIfNeeded()
        }
    }

    func installSendBus(_ sendBus: SendBusState) {
        let existing = performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return SendBusID.allCases.map { id in
                if id == sendBus.id {
                    return sendBus
                }
                return self.sendBusHosts[id]?.appliedStateForTesting ?? SendBusState(id: id)
            }
        }
        installSendBuses(existing)
    }

    func connectTrackOutput(
        _ source: AVAudioNode,
        to busID: UUID?,
        sends sendLevels: TrackSendLevels = .zero
    ) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.connectTrackOutput")
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard source.engine === self.engine else { return }

            // R1 (fixed-superset): rewire the track's output on the LIVE engine
            // — no stop/start. With R0's persistent fanout the change only
            // re-points the fanout's destinations; the master meter tap lives on
            // finalOutputMixer and is unaffected, so it is not bounced.
            // AVAudioEngine supports attach/connect/disconnect while running.
            // (Ramp-to-silence on a reassignment of a *sounding* track is the
            // follow-up in docs/plans/2026-06-24-fixed-superset-routing.md.)
            let routing = TrackOutputRouting(source: source, busID: busID, sendLevels: sendLevels)
            self.trackOutputRoutings[ObjectIdentifier(source)] = routing
            self.reconnectTrackOutputOnMain(routing)
        }
    }

    func connectPreparedSampleVoiceOutput(
        _ source: AVAudioNode,
        toMixerBus busID: UUID,
        inputBus: AVAudioNodeBus
    ) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.connectPreparedSampleVoiceOutput")
        performOnMain {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard source.engine === self.engine,
                  let destination = self.mixerBusHosts[busID]?.destinationNode()
            else {
                return
            }
            // realtime-allow-graph-mutation: prepared sample bus-safe route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
            self.engine.disconnectNodeOutput(source)
            // realtime-allow-graph-mutation: prepared sample bus-safe route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
            self.engine.connect(
                source,
                to: destination,
                fromBus: 0,
                toBus: inputBus,
                format: nil
            )
            self.trackOutputDestinationsForTesting[ObjectIdentifier(source)] = destination
        }
    }

    /// Install (or update) a track's FX insert chain. The chain is spliced
    /// between the track's output source node (resolved via the meter-source
    /// registration each track subsystem already publishes) and its dry/sends
    /// destinations.
    ///
    /// Value-only changes (e.g. a bypass toggle on an already-installed chain)
    /// configure the installed nodes in place and leave the engine RUNNING —
    /// matching the send-bus / track-fader scoped paths so continuous edits do
    /// not stop/reinstall/start the engine per gesture (Performance-Time
    /// Mutation Rule). A topology change (insert added/removed/reordered, or an
    /// AU still loading) takes the stop/rebuild/reconnect/start path.
    func setTrackInserts(trackID: UUID, inserts: [TrackFXInsert]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.applyTrackInsertsOnMain(trackID: trackID, inserts: inserts)
        }
    }

    /// Re-entry point for `TrackInsertChainHost` AU-load completion. Hops onto
    /// the graph queue and re-applies the latest authored chain so the freshly
    /// instantiated AU node wires in. Mirrors the send-bus post-load re-entry.
    private func rebuildTrackInsertChainAfterLoad(trackID: UUID) {
        performOnMain {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard let inserts = self.trackInsertChainsByTrackID[trackID] else { return }
            self.applyTrackInsertsOnMain(trackID: trackID, inserts: inserts, forceRebuild: true)
        }
    }

    @MainActor
    private func applyTrackInsertsOnMain(trackID: UUID, inserts: [TrackFXInsert], forceRebuild: Bool = false) {
        self.trackInsertChainsByTrackID[trackID] = inserts

        // No source node registered yet (track not prepared / playing): retain
        // the authored chain; it installs once the source registers and the
        // output is (re)connected.
        guard let source = self.trackMeterSources[trackID], source.engine === self.engine else {
            return
        }

        let host = self.trackInsertChainHosts[trackID] ?? self.makeTrackInsertChainHost(trackID: trackID)
        self.trackInsertChainHosts[trackID] = host

        // Value-only fast path: configure installed nodes in place, leave the
        // engine running (Performance-Time Mutation Rule — a bypass toggle on
        // a held chain must not stop/reinstall the engine).
        if !forceRebuild, !host.needsTopologyChange(for: inserts) {
            host.configureInstalledNodes(for: inserts)
            return
        }

        self.trackInsertChainTopologyInstallCountForTesting += 1
        // R2 (fixed-superset): rebuild the track insert chain on the LIVE
        // engine — no stop/start. reconnectTrackOutputOnMain re-splices
        // source -> chain -> fanout afterwards; the master meter tap on
        // finalOutputMixer is unaffected and is not bounced. Removes the global
        // silence gap when a track's FX inserts change during play (drum parts
        // are tracks, so this covers per-part FX too).
        host.rebuild(inserts: inserts, in: self)
        if let routing = self.trackOutputRoutings[ObjectIdentifier(source)] {
            self.reconnectTrackOutputOnMain(routing)
        }

        self.installMasterMeterTapIfNeeded()
    }

    @MainActor
    private func makeTrackInsertChainHost(trackID: UUID) -> TrackInsertChainHost {
        let factory = trackInsertAUFactoryForTesting ?? AUAudioUnitFactory()
        return TrackInsertChainHost(
            trackID: trackID,
            factory: factory,
            requestRebuild: { [weak self] trackID in
                self?.rebuildTrackInsertChainAfterLoad(trackID: trackID)
            }
        )
    }

    /// Tear down a track's FX insert chain (track removed). Safe to call for a
    /// track with no chain.
    func teardownTrackInserts(trackID: UUID) {
        performOnMain {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.trackInsertChainsByTrackID.removeValue(forKey: trackID)
            guard let host = self.trackInsertChainHosts.removeValue(forKey: trackID) else { return }
            host.teardown(from: self)
        }
    }

    var trackInsertChainReadoutForTesting: [UUID: Int] {
        performOnMainReturning {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.trackInsertChainHosts.mapValues { $0.topologyRebuildCount }
        }
    }

    func setTrackSendLevels(_ source: AVAudioNode, sendA: Double, sendB: Double) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.setTrackSendLevels")
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            let key = ObjectIdentifier(source)
            let sendLevels = TrackSendLevels(sendA: sendA, sendB: sendB)
            guard var routing = self.trackOutputRoutings[key] else { return }

            routing.sendLevels = sendLevels
            self.trackOutputRoutings[key] = routing

            // R0 (fixed-superset): send nodes are persistent. When they exist
            // (the send buses are installed), any level change — including
            // crossing zero in either direction — is a pure outputVolume write
            // with no live disconnect/reconnect; they are torn down only when
            // the track is removed. If they do not exist yet (send buses not
            // installed), establish the geometry once.
            guard let nodes = self.trackSendNodes[key] else {
                self.reconnectTrackOutputOnMain(routing)
                return
            }
            nodes.sendA.outputVolume = sendLevels.clampedSendA
            nodes.sendB.outputVolume = sendLevels.clampedSendB
        }
    }

    func start() throws {
        try performOnMainThrowing {
            guard !self.isStarted || !self.engine.isRunning else { return }
            self.installMasterMeterTapIfNeeded()
            self.channelMeterBank.startPublishing()
            try self.engine.start()
            self.isStarted = true
        }
    }

    func stop() {
        performOnMain {
            self.removeMasterMeterTapIfNeeded()
            self.channelMeterBank.stopPublishing()
            guard self.isStarted || self.engine.isRunning else { return }
            self.engine.stop()
            self.isStarted = false
        }
    }

    func applyAudioDeviceUIDs(
        inputUID: String?,
        outputUID: String?,
        deviceOwner: AudioDeviceOwning? = nil
    ) throws -> AudioDeviceApplyResult {
        try performOnMainThrowingReturning {
            let deviceOwner = deviceOwner ?? self.audioDeviceOwner
            let previousInputUID = deviceOwner.activeDeviceUID(direction: .input)
            let previousOutputUID = deviceOwner.activeDeviceUID(direction: .output)
            let wasRunning = self.engine.isRunning || self.isStarted

            self.removeMasterMeterTapIfNeeded()
            if self.engine.isRunning {
                self.engine.stop()
            }

            do {
                let deviceResult = try deviceOwner.apply(inputUID: inputUID, outputUID: outputUID)
                // NOTE deliberately NOT setting the input device on
                // engine.inputNode: on macOS the engine can share one HAL
                // unit between input and output, and forcing the input
                // device re-pointed OUTPUT at an input-only device — total
                // silence (observed 2026-06-11). In-app input device
                // selection currently requires the system-default input;
                // the aggregate-device approach is on the roadmap.
                try self.recoverAudioGraphAfterDeviceApply(wasRunning: wasRunning)

                return AudioDeviceApplyResult(
                    appliedInputDeviceUID: deviceResult.appliedInputDeviceUID,
                    appliedOutputDeviceUID: deviceResult.appliedOutputDeviceUID,
                    wasRunningBeforeApply: wasRunning,
                    restartedEngine: wasRunning && self.engine.isRunning
                )
            } catch {
                let rollbackError = self.rollbackAudioDevicesWithOwner(
                    inputUID: previousInputUID,
                    outputUID: previousOutputUID,
                    deviceOwner: deviceOwner,
                    wasRunning: wasRunning
                )
                if rollbackError == nil, case AudioDeviceApplyError.rollbackPerformed = error {
                    throw error
                }
                throw AudioDeviceApplyError.rollbackPerformed(underlying: error, rollbackError: rollbackError)
            }
        }
    }

    func installMasterChains(
        _ chains: [MasterChain],
        postBlendMasterNodes: [AVAudioNode] = [],
        masterOutputGain: Double = 1
    ) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            let clampedMasterOutputGain = Self.clampedMasterOutputGain(masterOutputGain)
            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

            self.engine.disconnectNodeOutput(self.preMasterMixer)
            self.engine.disconnectNodeInput(self.postBlendMixer)
            self.engine.disconnectNodeOutput(self.postBlendMixer)
            self.engine.disconnectNodeInput(self.finalOutputMixer)
            for node in self.managedMasterNodes {
                if node.engine === self.engine {
                    self.engine.disconnectNodeInput(node)
                    self.engine.disconnectNodeOutput(node)
                    self.engine.detach(node)
                }
            }
            self.managedMasterNodes = []
            self.managedMasterGainMixers = []

            let resolvedChains = chains.isEmpty ? [MasterChain(nodes: [], gain: 1)] : chains
            let resolvedPostBlendNodes = postBlendMasterNodes.filter { node in
                node.engine == nil || node.engine === self.engine
            }
            let usesDirectSingleBranch = resolvedChains.count == 1 && resolvedChains[0].nodes.isEmpty
            var firstDestinations: [AVAudioConnectionPoint] = []
            var branchReadouts: [MasterBranchReadout] = []

            if usesDirectSingleBranch, let chain = resolvedChains.first {
                let clampedGain = Float(min(max(chain.gain, 0), 1.5))
                self.postBlendMixer.outputVolume = clampedGain
                firstDestinations.append(AVAudioConnectionPoint(node: self.postBlendMixer, bus: 0))
                branchReadouts.append(MasterBranchReadout(nodes: [], gain: clampedGain))
            } else {
                self.postBlendMixer.outputVolume = 1
                for chain in resolvedChains {
                    let gainMixer = AVAudioMixerNode()
                    let clampedGain = Float(min(max(chain.gain, 0), 1.5))
                    gainMixer.outputVolume = clampedGain
                    self.engine.attach(gainMixer)
                    self.managedMasterNodes.append(gainMixer)
                    self.managedMasterGainMixers.append(gainMixer)

                    let chainNodes = chain.nodes.filter { node in
                        node.engine == nil || node.engine === self.engine
                    }
                    for node in chainNodes where node.engine == nil {
                        self.engine.attach(node)
                    }
                    self.managedMasterNodes.append(contentsOf: chainNodes)

                    if let first = chainNodes.first {
                        firstDestinations.append(AVAudioConnectionPoint(node: first, bus: 0))
                        for (source, destination) in zip(chainNodes, chainNodes.dropFirst()) {
                            self.engine.connect(source, to: destination, format: nil)
                        }
                        self.engine.connect(chainNodes.last ?? first, to: gainMixer, format: nil)
                    } else {
                        firstDestinations.append(AVAudioConnectionPoint(node: gainMixer, bus: 0))
                    }

                    self.engine.connect(gainMixer, to: self.postBlendMixer, format: nil)
                    branchReadouts.append(MasterBranchReadout(nodes: chainNodes, gain: clampedGain))
                }
            }

            for node in resolvedPostBlendNodes where node.engine == nil {
                self.engine.attach(node)
            }
            self.managedMasterNodes.append(contentsOf: resolvedPostBlendNodes)

            if let firstMasterNode = resolvedPostBlendNodes.first {
                self.engine.connect(self.postBlendMixer, to: firstMasterNode, format: nil)
                for (source, destination) in zip(resolvedPostBlendNodes, resolvedPostBlendNodes.dropFirst()) {
                    self.engine.connect(source, to: destination, format: nil)
                }
                self.engine.connect(resolvedPostBlendNodes.last ?? firstMasterNode, to: self.finalOutputMixer, format: nil)
            } else {
                self.engine.connect(self.postBlendMixer, to: self.finalOutputMixer, format: nil)
            }

            self.masterBranchesForTesting = branchReadouts
            self.postBlendMasterInsertNodesForTesting = resolvedPostBlendNodes
            self.finalOutputMixer.outputVolume = clampedMasterOutputGain
            self.masterOutputGainForTesting = clampedMasterOutputGain
            if let destination = firstDestinations.first,
               firstDestinations.count == 1,
               let node = destination.node
            {
                self.engine.connect(
                    self.preMasterMixer,
                    to: node,
                    fromBus: 0,
                    toBus: destination.bus,
                    format: nil
                )
            } else {
                self.engine.connect(self.preMasterMixer, to: firstDestinations, fromBus: 0, format: nil)
            }
            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    var isMasterMeterTapInstalledForTesting: Bool {
        isMasterMeterTapInstalled
    }

    var mixerBusReadoutsForTesting: [MixerBusHost.Readout] {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.mixerBusHosts.values.compactMap { $0.readout() }
                .sorted { $0.busID.uuidString < $1.busID.uuidString }
        }
    }

    func mixerBusReadoutForTesting(busID: UUID) -> MixerBusHost.Readout? {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.mixerBusHosts[busID]?.readout()
        }
    }

    var sendBusReadoutsForTesting: [SendBusHost.Readout] {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.sendBusHosts.values.compactMap { $0.readout() }
                .sorted { $0.busID.rawValue < $1.busID.rawValue }
        }
    }

    /// Test seam: registers a pre-built host (e.g. with an injected AU
    /// factory) so installSendBus(es) exercise it.
    func installSendBusHostForTesting(_ host: SendBusHost) {
        performOnMain {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.sendBusHosts[host.id] = host
        }
    }

    func sendBusReadoutForTesting(busID: SendBusID) -> SendBusHost.Readout? {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.sendBusHosts[busID]?.readout()
        }
    }

    func trackOutputDestinationForTesting(_ source: AVAudioNode) -> AVAudioNode? {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.trackOutputDestinationsForTesting[ObjectIdentifier(source)]
        }
    }

    func trackSendReadoutForTesting(_ source: AVAudioNode) -> TrackSendReadout? {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            let key = ObjectIdentifier(source)
            guard let dryDestination = self.trackOutputDestinationsForTesting[key] else {
                return nil
            }
            let nodes = self.trackSendNodes[key]
            let sendDestinations = self.trackSendDestinationsForTesting[key]
            return TrackSendReadout(
                dryDestination: dryDestination,
                sendFanoutNode: nodes?.fanout,
                sendAGainNode: nodes?.sendA,
                sendBGainNode: nodes?.sendB,
                sendAGain: nodes?.sendA.outputVolume ?? 0,
                sendBGain: nodes?.sendB.outputVolume ?? 0,
                sendFanoutDestinations: sendDestinations?.fanout ?? [],
                sendADestination: sendDestinations?.sendA,
                sendBDestination: sendDestinations?.sendB
            )
        }
    }

    func audioInputRoutingReadoutForTesting(trackID: UUID) -> AudioInputRoutingReadout? {
        return performOnMainReturning {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard let host = self.audioInputRoutingHosts[trackID] else { return nil }
            return AudioInputRoutingReadout(
                trackID: host.trackID,
                selectedChannel: host.selectedChannel,
                requestedSource: host.requestedSource,
                connectedSource: host.connectedSource,
                outputMixer: host.outputMixer,
                loopPlayer: host.loopPlayer,
                dryDestination: self.trackOutputDestinationsForTesting[ObjectIdentifier(host.outputMixer)],
                outputVolume: host.outputMixer.outputVolume,
                pan: host.outputMixer.pan,
                scheduledLoopFrameCount: host.scheduledLoopFrameCount,
                scheduledLoopChannelCount: host.scheduledLoopChannelCount,
                scheduledLoopSampleRate: host.scheduledLoopSampleRate,
                loopPlaybackScheduleCount: host.loopPlaybackScheduleCount
            )
        }
    }

    var masterMeterTapGenerationForTesting: Int {
        Int(masterMeterTapGeneration.load())
    }

    func recordMasterMeterPeakForTesting(left: Double, right: Double, generation: Int? = nil) {
        let currentGeneration = masterMeterTapGeneration.load()
        let resolvedGeneration = generation.map(Int32.init) ?? currentGeneration
        guard resolvedGeneration == currentGeneration else { return }
        masterMeterPublisher.recordPeakAmplitudes(left: left, right: right)
    }

    // MARK: - Master render to file
    //
    // Records exactly what reaches the master output to a WAV — the
    // ears-free way to verify sequencing: render N bars, assert on the
    // file. Shares the master meter tap (one tap per bus).

    /// Starts writing master output to `url`. Returns false if a render is
    /// already active or the file cannot be created.
    @discardableResult
    func startMasterRender(to url: URL) -> Bool {
        let format = finalOutputMixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        masterRenderLock.lock()
        defer { masterRenderLock.unlock() }
        guard masterRenderFile == nil else { return false }
        guard let file = try? AVAudioFile(forWriting: url, settings: settings) else {
            DevActivity.trace(DevActivity.audioGraph, "master render: cannot create file at \(url.path)")
            return false
        }
        masterRenderFile = file
        masterRenderURL = url
        DevActivity.trace(DevActivity.audioGraph, "master render started: \(url.lastPathComponent)")
        return true
    }

    /// Stops an active master render and returns the file URL, or nil if
    /// none was active.
    @discardableResult
    func stopMasterRender() -> URL? {
        masterRenderLock.lock()
        let url = masterRenderURL
        masterRenderFile = nil
        masterRenderURL = nil
        masterRenderLock.unlock()
        if let url {
            DevActivity.trace(DevActivity.audioGraph, "master render stopped: \(url.lastPathComponent)")
        }
        return url
    }

    var isMasterRenderActive: Bool {
        masterRenderLock.lock()
        defer { masterRenderLock.unlock() }
        return masterRenderFile != nil
    }

    private func writeMasterRenderBufferIfActive(_ buffer: AVAudioPCMBuffer) {
        masterRenderLock.lock()
        let file = masterRenderFile
        masterRenderLock.unlock()
        guard let file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            DevActivity.trace(DevActivity.audioGraph, "master render write failed: \(error)")
        }
    }

    /// Test hook: pushes a buffer through the render write path without a
    /// running engine.
    func writeMasterRenderBufferForTesting(_ buffer: AVAudioPCMBuffer) {
        writeMasterRenderBufferIfActive(buffer)
    }

    #if DEBUG
    /// Test hook: advances AVAudioEngine offline manual rendering so taps and
    /// scheduled player nodes produce deterministic buffers without the HAL.
    func renderOfflineForTesting(frameCount: AVAudioFrameCount) throws {
        let format = engine.manualRenderingFormat
        let capacity = min(max(1, frameCount), engine.manualRenderingMaximumFrameCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return
        }
        var remaining = frameCount
        while remaining > 0 {
            let chunk = min(remaining, capacity)
            _ = try engine.renderOffline(chunk, to: buffer)
            remaining -= chunk
        }
    }
    #endif

    @MainActor
    private func installMasterMeterTapIfNeeded() {
        installChannelMeterTapsIfNeeded()
        guard !isMasterMeterTapInstalled else { return }
        let generation = masterMeterTapGeneration.increment()
        finalOutputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, self.masterMeterTapGeneration.load() == generation else { return }
            self.masterMeterPublisher.process(buffer: buffer)
            self.writeMasterRenderBufferIfActive(buffer)
        }
        isMasterMeterTapInstalled = true
        masterMeterTapPointForTesting = .finalOutputMixer
        masterMeterTapInstallCountForTesting += 1
    }

    @MainActor
    private func removeMasterMeterTapIfNeeded() {
        removeChannelMeterTapsIfNeeded()
        guard isMasterMeterTapInstalled else { return }
        masterMeterTapGeneration.increment()
        finalOutputMixer.removeTap(onBus: 0)
        masterMeterPublisher.recordPeakAmplitudes(left: 0, right: 0)
        isMasterMeterTapInstalled = false
        masterMeterTapPointForTesting = nil
        masterMeterTapRemoveCountForTesting += 1
    }

    // MARK: - Channel meter taps (roadmap 29)
    //
    // One tap per strip node, installed/removed at exactly the master-tap
    // sites so they only ever touch the graph while it is being rebuilt.
    // A node carries at most one tap, so nodes that already host the audio
    // input capture tap are skipped until that tap clears.

    /// Track strips register the node whose output represents the track
    /// (post level/pan, post filter). Multiple tracks may share one node
    /// when they share a playback host. Passing an empty set unregisters
    /// the node.
    func setTrackMeterSources(trackIDs: Set<UUID>, node: AVAudioNode) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            self.trackMeterSources = self.trackMeterSources.filter { $0.value !== node || trackIDs.contains($0.key) }
            for trackID in trackIDs {
                self.trackMeterSources[trackID] = node
            }
            guard self.areChannelMeterTapsInstalled else { return }
            self.removeChannelMeterTapsIfNeeded()
            self.installChannelMeterTapsIfNeeded()
        }
    }

    var trackMeterSourceCountForTesting: Int {
        performOnMainReturning {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.trackMeterSources.count
        }
    }

    var channelMeterTappedNodeCountForTesting: Int {
        performOnMainReturning {
            self.channelMeterTappedNodes.count
        }
    }

    @MainActor
    private func installChannelMeterTapsIfNeeded() {
        guard !areChannelMeterTapsInstalled else { return }
        let generation = channelMeterTapGeneration.increment()

        var entries: [ObjectIdentifier: (node: AVAudioNode, ids: [ChannelMeterID])] = [:]
        func register(_ node: AVAudioNode?, _ id: ChannelMeterID) {
            guard let node, node.engine === engine, node !== finalOutputMixer else { return }
            entries[ObjectIdentifier(node), default: (node, [])].ids.append(id)
        }

        for (busID, host) in mixerBusHosts {
            register(host.destinationNode(), .bus(busID))
        }
        for (sendID, host) in sendBusHosts {
            register(host.destinationNode(), .send(sendID))
        }
        for (trackID, node) in trackMeterSources {
            if let host = audioInputRoutingHosts[trackID], host.outputMixer === node, host.isCaptureTapInstalled {
                continue
            }
            register(node, .track(trackID))
        }

        for (key, entry) in entries {
            let publishers = entry.ids.map { channelMeterBank.publisher(for: $0) }
            // installTap throws an uncatchable NSException if the node
            // already has a tap — the shim turns a bookkeeping slip into a
            // skipped meter instead of a crash.
            let exception = SEQRunCatchingObjCException {
                entry.node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                    guard let self, self.channelMeterTapGeneration.load() == generation else { return }
                    for publisher in publishers {
                        publisher.process(buffer: buffer)
                    }
                }
            }
            guard exception == nil else {
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "channel meter tap skipped: \(exception?.reason ?? "unknown")"
                )
                continue
            }
            channelMeterTappedNodes[key] = entry.node
            channelMeterTapInstallCountForTesting += 1
        }
        areChannelMeterTapsInstalled = true
    }

    @MainActor
    private func removeChannelMeterTapsIfNeeded() {
        guard areChannelMeterTapsInstalled else { return }
        channelMeterTapGeneration.increment()
        for node in channelMeterTappedNodes.values {
            _ = SEQRunCatchingObjCException {
                node.removeTap(onBus: 0)
            }
            channelMeterTapRemoveCountForTesting += 1
        }
        channelMeterTappedNodes = [:]
        channelMeterBank.recordSilenceEverywhere()
        areChannelMeterTapsInstalled = false
    }

    /// Removes one node's meter tap immediately (e.g. before the capture
    /// tap claims the node, or before the node is detached).
    @MainActor
    private func removeChannelMeterTapIfInstalled(on node: AVAudioNode) {
        let key = ObjectIdentifier(node)
        guard channelMeterTappedNodes[key] != nil else { return }
        _ = SEQRunCatchingObjCException {
            node.removeTap(onBus: 0)
        }
        channelMeterTappedNodes.removeValue(forKey: key)
        channelMeterTapRemoveCountForTesting += 1
    }

    private static func clampedMasterOutputGain(_ gain: Double) -> Float {
        guard gain.isFinite else { return 1 }
        return Float(min(max(gain, 0), 2))
    }

    @MainActor
    private func recoverAudioGraphAfterDeviceApply(wasRunning: Bool) throws {
        // A device switch can change the hardware format; the engine
        // reset/prepare renegotiates node formats. Republish the tick-path
        // capture-format snapshot whether recovery succeeds or throws (both
        // the apply and rollback paths land here).
        defer { publishAudioInputCaptureFormatsOnMain() }
        if self.engine.isRunning {
            self.engine.stop()
        }
        self.engine.reset()
        self.engine.prepare()
        self.installMasterMeterTapIfNeeded()
        if wasRunning {
            self.channelMeterBank.startPublishing()
            try self.engine.start()
        }
        self.isStarted = wasRunning ? self.engine.isRunning : self.isStarted
    }

    @MainActor
    private func rollbackAudioDevicesWithOwner(
        inputUID: String?,
        outputUID: String?,
        deviceOwner: AudioDeviceOwning,
        wasRunning: Bool
    ) -> Error? {
        do {
            _ = try deviceOwner.apply(inputUID: inputUID, outputUID: outputUID)
            try self.recoverAudioGraphAfterDeviceApply(wasRunning: wasRunning)
            return nil
        } catch {
            self.isStarted = self.engine.isRunning
            return error
        }
    }

    func setMasterOutputGain(_ gain: Double) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            let clampedGain = Self.clampedMasterOutputGain(gain)
            self.finalOutputMixer.outputVolume = clampedGain
            self.masterOutputGainForTesting = clampedGain
        }
    }

    func setMasterBranchGains(_ gains: [Double]) {
        performOnMain {
            // Acquired inside the main-thread closure: holding
            // graphLock across DispatchQueue.main.sync is a
            // lock-order deadlock waiting to happen.
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard !gains.isEmpty else { return }
            for (index, gain) in gains.enumerated() where index < self.managedMasterGainMixers.count {
                let clampedGain = Float(min(max(gain, 0), 1.5))
                self.managedMasterGainMixers[index].outputVolume = clampedGain
                if index < self.masterBranchesForTesting.count {
                    self.masterBranchesForTesting[index].gain = clampedGain
                }
            }
        }
    }

    @MainActor
    private func reconnectTrackOutputOnMain(_ routing: TrackOutputRouting) {
        reconnectTrackOutputCountForTesting += 1
        let source = routing.source
        let dryDestination = routing.busID.flatMap { mixerBusHosts[$0]?.destinationNode() } ?? preMasterMixer
        engine.disconnectNodeOutput(source)

        // Splice the per-track FX insert chain (if any) directly after the
        // track's output source: source -> [insert chain] -> chainOutput. Every
        // downstream wire (dry destination + send fanout) then feeds from
        // `chainOutput`, so sends are post-insert (mirroring a DAW channel
        // strip). The chain host owns the internal series wiring; here we only
        // wire the two boundaries. When the chain is empty, `chainOutput`
        // collapses back to `source` and the geometry is unchanged.
        let chainOutput: AVAudioNode
        if let host = trackInsertChainHosts[trackID(for: source)],
           let chainInput = host.inputNode,
           let chainTerminal = host.terminalNode
        {
            engine.disconnectNodeOutput(chainTerminal)
            engine.connect(source, to: chainInput, format: nil)
            chainOutput = chainTerminal
        } else {
            chainOutput = source
        }

        var destinations = [connectionPoint(for: dryDestination)]
        // R0 (fixed-superset): when the send buses exist, every track keeps
        // persistent fanout/sendA/sendB nodes for its whole life and always
        // routes its dry signal THROUGH the fanout — geometry independent of
        // engine.isRunning. "No send" is gain 0, never a node teardown, so a
        // send fader crossing zero is a pure outputVolume change (see
        // setTrackSendLevels) with no live disconnect/reconnect. Routing dry on
        // the fanout means a later bus change only rewires that one leg — the
        // property the engine.isRunning gate (commit 72aaf0b2) used to provide
        // for the running case, now universal. Nodes are torn down only on
        // track removal (removeTrackSendNodes).
        if sendBusHosts[.sendA]?.destinationNode() != nil,
           sendBusHosts[.sendB]?.destinationNode() != nil
        {
            let nodes = sendNodes(for: source, levels: routing.sendLevels)
            engine.disconnectNodeOutput(nodes.fanout)
            engine.disconnectNodeInput(nodes.fanout)
            engine.disconnectNodeOutput(nodes.sendA)
            engine.disconnectNodeInput(nodes.sendA)
            engine.disconnectNodeOutput(nodes.sendB)
            engine.disconnectNodeInput(nodes.sendB)
            let fanoutDestinations = [
                connectionPoint(for: dryDestination),
                connectionPoint(for: nodes.sendA),
                connectionPoint(for: nodes.sendB),
            ]
            engine.connect(nodes.fanout, to: fanoutDestinations, fromBus: 0, format: nil)

            var sendDestinations = TrackSendDestinations(
                fanout: [dryDestination, nodes.sendA, nodes.sendB],
                sendA: nil,
                sendB: nil
            )
            if let sendADestination = sendBusHosts[.sendA]?.destinationNode() {
                engine.connect(
                    nodes.sendA,
                    to: sendADestination,
                    fromBus: 0,
                    toBus: inputBus(for: sendADestination),
                    format: nil
                )
                sendDestinations.sendA = sendADestination
            }
            if let sendBDestination = sendBusHosts[.sendB]?.destinationNode() {
                engine.connect(
                    nodes.sendB,
                    to: sendBDestination,
                    fromBus: 0,
                    toBus: inputBus(for: sendBDestination),
                    format: nil
                )
                sendDestinations.sendB = sendBDestination
            }
            trackSendDestinationsForTesting[ObjectIdentifier(source)] = sendDestinations
            destinations = [connectionPoint(for: nodes.fanout)]
        } else {
            // Send buses not installed yet: route dry only and tear down any
            // stale send nodes. installSendBuses re-reconnects every track once
            // the buses exist, which establishes the persistent geometry above.
            let key = ObjectIdentifier(source)
            if let nodes = trackSendNodes.removeValue(forKey: key) {
                engine.disconnectNodeOutput(nodes.fanout)
                engine.disconnectNodeInput(nodes.fanout)
                engine.disconnectNodeOutput(nodes.sendA)
                engine.disconnectNodeInput(nodes.sendA)
                engine.disconnectNodeOutput(nodes.sendB)
                engine.disconnectNodeInput(nodes.sendB)
                engine.detach(nodes.fanout)
                engine.detach(nodes.sendA)
                engine.detach(nodes.sendB)
            }
            trackSendDestinationsForTesting.removeValue(forKey: key)
        }

        if let destination = destinations.first, destinations.count == 1, let node = destination.node {
            engine.connect(
                chainOutput,
                to: node,
                fromBus: 0,
                toBus: destination.bus,
                format: nil
            )
        } else {
            engine.connect(chainOutput, to: destinations, fromBus: 0, format: nil)
        }
        trackOutputDestinationsForTesting[ObjectIdentifier(source)] = dryDestination
    }

    @MainActor
    private func reconnectMixerBusTerminalsOnMain() {
        var inputBusCursor: [ObjectIdentifier: AVAudioNodeBus] = [:]
        for readout in mixerBusHosts.values.compactMap({ $0.readout() }) {
            let terminal = readout.terminalSourceNode ?? readout.inputMixer
            engine.disconnectNodeOutput(terminal)
            engine.connect(
                terminal,
                to: preMasterMixer,
                fromBus: 0,
                toBus: inputBus(for: preMasterMixer, cursor: &inputBusCursor),
                format: nil
            )
        }
    }

    /// Resolve the trackID whose registered meter source is `node`, so the
    /// insert chain (keyed by trackID) can be located from the output source
    /// node `reconnectTrackOutput` operates on.
    @MainActor
    private func trackID(for node: AVAudioNode) -> UUID {
        trackMeterSources.first(where: { $0.value === node })?.key ?? UUID()
    }

    @MainActor
    private func installAudioInputRoutingOnMain(_ request: AudioInputRoutingRequest) {
        let host = audioInputRoutingHosts[request.trackID] ?? AudioInputRoutingHost(trackID: request.trackID)
        audioInputRoutingHosts[request.trackID] = host

        if host.outputMixer.engine == nil {
            engine.attach(host.outputMixer)
        }
        if host.loopPlayer.engine == nil {
            engine.attach(host.loopPlayer)
        }

        host.selectedChannel = request.selectedChannel
        host.requestedSource = request.source

        // The output mixer is the audio-input track's meter point (post
        // level/pan), matching the other strip kinds.
        trackMeterSources[request.trackID] = host.outputMixer

        reconnectAudioInputSourceOnMain(host: host, requestedSource: request.source)
        applyAudioInputRoutingParametersOnMain(request)
        installAudioInputCaptureTapIfNeededOnMain(host: host)
    }

    @MainActor
    private func canUpdateAudioInputRoutingParametersOnMain(_ requests: [AudioInputRoutingRequest]) -> Bool {
        let requestedIDs = Set(requests.map(\.trackID))
        guard requestedIDs == Set(audioInputRoutingHosts.keys) else { return false }
        return requests.allSatisfy { request in
            guard let host = audioInputRoutingHosts[request.trackID] else { return false }
            return host.requestedSource == request.source
                && host.selectedChannel == request.selectedChannel
        }
    }

    @MainActor
    private func applyAudioInputRoutingParametersOnMain(_ requests: [AudioInputRoutingRequest]) {
        for request in requests {
            applyAudioInputRoutingParametersOnMain(request)
        }
    }

    @MainActor
    private func applyAudioInputRoutingParametersOnMain(_ request: AudioInputRoutingRequest) {
        guard let host = audioInputRoutingHosts[request.trackID],
              host.requestedSource == request.source,
              host.selectedChannel == request.selectedChannel
        else {
            return
        }

        host.outputBusID = request.outputBusID
        host.outputMixer.outputVolume = request.source == .silent || request.mix.isMuted ? 0 : Float(request.mix.clampedLevel)
        host.outputMixer.pan = Float(request.mix.clampedPan)

        let sendLevels = request.mix.graphSendLevels
        let routing = TrackOutputRouting(
            source: host.outputMixer,
            busID: request.outputBusID,
            sendLevels: sendLevels
        )
        let key = ObjectIdentifier(host.outputMixer)
        let currentRouting = trackOutputRoutings[key]
        trackOutputRoutings[key] = routing

        if currentRouting?.busID != request.outputBusID || currentRouting?.sendLevels != sendLevels {
            removeAudioInputCaptureTapOnMain(host: host)
            reconnectTrackOutputOnMain(routing)
            installAudioInputCaptureTapIfNeededOnMain(host: host)
        } else {
            trackSendNodes[key]?.sendA.outputVolume = sendLevels.clampedSendA
            trackSendNodes[key]?.sendB.outputVolume = sendLevels.clampedSendB
        }
    }

    @MainActor
    private func reconnectAudioInputSourceOnMain(
        host: AudioInputRoutingHost,
        requestedSource: AudioInputMonitorSource
    ) {
        removeAudioInputCaptureTapOnMain(host: host)
        if host.connectedSource == .input, !Self.simulateAudioInputConnectionForTesting {
            engine.disconnectNodeOutput(engine.inputNode)
        }
        if host.connectedSource == .loop {
            host.loopPlayer.stop()
            engine.disconnectNodeOutput(host.loopPlayer)
            host.scheduledLoopFrameCount = nil
            host.scheduledLoopChannelCount = nil
            host.scheduledLoopSampleRate = nil
        }
        engine.disconnectNodeInput(host.outputMixer)

        switch requestedSource {
        case .input:
            if Self.simulateAudioInputConnectionForTesting {
                host.connectedSource = .input
                return
            }
            guard Self.liveAudioInputAuthorized else {
                host.connectedSource = .silent
                host.outputMixer.outputVolume = 0
                return
            }
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0 else {
                host.connectedSource = .silent
                host.outputMixer.outputVolume = 0
                return
            }
            applyInputChannelMapOnMain(
                for: host.selectedChannel,
                deviceChannelCount: Int(inputFormat.channelCount)
            )
            engine.connect(engine.inputNode, to: host.outputMixer, format: engine.inputNode.inputFormat(forBus: 0))
            host.connectedSource = .input

        case .loop:
            engine.connect(host.loopPlayer, to: host.outputMixer, format: nil)
            host.connectedSource = .loop

        case .silent:
            host.connectedSource = .silent
        }
    }

    /// Select which device channels feed the input node via the input unit's
    /// channel map. Mono duplicates the chosen channel to both client
    /// channels; stereo maps the chosen pair. A default selection (stereo
    /// 1-2) clears the map. Channel-map behavior varies by device/driver —
    /// validated against real interfaces rather than unit tests.
    @MainActor
    private func applyInputChannelMapOnMain(for channel: AudioInputChannel, deviceChannelCount: Int) {
        let map: [NSNumber]?
        switch channel.normalized {
        case let .mono(deviceChannel):
            let clamped = min(deviceChannel, max(0, deviceChannelCount - 1))
            map = [NSNumber(value: clamped), NSNumber(value: clamped)]
        case let .stereo(firstChannel):
            if deviceChannelCount <= 1 {
                // Mono device: duplicate the only channel to both sides.
                map = [NSNumber(value: 0), NSNumber(value: 0)]
            } else if firstChannel == 0 {
                map = nil
            } else {
                let first = min(firstChannel, max(0, deviceChannelCount - 2))
                map = [NSNumber(value: first), NSNumber(value: first + 1)]
            }
        }
        engine.inputNode.auAudioUnit.channelMap = map
    }

    @MainActor
    private func teardownAudioInputRoutingOnMain(trackID: UUID) {
        guard let host = audioInputRoutingHosts.removeValue(forKey: trackID) else { return }

        if host.connectedSource == .input, !Self.simulateAudioInputConnectionForTesting {
            engine.disconnectNodeOutput(engine.inputNode)
        }
        removeAudioInputCaptureTapOnMain(host: host)
        host.loopPlayer.stop()
        engine.disconnectNodeOutput(host.loopPlayer)
        engine.disconnectNodeInput(host.outputMixer)
        disconnectOutput(host.outputMixer)
        detach(host.loopPlayer)
        detach(host.outputMixer)
    }

    @MainActor
    private func installAudioInputCaptureTapIfNeededOnMain(host: AudioInputRoutingHost) {
        guard audioInputCaptureHandler != nil,
              host.connectedSource != .silent,
              !host.isCaptureTapInstalled
        else {
            return
        }

        let generation = host.captureTapGeneration.increment()
        let format = host.outputMixer.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        // One tap per node: the capture tap owns the output mixer's tap slot
        // while recording is armed; the meter tap yields and returns when
        // the capture tap clears.
        removeChannelMeterTapIfInstalled(on: host.outputMixer)
        host.outputMixer.installTap(onBus: 0, bufferSize: 32, format: format) { [weak self, weak host] buffer, _ in
            guard let self,
                  let host,
                  host.captureTapGeneration.load() == generation
            else {
                return
            }
            self.audioInputCaptureHandler?(host.trackID, buffer)
        }
        host.isCaptureTapInstalled = true
    }

    @MainActor
    private func removeAudioInputCaptureTapOnMain(host: AudioInputRoutingHost) {
        guard host.isCaptureTapInstalled else { return }
        host.captureTapGeneration.increment()
        host.outputMixer.removeTap(onBus: 0)
        host.isCaptureTapInstalled = false
        // Give the meter tap its node back.
        if areChannelMeterTapsInstalled {
            removeChannelMeterTapsIfNeeded()
            installChannelMeterTapsIfNeeded()
        }
    }

    @MainActor
    private func connectionPoint(for destination: AVAudioNode) -> AVAudioConnectionPoint {
        AVAudioConnectionPoint(node: destination, bus: inputBus(for: destination))
    }

    @MainActor
    private func inputBus(for destination: AVAudioNode) -> AVAudioNodeBus {
        if let mixer = destination as? AVAudioMixerNode {
            return firstFreeInputBus(for: mixer)
        }
        return 0
    }

    @MainActor
    private func inputBus(
        for destination: AVAudioNode,
        cursor: inout [ObjectIdentifier: AVAudioNodeBus]
    ) -> AVAudioNodeBus {
        guard let mixer = destination as? AVAudioMixerNode else { return 0 }
        let key = ObjectIdentifier(mixer)
        let bus = cursor[key] ?? firstFreeInputBus(for: mixer)
        cursor[key] = bus + 1
        return bus
    }

    @MainActor
    private func firstFreeInputBus(for mixer: AVAudioMixerNode) -> AVAudioNodeBus {
        for bus in AVAudioNodeBus(0)..<AVAudioNodeBus(64) {
            if engine.inputConnectionPoint(for: mixer, inputBus: bus) == nil {
                return bus
            }
        }
        return mixer.nextAvailableInputBus
    }

    @MainActor
    private func sendNodes(for source: AVAudioNode, levels: TrackSendLevels) -> TrackSendNodes {
        let key = ObjectIdentifier(source)
        if let nodes = trackSendNodes[key] {
            nodes.sendA.outputVolume = levels.clampedSendA
            nodes.sendB.outputVolume = levels.clampedSendB
            return nodes
        }

        let nodes = TrackSendNodes(fanout: AVAudioMixerNode(), sendA: AVAudioMixerNode(), sendB: AVAudioMixerNode())
        engine.attach(nodes.fanout)
        engine.attach(nodes.sendA)
        engine.attach(nodes.sendB)
        nodes.sendA.outputVolume = levels.clampedSendA
        nodes.sendB.outputVolume = levels.clampedSendB
        trackSendNodes[key] = nodes
        return nodes
    }

    @MainActor
    private func removeTrackSendNodes(for source: AVAudioNode) {
        let key = ObjectIdentifier(source)
        guard let nodes = trackSendNodes.removeValue(forKey: key) else {
            trackOutputRoutings.removeValue(forKey: key)
            trackOutputDestinationsForTesting.removeValue(forKey: key)
            trackSendDestinationsForTesting.removeValue(forKey: key)
            return
        }
        engine.disconnectNodeOutput(nodes.fanout)
        engine.disconnectNodeOutput(nodes.sendA)
        engine.disconnectNodeOutput(nodes.sendB)
        engine.detach(nodes.fanout)
        engine.detach(nodes.sendA)
        engine.detach(nodes.sendB)
        trackOutputRoutings.removeValue(forKey: key)
        trackOutputDestinationsForTesting.removeValue(forKey: key)
        trackSendDestinationsForTesting.removeValue(forKey: key)
    }

    private func performOnMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("MainAudioGraph.performOnMain")
        debugAssertNotHoldingGraphLockForMainHop("MainAudioGraph.performOnMain")
        // realtime-allow-main-sync: graph-owner control path guarded against tick-thread use. Test: TickPathMainIsolationTests.
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    private func performOnMainThrowing(_ work: @escaping @MainActor () throws -> Void) throws {
        if Thread.isMainThread {
            try MainActor.assumeIsolated {
                try work()
            }
            return
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("MainAudioGraph.performOnMainThrowing")
        debugAssertNotHoldingGraphLockForMainHop("MainAudioGraph.performOnMainThrowing")
        var thrownError: Error?
        // realtime-allow-main-sync: throwing graph-owner control path guarded against tick-thread use. Test: TickPathMainIsolationTests.
        DispatchQueue.main.sync {
            do {
                try MainActor.assumeIsolated {
                    try work()
                }
            } catch {
                thrownError = error
            }
        }
        if let thrownError {
            throw thrownError
        }
    }

    private func performOnMainReturning<T>(_ work: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                work()
            }
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("MainAudioGraph.performOnMainReturning")
        debugAssertNotHoldingGraphLockForMainHop("MainAudioGraph.performOnMainReturning")
        var output: T?
        // realtime-allow-main-sync: graph-owner read/control path guarded against tick-thread use. Test: TickPathMainIsolationTests.
        DispatchQueue.main.sync {
            output = MainActor.assumeIsolated {
                work()
            }
        }
        return output!
    }

    private func performOnMainThrowingReturning<T>(_ work: @escaping @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try work()
            }
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("MainAudioGraph.performOnMainThrowingReturning")
        debugAssertNotHoldingGraphLockForMainHop("MainAudioGraph.performOnMainThrowingReturning")
        var output: T?
        var thrownError: Error?
        // realtime-allow-main-sync: throwing graph-owner read/control path guarded against tick-thread use. Test: TickPathMainIsolationTests.
        DispatchQueue.main.sync {
            do {
                output = try MainActor.assumeIsolated {
                    try work()
                }
            } catch {
                thrownError = error
            }
        }
        if let thrownError {
            throw thrownError
        }
        return output!
    }
}

enum MasterMeterTapPoint: Equatable {
    case finalOutputMixer
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension TrackMixSettings {
    var graphSendLevels: MainAudioGraph.TrackSendLevels {
        MainAudioGraph.TrackSendLevels(sendA: sendA, sendB: sendB)
    }
}

struct MasterMeterDisplayState: Equatable {
    static let silenceDBFS = -Double.infinity
    static let displayFloorDBFS = -60.0
    static let silent = MasterMeterDisplayState(
        leftPeakDBFS: silenceDBFS,
        rightPeakDBFS: silenceDBFS,
        leftPeakHoldDBFS: silenceDBFS,
        rightPeakHoldDBFS: silenceDBFS,
        isClipLatched: false
    )

    var leftPeakDBFS: Double
    var rightPeakDBFS: Double
    var leftPeakHoldDBFS: Double
    var rightPeakHoldDBFS: Double
    var isClipLatched: Bool
    var isClearClipActionable: Bool { isClipLatched }
}

@Observable
final class MasterMeterPublisher {
    private(set) var displayState: MasterMeterDisplayState = .silent

    @ObservationIgnored private let transport = MasterMeterTransport()
    @ObservationIgnored private let peakHoldDuration: TimeInterval
    @ObservationIgnored private let peakHoldReleaseDBPerSecond: Double
    @ObservationIgnored private let levelReleaseDBPerSecond: Double
    @ObservationIgnored private var lastPublishTime: TimeInterval?
    @ObservationIgnored private var leftPeakHoldTime: TimeInterval = 0
    @ObservationIgnored private var rightPeakHoldTime: TimeInterval = 0

    // NOTE: this publisher owns NO timer. All publishers — channel strips
    // and the master — are pumped by ChannelMeterBank's single main-queue
    // timer (the master registers itself via
    // `ChannelMeterBank.registerAuxiliaryPublisher`). One pump, one cadence,
    // publish-outside-locks (abstraction audit F6).
    init(
        peakHoldDuration: TimeInterval = 0.75,
        peakHoldReleaseDBPerSecond: Double = 18,
        levelReleaseDBPerSecond: Double = 42
    ) {
        self.peakHoldDuration = peakHoldDuration
        self.peakHoldReleaseDBPerSecond = peakHoldReleaseDBPerSecond
        self.levelReleaseDBPerSecond = levelReleaseDBPerSecond
    }

    func process(buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else {
            recordPeakAmplitudes(left: 0, right: 0)
            return
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            recordPeakAmplitudes(left: 0, right: 0)
            return
        }

        let left = Self.peakAmplitude(channel: channels[0], frameCount: frameCount)
        let right = channelCount > 1
            ? Self.peakAmplitude(channel: channels[1], frameCount: frameCount)
            : left
        recordPeakAmplitudes(left: left, right: right)
    }

    func recordPeakAmplitudes(left: Double, right: Double) {
        transport.store(left: left, right: right)
    }

    func publishPendingToMain(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard Thread.isMainThread else {
            // realtime-allow-main-async: UI-only meter publication, not event scheduling. Test: RealtimePathLintTests.
            DispatchQueue.main.async { [weak self] in
                self?.publishPendingToMain()
            }
            return
        }

        let snapshot = transport.snapshot()
        let leftLivePeak = Self.dbFS(amplitude: snapshot.left)
        let rightLivePeak = Self.dbFS(amplitude: snapshot.right)
        let elapsed = max(0, now - (lastPublishTime ?? now))
        lastPublishTime = now
        let leftPeak = nextDisplayedPeak(
            currentPeak: displayState.leftPeakDBFS,
            livePeak: leftLivePeak,
            elapsed: elapsed
        )
        let rightPeak = nextDisplayedPeak(
            currentPeak: displayState.rightPeakDBFS,
            livePeak: rightLivePeak,
            elapsed: elapsed
        )

        let leftHold = nextPeakHold(
            currentHold: displayState.leftPeakHoldDBFS,
            holdTime: &leftPeakHoldTime,
            livePeak: leftPeak,
            now: now,
            elapsed: elapsed
        )
        let rightHold = nextPeakHold(
            currentHold: displayState.rightPeakHoldDBFS,
            holdTime: &rightPeakHoldTime,
            livePeak: rightPeak,
            now: now,
            elapsed: elapsed
        )

        let nextState = MasterMeterDisplayState(
            leftPeakDBFS: leftPeak,
            rightPeakDBFS: rightPeak,
            leftPeakHoldDBFS: leftHold,
            rightPeakHoldDBFS: rightHold,
            isClipLatched: displayState.isClipLatched || snapshot.isClipped
        )
        // Skip the no-op assignment: with one publisher per mixer strip, an
        // unconditional 60Hz write would re-render every visible strip even
        // when its meter sits silent.
        if nextState != displayState {
            displayState = nextState
        }
    }

    func clearClip() {
        transport.clearClip()
        guard Thread.isMainThread else {
            // realtime-allow-main-async: UI-only meter clip-latch publication, not event scheduling. Test: RealtimePathLintTests.
            DispatchQueue.main.async { [weak self] in
                self?.clearClip()
            }
            return
        }
        displayState.isClipLatched = false
    }

    /// Snaps the meter to silence immediately (no release envelope) — used
    /// when the transport stops so frozen peaks drop to zero at once instead
    /// of decaying. The clip latch is preserved (clearing it is a separate
    /// user action). Safe on any thread; the @Observable mutation hops to
    /// main, matching `clearClip()`/`publishPendingToMain()`.
    func resetToSilence() {
        _ = transport.snapshot() // drain any pending peaks
        guard Thread.isMainThread else {
            // realtime-allow-main-async: UI-only meter reset publication, not event scheduling. Test: RealtimePathLintTests.
            DispatchQueue.main.async { [weak self] in
                self?.resetToSilence()
            }
            return
        }
        let cleared = MasterMeterDisplayState(
            leftPeakDBFS: MasterMeterDisplayState.silenceDBFS,
            rightPeakDBFS: MasterMeterDisplayState.silenceDBFS,
            leftPeakHoldDBFS: MasterMeterDisplayState.silenceDBFS,
            rightPeakHoldDBFS: MasterMeterDisplayState.silenceDBFS,
            isClipLatched: displayState.isClipLatched
        )
        if cleared != displayState {
            displayState = cleared
        }
    }

    static func dbFS(amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else {
            return MasterMeterDisplayState.silenceDBFS
        }
        return 20 * log10(amplitude)
    }

    private static func peakAmplitude(channel: UnsafePointer<Float>, frameCount: Int) -> Double {
        var peak: Float = 0
        for frame in 0..<frameCount {
            peak = max(peak, abs(channel[frame]))
        }
        return Double(peak)
    }

    private func nextPeakHold(
        currentHold: Double,
        holdTime: inout TimeInterval,
        livePeak: Double,
        now: TimeInterval,
        elapsed: TimeInterval
    ) -> Double {
        if !currentHold.isFinite || livePeak >= currentHold {
            holdTime = now
            return livePeak
        }

        guard now - holdTime >= peakHoldDuration else {
            return currentHold
        }

        let released = currentHold - peakHoldReleaseDBPerSecond * elapsed
        return max(livePeak, released)
    }

    private func nextDisplayedPeak(
        currentPeak: Double,
        livePeak: Double,
        elapsed: TimeInterval
    ) -> Double {
        guard currentPeak.isFinite else { return livePeak }
        guard livePeak.isFinite else {
            let released = currentPeak - levelReleaseDBPerSecond * elapsed
            return released <= MasterMeterDisplayState.displayFloorDBFS ? MasterMeterDisplayState.silenceDBFS : released
        }
        guard livePeak < currentPeak else { return livePeak }
        return max(livePeak, currentPeak - levelReleaseDBPerSecond * elapsed)
    }
}

private final class MasterMeterTransport {
    private static let zeroAmplitudeBits = Int64(bitPattern: 0.0.bitPattern)

    private let leftBits = AtomicInt64(Int64(bitPattern: 0.0.bitPattern))
    private let rightBits = AtomicInt64(Int64(bitPattern: 0.0.bitPattern))
    private let clipped = AtomicInt32(0)

    func store(left: Double, right: Double) {
        let safeLeft = Self.safeAmplitude(left)
        let safeRight = Self.safeAmplitude(right)
        leftBits.storeMaximum(Self.amplitudeBits(safeLeft), shouldReplace: Self.shouldReplaceAmplitude)
        rightBits.storeMaximum(Self.amplitudeBits(safeRight), shouldReplace: Self.shouldReplaceAmplitude)
        if safeLeft > 1 || safeRight > 1 {
            clipped.store(1)
        }
    }

    func snapshot() -> (left: Double, right: Double, isClipped: Bool) {
        (
            left: Self.amplitude(fromBits: leftBits.exchange(Self.zeroAmplitudeBits)),
            right: Self.amplitude(fromBits: rightBits.exchange(Self.zeroAmplitudeBits)),
            isClipped: clipped.load() != 0
        )
    }

    func clearClip() {
        clipped.store(0)
    }

    private static func safeAmplitude(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }

    private static func amplitudeBits(_ value: Double) -> Int64 {
        Int64(bitPattern: value.bitPattern)
    }

    private static func amplitude(fromBits bits: Int64) -> Double {
        Double(bitPattern: UInt64(bitPattern: bits))
    }

    private static func shouldReplaceAmplitude(stored: Int64, next: Int64) -> Bool {
        amplitude(fromBits: stored) < amplitude(fromBits: next)
    }
}
