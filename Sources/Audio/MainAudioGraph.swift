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
    /// Counts live single-track output edits that took the ramp-to-silence
    /// path (engine running + sounding mixer-node gain stage). Lets the
    /// ramp-before-disconnect tests assert the click-safe path was exercised.
    private(set) var rampedReconnectCountForTesting = 0
    /// Counts steady-state (send nodes already exist) send-level applies that
    /// took the glitch-free gain RAMP path (vs an immediate setup write). Lets
    /// R4 tests assert a live A/A+B/B switch ramps the send gains rather than
    /// hard-jumping (a click on the aux bus) — and that it does NOT reconnect.
    private(set) var sendRampCountForTesting = 0
    /// Calibration-only: when true the ramp-before-disconnect guard is bypassed
    /// (old hard-disconnect path) so the click metric can be measured against a
    /// known-clicking control. Driven by SEQUENCER_AI_DISABLE_ROUTING_RAMP=1.
    static let disableRoutingRampForCalibration =
        ProcessInfo.processInfo.environment["SEQUENCER_AI_DISABLE_ROUTING_RAMP"] == "1"
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
    private var retiredTrackSendNodes: [TrackSendNodes] = []
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
        // TEARDOWN MUST NEVER BLOCK (bug 20260702-140500). Deinit runs on
        // whatever thread drops the last strong reference — sampled in the
        // wild on CoreAudio's `RealtimeMessenger.mServiceQueue` itself, when
        // the master meter tap callback's `guard let self` upgrade turned out
        // to be the final reference. That thread performs pending tap messages
        // while HOLDING the messenger's recursive mutex, so the old
        // `performOnMain { removeMasterMeterTapIfNeeded() }` (a synchronous
        // main hop) deadlocked against any OTHER graph deinit already on main
        // inside `removeTapOnBus` → `_PerformPendingMessages()` waiting for
        // that same mutex — a cross-graph ABBA deadlock that wedged the whole
        // process (the long-standing ~990 s test-host stalls).
        //
        // So: silence the tap callbacks immediately (the closures check the
        // generation before touching the publishers), then hand the actual
        // `removeTap` calls to main ASYNCHRONOUSLY. The closure captures keep
        // the engine and tapped nodes alive until the removal has run, and
        // the deallocating thread never waits on anyone.
        masterMeterTapGeneration.increment()
        channelMeterTapGeneration.increment()
        let engine = self.engine
        let masterTapNode = isMasterMeterTapInstalled ? finalOutputMixer : nil
        let channelTapNodes = Array(channelMeterTappedNodes.values)
        guard masterTapNode != nil || !channelTapNodes.isEmpty else { return }
        // realtime-allow-main-async: graph deinit teardown control path (never tick dispatch); a SYNC hop here deadlocked against the RealtimeMessenger service queue. Test: MainAudioGraphTests.
        DispatchQueue.main.async {
            if let masterTapNode {
                masterTapNode.removeTap(onBus: 0)
            }
            for node in channelTapNodes {
                _ = SEQRunCatchingObjCException {
                    node.removeTap(onBus: 0)
                }
            }
            // Keep the engine alive until its taps are gone: removing a tap
            // from a node whose engine already deallocated is the other half
            // of this hang class.
            _ = engine
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
            // A node's channel-meter tap MUST come off before its topology is
            // mutated. `disconnectNodeOutput` reconfigures the affected subgraph
            // (`AVAudioEngineGraph::UpdateGraphAfterReconfig`); doing so while a
            // tap is still live on the node faults inside AVFAudio (the
            // QA-fixture EXC_BAD_ACCESS at UpdateGraphAfterReconfig,
            // 20260703-0907-setTrackOutputBus-disconnect-segfault). `detach`
            // already follows this discipline (it calls the same remove before
            // its disconnect); the prepared-track repair and track-teardown
            // paths route the track's registered METER-SOURCE node through here,
            // so mirror it. Re-registration (`setTrackMeterSources`, run on the
            // next prepare/apply) re-taps a surviving track after the rebuild;
            // bus/send meter taps do not flow through here (they disconnect via
            // `reconnectMixerBusTerminalsOnMain` → `engine.disconnectNodeOutput`).
            self.removeChannelMeterTapIfInstalled(on: node)
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
            // See `disconnectOutput`: never reconfigure a node whose meter tap is
            // still live (UpdateGraphAfterReconfig fault). The prepared-track
            // repair disconnects voice-filter / mixer INPUTS through here; drop
            // any tap first — re-registered after the rebuild.
            self.removeChannelMeterTapIfInstalled(on: node)
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

    /// The current audio-render position, as the unified master clock's origin
    /// (Audio Engine Hard Rule 1). Reads the render `sampleTime` from the
    /// engine itself — NEVER a wall clock:
    ///
    /// - **Offline manual-rendering mode** (the deterministic gate / automation
    ///   path): `engine.manualRenderingSampleTime` is the exact frame the next
    ///   `renderOffline` will produce. There is no live `hostTime`, so we pair
    ///   it with `mach_absolute_time()` purely as a *correlation* stamp (the
    ///   musical-time math never depends on it offline — `sampleTime` is the
    ///   sole source of truth, which is what makes the offline gate exact).
    /// - **Live HAL mode:** the output node's `lastRenderTime` carries the
    ///   device render position as a monotonic `sampleTime` (+ matching
    ///   `hostTime`). Before the first render (or if the node has not produced a
    ///   valid render time yet) this returns nil and the clock falls back to its
    ///   musical-time accumulator.
    ///
    /// Returns nil when no render position is available yet; the caller must
    /// treat that as "origin not yet established".
    ///
    /// This is a pure READ of engine state — no allocation, no locks, no graph
    /// mutation — so it is safe to call from the lookahead pump (Rule 6: it adds
    /// no work to the render thread itself; the pump runs off it).
    var renderPosition: (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)? {
        if engine.isInManualRenderingMode {
            let rate = engine.manualRenderingFormat.sampleRate
            guard rate > 0 else { return nil }
            return (engine.manualRenderingSampleTime, mach_absolute_time(), rate)
        }
        guard let renderTime = engine.outputNode.lastRenderTime,
              renderTime.isSampleTimeValid
        else {
            return nil
        }
        let rate = renderTime.sampleRate > 0
            ? renderTime.sampleRate
            : engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0 else { return nil }
        let hostTime = renderTime.isHostTimeValid ? renderTime.hostTime : mach_absolute_time()
        return (renderTime.sampleTime, hostTime, rate)
    }

    /// True when `node` can be started right now: the engine is running and
    /// the node is still attached and connected. AVAudioPlayerNode.play()
    /// throws an uncatchable NSException for a detached/disconnected node
    /// even on a running engine (seen when a document re-apply tears voices
    /// down while a queued play closure is in flight).
    func isNodePlayableNow(_ node: AVAudioNode) -> Bool {
        (engine.isRunning || engine.isInManualRenderingMode)
            && node.engine === engine
            && !engine.outputConnectionPoints(for: node, outputBus: 0).isEmpty
    }

    /// Count of `engine.inputNode` accesses made through this graph. Accessing
    /// the input node is never free: AVAudioEngine shares ONE HAL IO unit
    /// between input and output, and the first `inputNode` access permanently
    /// arms `EnableIO` on the unit's input scope — every later `engine.start()`
    /// then opens a microphone stream and becomes a mic-TCC trigger. On ad-hoc
    /// signed debug builds the prompt re-fires after every rebuild even while
    /// `AVCaptureDevice.authorizationStatus` still reports `.authorized`
    /// (stale TCC record), and since the warm-graph change the session start
    /// happens at document open — so a stray access here turns into a
    /// launch-blocking mic prompt. Sample-only sessions must keep this at 0.
    private(set) var inputNodeAccessCountForTesting = 0

    /// The ONLY sanctioned door to `engine.inputNode`. Callers must already be
    /// on an armed audio-input path (a routing whose requested source is
    /// `.input`), so the mic-TCC prompt can only fire at the moment of user
    /// intent — never at sample-only graph construction/start.
    @MainActor
    private func armedEngineInputNode() -> AVAudioInputNode {
        inputNodeAccessCountForTesting += 1
        return engine.inputNode
    }

    /// True when a live `.input` monitor connection must be SIMULATED instead
    /// of wired through `engine.inputNode`. Two cases:
    ///
    /// - Unit tests (`simulateAudioInputConnectionForTesting`) — real input
    ///   access risks the mic-TCC prompt and CoreAudio stalls.
    /// - OFFLINE MANUAL-RENDERING engines (the QA/visual-automation force):
    ///   an offline engine has no HAL IO unit, so `engine.inputNode` has no
    ///   underlying audio unit. Wiring it in "works" until the host is torn
    ///   down and the engine restarts — the input node is then left in the
    ///   engine's node set with a NULL AUInterface, and the NEXT
    ///   running-engine disconnect's `UpdateGraphAfterReconfig` walk makes a
    ///   virtual call through that null interface: the record-arm SIGSEGV at
    ///   `KERN_INVALID_ADDRESS 0x68` (bug 20260702-123512). This slipped the
    ///   "automation never instantiates the input IO unit" invariant because
    ///   a stale-authorized TCC record makes `liveAudioInputAuthorized` true
    ///   on rebuilt ad-hoc binaries. Automation fixtures inject capture
    ///   buffers directly, so nothing offline needs the real input edge.
    private var simulatesLiveInputConnection: Bool {
        Self.simulateAudioInputConnectionForTesting || engine.isInManualRenderingMode
    }

    /// Test seam for the HAL default-input-device channel-count read.
    static var hardwareInputChannelCountOverrideForTesting: Int?

    /// Device input channel count for UI affordances (input selector,
    /// arm-availability messaging). Read from the HAL default input device's
    /// stream configuration — a plain CoreAudio property read with no TCC side
    /// effects. This must NEVER go through `engine.inputNode`: documents that
    /// merely CONTAIN an audio-input track compute route state through here at
    /// document apply, and an `inputNode` read would arm the shared IO unit's
    /// input scope (see `inputNodeAccessCountForTesting`) — on a rebuilt
    /// ad-hoc binary the TCC status is stale-`.authorized`, so that single
    /// read turned the warm session start into a launch-blocking mic prompt.
    var availableInputChannelCount: Int {
        guard Self.liveAudioInputAuthorized else { return 0 }
        if let override = Self.hardwareInputChannelCountOverrideForTesting {
            return max(0, override)
        }
        return CoreAudioDeviceCatalog().defaultInputDeviceChannelCount()
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
                // routing-lint-allow: setAudioInputRouting full-rebuild fallback (HAL renegotiation)
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
                // routing-lint-allow: setAudioInputRouting full-rebuild fallback (HAL renegotiation)
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

    /// - Parameter ramped: when `true` (the default — the LIVE single-track
    ///   reroute path), the splice runs under a ramp-to-silence dip so a SOUNDING
    ///   node is never hard-disconnected (Hard Rule 5). Pass `false` for the
    ///   SETUP / REPAIR / REBUILD path (prepared-track build, `repairTrackMixer-
    ///   Output`): the track's new voices are not yet sounding through this graph,
    ///   so there is nothing to click — and the dip is actively harmful there.
    ///   A rebuild issues several `connectTrackOutput`s in quick succession; if
    ///   each took the ~12 ms deferred dip, the overlapping deferred reconnects
    ///   race on the same fanout and can leave the filter disconnected from it
    ///   (the intermittent drum-part-add / route-to-master silence,
    ///   docs/bugs/20260626-route-to-master-intermittent-silence). The synchronous
    ///   splice lands the connection immediately and deterministically.
    func connectTrackOutput(
        _ source: AVAudioNode,
        to busID: UUID?,
        sends sendLevels: TrackSendLevels = .zero,
        ramped: Bool = true
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
            // Ramp-to-silence before the disconnect (R1 click fix): if the
            // track is sounding and the engine is live, the gain stage is
            // ramped to 0, the splice happens on silence, then it ramps back —
            // so a live bus reassign no longer hard-cuts a playing node.
            let routing = TrackOutputRouting(source: source, busID: busID, sendLevels: sendLevels)
            self.trackOutputRoutings[ObjectIdentifier(source)] = routing
            // The synchronous splice (reconnectTrackOutputOnMain) unconditionally
            // disconnects the track's SHARED per-track fanout. The fanout is
            // shared across ALL the track's voices, so even on a setup/repair
            // triggered by ONE voice, a SIBLING voice may still be sustaining a
            // sample through it. Hard-disconnecting a fanout that is currently
            // passing a sibling's audio is a Hard Rule 5 hard-cut (click).
            //
            // Guard: take the synchronous (un-ramped) path ONLY when the gain
            // stage is genuinely not passing audio — engine not running, OR the
            // gain stage has no live output edge yet (a fresh build, nothing
            // sounding). If the fanout already has an output connection while the
            // engine runs (a sibling could be sounding), PROMOTE to the ramped
            // path so the splice lands on silence. This keeps the silence fix
            // intact (the overlapping-dip race is independently solved by the
            // settled-target restore) while never hard-cutting a sounding sibling.
            let canSpliceSynchronously: Bool = {
                if ramped { return false }
                guard self.engine.isRunning else { return true }
                guard let gainStage = self.trackGainStage(for: source) else { return true }
                // A sibling voice can only be PASSING audio through the fanout if
                // the fanout is fed (has a live INPUT edge) AND has a downstream
                // OUTPUT edge. A fanout with an output edge but no input (the
                // common repair case: the filter→fanout INPUT is exactly what we
                // are re-wiring) is silent → the synchronous splice is safe.
                let inputConnected = self.engine.inputConnectionPoint(for: gainStage, inputBus: 0) != nil
                let outputConnected = !self.engine.outputConnectionPoints(for: gainStage, outputBus: 0).isEmpty
                return !(inputConnected && outputConnected)
            }()
            if canSpliceSynchronously {
                // Setup/repair/rebuild with nothing sounding through the fanout:
                // splice synchronously (no dip). The connection lands immediately
                // and deterministically, avoiding the overlapping-deferred race.
                self.reconnectTrackOutputOnMain(routing)
            } else {
                // Live single-track reroute, OR a setup/repair where a sibling
                // voice may still be sounding through the shared fanout: ramp the
                // gain stage to silence first so no sounding node is hard-cut.
                self.reconnectTrackOutputRampedOnMain(routing)
            }
        }
    }

    /// Connect a prepared sample voice mixer to a mixer bus's input mixer.
    ///
    /// The bus input mixer SUMS every routed track's voices, so each connecting
    /// voice mixer must land on a UNIQUE free input bus across the WHOLE bus —
    /// never a per-track 0..N index. A 4-part kit routed to one bus is 4 tracks ×
    /// 4 voices = 16 connections; if each track reused input buses 0..3 the
    /// later connections would overwrite the earlier ones and only one part would
    /// reach the bus (docs/bugs/20260626-route-track-to-mixer-bus-goes-silent,
    /// multi-track collision). `firstFreeInputBus` scans the live mixer and
    /// returns the lowest unused input, so re-routes that freed buses (teardown
    /// disconnects the voice mixers) re-fill the gaps without leaking.
    ///
    /// It also (re)asserts the bus terminal -> preMaster edge: AVAudioEngine
    /// silently drops the output connection of a mixer that has no inputs, so
    /// the bus-output edge wired at install time (before any track fed the bus)
    /// never stuck. We re-establish it here, now that the bus has at least one
    /// input, so the chain voice -> voiceMixer -> busInputMixer -> preMaster is
    /// actually live (same bug, single-track silence).
    func connectPreparedSampleVoiceOutput(
        _ source: AVAudioNode,
        toMixerBus busID: UUID
    ) {
        TickPathMainSyncGuard.assertNotHoldingLifecycleLockForGraphMutation("MainAudioGraph.connectPreparedSampleVoiceOutput")
        performOnMain {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard source.engine === self.engine,
                  let destinationMixer = self.mixerBusHosts[busID]?.destinationNode()
            else {
                return
            }
            // realtime-allow-graph-mutation: prepared sample bus-safe route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
            self.engine.disconnectNodeOutput(source)
            // realtime-allow-graph-mutation: prepared sample bus-safe route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
            self.engine.connect(
                source,
                to: destinationMixer,
                fromBus: 0,
                toBus: self.inputBus(for: destinationMixer),
                format: nil
            )
            self.trackOutputDestinationsForTesting[ObjectIdentifier(source)] = destinationMixer
            // The bus now has at least one input — (re)assert its output edge to
            // preMaster so the routed signal actually reaches master.
            self.ensureMixerBusTerminalReachesPreMasterOnMain(busID: busID)
            // The bus input mixer only acquires a resolvable output format once
            // it has at least one input + a live output edge. Its per-bus meter
            // tap (installed at graph-build time on the then-formatless mixer)
            // never captured (bus<N>Peak = -inf even with signal, #59). Install
            // the bus meter tap HERE on the now-formatted summing node — a single
            // targeted install, idempotent (no-op if already tapped), NOT a
            // remove-all + reinstall-all thrash on every routed voice (that was
            // the #61 route-to-bus click suspect AND was ineffective at making
            // the bus read). Read-only observer — does not touch the audio path.
            self.installBusMeterTapIfNeeded(busID: busID, on: destinationMixer)
        }
    }

    /// (Re)connect a mixer bus's terminal node to preMaster if that output edge
    /// is missing. Safe to call repeatedly — it no-ops when the terminal already
    /// reaches preMaster. Needed because a bus input mixer with zero inputs has
    /// no resolvable output format, so AVAudioEngine drops the terminal ->
    /// preMaster connection made at install time; the edge must be (re)made once
    /// the bus has a producer.
    /// Returns true when it actually (re)made the terminal -> preMaster edge
    /// (i.e. the edge was missing), false when it was already live.
    @MainActor
    @discardableResult
    private func ensureMixerBusTerminalReachesPreMasterOnMain(busID: UUID) -> Bool {
        guard let readout = mixerBusHosts[busID]?.readout() else { return false }
        let terminal = readout.terminalSourceNode ?? readout.inputMixer
        guard terminal.engine === engine else { return false }
        let reachesPreMaster = engine.outputConnectionPoints(for: terminal, outputBus: 0)
            .contains { $0.node === preMasterMixer }
        guard !reachesPreMaster else { return false }
        // realtime-allow-graph-mutation: prepared route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
        engine.disconnectNodeOutput(terminal)
        // realtime-allow-graph-mutation: prepared route setup/repair only, not event scheduling. Test: RealtimePathLintTests.
        engine.connect(
            terminal,
            to: preMasterMixer,
            fromBus: 0,
            toBus: firstFreeInputBus(for: preMasterMixer),
            format: nil
        )
        return true
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
        //
        // Ramp-to-silence (R2 click fix): host.rebuild disconnects the live
        // chain nodes, which on a sounding track would hard-cut the signal mid
        // sample. So the rebuild AND the reconnect both run inside the gain-stage
        // ramp-to-silence guard — the whole edit lands on silence, then the gain
        // ramps back. When the engine is stopped / track is silent this is the
        // plain synchronous path (no behaviour change for setup/tests).
        let routing = self.trackOutputRoutings[ObjectIdentifier(source)]
        self.withTrackGainRampedToSilence(source: source) {
            host.rebuild(inserts: inserts, in: self)
            if let routing {
                self.reconnectTrackOutputOnMain(routing)
            }
            self.installMasterMeterTapIfNeeded()
        }
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

    /// Count of FX insert NODES actually installed in the live graph for a track
    /// (engine-truth), as distinct from the authored `track.fxInserts.count`.
    /// 0 when the track has no chain host. The routing-stress gate asserts this
    /// against the requested op so a parse-only command (no real install) fails.
    func trackInstalledInsertNodeCountForTesting(trackID: UUID) -> Int {
        performOnMainReturning {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.trackInsertChainHosts[trackID]?.installedInsertNodeCountForTesting ?? 0
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
            // crossing zero in either direction — is a pure gain change with no
            // live disconnect/reconnect; they are torn down only when the track
            // is removed. If they do not exist yet (send buses not installed),
            // establish the geometry once.
            guard let nodes = self.trackSendNodes[key] else {
                // First-time setup: the send nodes are brand-new and not yet
                // sounding (reconnectTrackOutputOnMain attaches them), so the
                // initial gain is a setup write, NOT a ramp — ramping from a
                // default would be wrong here.
                self.reconnectTrackOutputOnMain(routing)
                return
            }
            // R4 (steady-state live switch): the send nodes already exist and
            // may be sounding (e.g. an A/A+B/B scene-send switch on a playing
            // track). Hard-writing outputVolume here hard-jumps the send gain =
            // a click on the aux bus. RAMP it instead. This is pure gain — NO
            // attach/detach/connect/disconnect, NO topology change, NO reconnect
            // (rampedReconnectCountForTesting stays flat).
            self.sendRampCountForTesting += 1
            MixerGainRamp.shared.ramp(nodes.sendA, to: sendLevels.clampedSendA)
            MixerGainRamp.shared.ramp(nodes.sendB, to: sendLevels.clampedSendB)
        }
    }

    /// TICK-SAFE send-leg gain ramp for the #58 mute path. Unlike
    /// `setTrackSendLevels` (which does a synchronous main hop to (re)establish
    /// send geometry the first time), this NEVER hops to main and NEVER mutates
    /// the graph: it only reads the already-established per-track send nodes
    /// under `graphLock` (a leaf lock) and kicks a `MixerGainRamp` (which writes
    /// `outputVolume` on its own background queue). Safe from the tick path —
    /// the perform-LAYER mute (`setTrackMuteGain(source: .layer)`) calls into
    /// here. If the send nodes are not established yet (no fanout / send buses
    /// not installed), this is a no-op: the mixer path applies the gated levels
    /// through the full `setTrackSendLevels` setup on the next pass.
    ///
    /// `sendA`/`sendB` are the levels to ramp the send legs to (already gated by
    /// effective mute by the caller: 0 while muted, the configured level when
    /// unmuted). The node's recorded steady-state target is NOT overwritten
    /// (`markSettled: false`) — a mute is a transient gain dip over the
    /// configured send level, exactly like the dry mute does not overwrite the
    /// fader's settled level.
    func rampExistingTrackSendLegsForMute(_ source: AVAudioNode, sendA: Double, sendB: Double) {
        let key = ObjectIdentifier(source)
        let nodes: TrackSendNodes? = {
            lockGraphLock()
            defer { unlockGraphLock() }
            return trackSendNodes[key]
        }()
        guard let nodes else { return }
        let levels = TrackSendLevels(sendA: sendA, sendB: sendB)
        MixerGainRamp.shared.ramp(nodes.sendA, to: levels.clampedSendA, markSettled: false)
        MixerGainRamp.shared.ramp(nodes.sendB, to: levels.clampedSendB, markSettled: false)
    }

    func start() throws {
        try performOnMainThrowing {
            guard !self.isStarted || !self.engine.isRunning else { return }
            self.installMasterMeterTapIfNeeded()
            self.channelMeterBank.startPublishing()
            // routing-lint-allow: transport start() (engine lifecycle, not a routing edit)
            try self.engine.start()
            self.isStarted = true
        }
    }

    func stop() {
        performOnMain {
            self.removeMasterMeterTapIfNeeded()
            self.channelMeterBank.stopPublishing()
            guard self.isStarted || self.engine.isRunning else { return }
            // routing-lint-allow: transport stop() (engine lifecycle, not a routing edit)
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
            // Lazy input arming: the device owner's input-direction unit is an
            // input-ENABLED AUHAL, and creating/initializing one is a mic-TCC
            // trigger. Re-applying a stored device preference at document open
            // therefore raised the microphone prompt at launch with zero user
            // intent (launch-blocking on ad-hoc rebuilds, where the stale TCC
            // grant re-prompts). Until an audio-input routing is actually armed
            // (requested source `.input`), the input selection is only RECORDED
            // (`deferredInputDeviceUID` in the result, so preference persistence
            // keeps it) and never applied to the HAL. Nothing audible is lost:
            // the engine's live input follows the system-default input device
            // regardless (see the NOTE below about engine.inputNode).
            // `audioInputRoutingHosts` mutates on main only, and this closure
            // runs on main, so the read needs no graphLock.
            let inputSideArmed = self.audioInputRoutingHosts.values.contains {
                $0.requestedSource == .input
            }
            let effectiveInputUID = inputSideArmed ? inputUID : nil
            let deferredInputUID = inputSideArmed ? nil : inputUID
            let previousInputUID = inputSideArmed
                ? deviceOwner.activeDeviceUID(direction: .input)
                : nil
            let previousOutputUID = deviceOwner.activeDeviceUID(direction: .output)
            let wasRunning = self.engine.isRunning || self.isStarted

            self.removeMasterMeterTapIfNeeded()
            if self.engine.isRunning {
                // routing-lint-allow: applyAudioDeviceUIDs device-change recovery (HAL renegotiation)
                self.engine.stop()
            }

            do {
                let deviceResult = try deviceOwner.apply(inputUID: effectiveInputUID, outputUID: outputUID)
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
                    restartedEngine: wasRunning && self.engine.isRunning,
                    deferredInputDeviceUID: deferredInputUID
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
                // NOTE: a LIVE stop() here resets the output node's render
                // timeline on the HAL; the unified master clock detects the
                // reset and rebases its frame origin
                // (AudioMasterClock.rebaseFrameOriginIfRenderTimelineReset) so
                // AU note stamps stay schedulable (the scene-FX AU-attenuation
                // bug, docs/bugs/20260702-143000).
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "installMasterChains STOP live engine for master-chain rebuild chains=\(chains.count) postBlendNodes=\(postBlendMasterNodes.count)"
                )
                // routing-lint-allow: installMasterChains one-time master-chain topology setup
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
                // routing-lint-allow: installMasterChains one-time master-chain topology setup
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "installMasterChains RESTART live engine after master-chain rebuild running=\(self.engine.isRunning)"
                )
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

    /// True when the bus's terminal node has a LIVE output edge that reaches
    /// preMaster (i.e. the bus->master leg is actually wired in the engine, not
    /// just recorded as intent on the host). The fast-path gate checks this so a
    /// bus whose output edge was silently dropped (mixer-with-no-inputs, see
    /// `ensureMixerBusTerminalReachesPreMasterOnMain`) cannot pass the gate and
    /// play into a dead-end.
    func mixerBusTerminalReachesPreMaster(busID: UUID) -> Bool {
        return performOnMainReturning {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            guard let readout = self.mixerBusHosts[busID]?.readout() else { return false }
            let terminal = readout.terminalSourceNode ?? readout.inputMixer
            guard terminal.engine === self.engine else { return false }
            return self.engine.outputConnectionPoints(for: terminal, outputBus: 0)
                .contains { $0.node === self.preMasterMixer }
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

    /// Test accessor for the per-track gain stage (the fanout for sample/native
    /// tracks) that the ramp-to-silence path dips. Used by the overlapping-splice
    /// restore-level regression test.
    @MainActor
    func trackGainStageForTesting(_ source: AVAudioNode) -> AVAudioMixerNode? {
        trackGainStage(for: source)
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

    /// The node currently registered as a track's meter source (the node whose
    /// output the track strip meters). Lets a test assert that a bus-routed track
    /// meters its OWN pre-bus output rather than following the bus (#62).
    func trackMeterSourceNodeForTesting(trackID: UUID) -> AVAudioNode? {
        performOnMainReturning {
            self.lockGraphLock()
            defer { self.unlockGraphLock() }
            return self.trackMeterSources[trackID]
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

    /// Install the per-bus meter tap on a bus's summing node once it has a
    /// resolvable (formatted) output — i.e. when a routed track first wires a
    /// voice into it. The general `installChannelMeterTapsIfNeeded` registers the
    /// bus node at graph-build time, but the bus input mixer is FORMATLESS then
    /// (no inputs), so that tap never captures (bus<N>Peak = -inf despite signal,
    /// #59). This targeted installer re-attaches just the bus tap on the live,
    /// summed node — capturing the SUM of every track routed to the bus — without
    /// the remove-all + reinstall-all thrash that glitched the render on a route
    /// (#61). It is idempotent: a no-op if the node is already tapped, and only
    /// runs while channel meter taps are active (so it tracks the same lifecycle
    /// as the bank).
    @MainActor
    private func installBusMeterTapIfNeeded(busID: UUID, on node: AVAudioNode) {
        guard node.engine === engine, node !== finalOutputMixer else { return }
        let key = ObjectIdentifier(node)
        guard channelMeterTappedNodes[key] == nil else { return }
        // Use the LIVE generation so a later tap teardown silences this closure.
        // The node is tracked in `channelMeterTappedNodes`, so the normal
        // remove-all / install-all bank cycle reclaims and re-adds it cleanly; it
        // works whether or not the general bank is currently installed (the
        // offline render path wires the route before the engine runs the bank).
        let generation = channelMeterTapGeneration.load()
        let publisher = channelMeterBank.publisher(for: .bus(busID))
        // installTap throws an uncatchable NSException if the node already has a
        // tap — the shim turns a bookkeeping slip into a skipped meter, not a crash.
        let exception = SEQRunCatchingObjCException {
            node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                guard let self, self.channelMeterTapGeneration.load() == generation else { return }
                publisher.process(buffer: buffer)
            }
        }
        guard exception == nil else {
            DevActivity.trace(
                DevActivity.audioGraph,
                "bus meter tap skipped: \(exception?.reason ?? "unknown")"
            )
            return
        }
        channelMeterTappedNodes[key] = node
        channelMeterTapInstallCountForTesting += 1
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
            // routing-lint-allow: recoverAudioGraphAfterDeviceApply device-change recovery (HAL renegotiation)
            self.engine.stop()
        }
        self.engine.reset()
        self.engine.prepare()
        self.installMasterMeterTapIfNeeded()
        if wasRunning {
            self.channelMeterBank.startPublishing()
            // routing-lint-allow: recoverAudioGraphAfterDeviceApply device-change recovery (HAL renegotiation)
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

    /// Live single-track output reconnect (R1 bus reassign, R2 insert
    /// add/remove, audio-input route change) with a ramp-to-silence guard so a
    /// SOUNDING track is never hard-disconnected mid-signal (the click bug,
    /// docs/bugs/20260625-routing-hard-disconnect-clicks).
    ///
    /// Shape: ramp the track's OWN per-track gain stage (`source`, an
    /// `AVAudioMixerNode` — the same node mute ramps) down to 0 over ~12 ms,
    /// perform the disconnect+reconnect on (near-)silence, then ramp back to the
    /// stored level. Because the whole track briefly dips to silence the
    /// disconnect lands on no signal → no click. This avoids per-leg ramp
    /// choreography: one gain stage, one down-ramp, one up-ramp.
    ///
    /// Sequencing (no thread blocked, no lock held across the wait):
    ///  - The down-ramp runs on MixerGainRamp's queue. Its completion schedules
    ///    the reconnect on MAIN (re-acquiring graphLock there), then kicks the
    ///    up-ramp. graphLock / lifecycleLock are NOT held across the ~12 ms.
    ///  - Overlapping reconnects coalesce safely: MixerGainRamp's per-node
    ///    generation token means a newer ramp supersedes an older one; a
    ///    superseded down-ramp's completion reports `reachedTarget == false`,
    ///    so the stale reconnect/up-ramp is dropped — the newer request owns it.
    ///
    /// Skips the ramp (does the plain synchronous reconnect) when the engine is
    /// not running, the source is not a mixer node, or it is already silent
    /// (muted / level 0) — a muted track is already at 0 so disconnecting it is
    /// click-free, and double-ramping a muted node would itself click on the
    /// up-ramp.
    @MainActor
    private func reconnectTrackOutputRampedOnMain(_ routing: TrackOutputRouting) {
        let source = routing.source
        withTrackGainRampedToSilence(source: source) { [weak self] in
            self?.reconnectTrackOutputOnMain(routing)
        }
    }

    /// Run a graph-mutating `work` closure on (near-)silence so a SOUNDING
    /// track is never hard-disconnected mid-signal (the click bug,
    /// docs/bugs/20260625-routing-hard-disconnect-clicks).
    ///
    /// Shape: ramp the track's OWN per-track gain stage down to 0 over ~12 ms,
    /// run the disconnect/rebuild/reconnect `work` on silence, then ramp back to
    /// the stored level. Because the whole track briefly dips to silence the
    /// edits land on no signal → no click. One gain stage, one down-ramp, one
    /// up-ramp — no per-leg ramp choreography.
    ///
    /// The gain stage is resolved as: the `source` itself when it is an
    /// `AVAudioMixerNode` (audio-input tracks — same node mute ramps), else the
    /// track's persistent send FANOUT mixer (sample / native tracks, whose
    /// output node is an EQ/filter, not a mixer). The fanout's `outputVolume`
    /// gates the track's whole dry+send contribution, so ramping it to 0
    /// silences everything downstream of the chain rebuild — exactly what makes
    /// `host.rebuild`'s chain disconnect land on silence.
    ///
    /// Sequencing (no thread blocked, no lock held across the wait):
    ///  - The down-ramp runs on MixerGainRamp's queue. Its completion schedules
    ///    `work` on MAIN (acquiring graphLock there), then kicks the up-ramp.
    ///    graphLock / lifecycleLock are NOT held across the ~12 ms.
    ///  - Overlapping edits coalesce safely: MixerGainRamp's per-node generation
    ///    token means a newer ramp supersedes an older one; a superseded
    ///    down-ramp's completion reports `reachedTarget == false`, so the stale
    ///    `work` + up-ramp is dropped — the newer request owns the node.
    ///
    /// Skips the ramp (runs `work` synchronously under the CALLER's graphLock)
    /// when the engine is not running, no mixer gain stage can be resolved, or
    /// the gain stage is already silent (muted / level 0): a muted track is
    /// already at 0 so the edit is click-free, and double-ramping a silent node
    /// would itself click.
    /// IMPORTANT: callers must NOT hold graphLock when taking the ramped path —
    /// they already release it before returning (the closure re-acquires it on
    /// its own main hop), and the synchronous path here assumes the caller's
    /// lock is held. In practice the live single-track edit sites call this
    /// while holding graphLock, which is correct for the synchronous fallthrough
    /// and harmless for the ramped path (the lock is released when their
    /// `performOnMain` closure returns, before the deferred work runs).
    @MainActor
    private func withTrackGainRampedToSilence(
        source: AVAudioNode,
        work: @escaping @MainActor () -> Void
    ) {
        // A/B calibration hook: set SEQUENCER_AI_DISABLE_ROUTING_RAMP=1 to take
        // the OLD hard-disconnect path so the click metric can be calibrated
        // against a known-clicking control. Never set in production.
        if Self.disableRoutingRampForCalibration {
            work()
            return
        }

        guard engine.isRunning,
              let gainStage = trackGainStage(for: source)
        else {
            work()
            return
        }

        // Restore level: read the gain stage's SETTLED steady-state target, not
        // its live `outputVolume`. The live value can be a transient mid-dip if
        // a previous ramp-to-silence on this same stage is still in flight (two
        // routing/rebuild splices overlapping within the ~12 ms dip) — capturing
        // that transient as the "restore" level is the intermittent route-to-
        // master / drum-part-add silence bug: the second cycle would ramp "back"
        // to a near-zero value and the track stayed silent. The fanout splitter
        // is only ever driven by this dip path, so its settled target is its
        // intended rest level (1.0 unless an outer mute set it). Fall back to the
        // live volume for a stage this ramp has never driven (first-ever splice).
        let storedLevel = MixerGainRamp.shared.settledTarget(for: gainStage) ?? gainStage.outputVolume
        // Already silent (muted / level 0): a hard disconnect on silence does
        // not click, and ramping a silent node back up would itself click. Use
        // the SETTLED level (not the possibly-mid-dip live volume) so an
        // in-flight transient dip does not make us wrongly skip the restore.
        guard storedLevel > 0.0005 else {
            work()
            return
        }

        rampedReconnectCountForTesting += 1

        // Ramp the track's gain stage to silence, then — once silence is
        // actually reached — run the graph edit and ramp back. The completion
        // fires on MixerGainRamp's background queue, so hop to main and acquire
        // graphLock there (never held across the ramp wait). The down-ramp is a
        // TRANSIENT dip (`markSettled: false`) so it does not overwrite the
        // stage's recorded steady-state target — a concurrent splice that starts
        // mid-dip still reads the true restore level above.
        MixerGainRamp.shared.ramp(gainStage, to: 0, markSettled: false) { [weak self] reachedTarget in
            guard let self else { return }
            // Superseded by a newer ramp for this node → that newer request now
            // owns the gain stage and its edit (and restores its settled level).
            // Drop this stale one.
            guard reachedTarget else { return }
            // realtime-allow-main-async: ramp-completion graph-edit hop off the ramp queue (not tick/event scheduling), graphLock acquired here. Test: RampBeforeDisconnectTests.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard source.engine === self.engine else {
                        // Source was detached/torn down before the dip completed
                        // (e.g. removeTrack). Skip the reconnect — but STILL
                        // restore the gain stage to its settled level so a
                        // recycled/persistent stage is never left stuck silent.
                        DevActivity.trace(DevActivity.audioGraph, "ramp-silence DROP reason=source-detached storedLevel=\(storedLevel)")
                        if gainStage.engine === self.engine {
                            MixerGainRamp.shared.ramp(gainStage, to: storedLevel)
                        }
                        return
                    }
                    self.lockGraphLock()
                    work()
                    self.unlockGraphLock()
                    // Ramp the gain stage back to its pre-edit (settled) level on
                    // silence — a normal ramp, re-recording the settled target.
                    MixerGainRamp.shared.ramp(gainStage, to: storedLevel)
                }
            }
        }
    }

    /// Resolve the per-track gain stage (an `AVAudioMixerNode` whose
    /// `outputVolume` gates the track's whole contribution) used to ramp the
    /// track to silence before a live graph edit. Returns the `source` itself
    /// when it is a mixer (audio-input tracks), else the track's persistent send
    /// FANOUT mixer (sample / native tracks route their dry + sends through the
    /// fanout, so silencing it silences the entire track downstream of the
    /// chain). Returns nil when neither exists (e.g. send buses not yet
    /// installed and a non-mixer source) → caller takes the synchronous path.
    @MainActor
    private func trackGainStage(for source: AVAudioNode) -> AVAudioMixerNode? {
        if let mixer = source as? AVAudioMixerNode {
            return mixer
        }
        return trackSendNodes[ObjectIdentifier(source)]?.fanout
    }

    @MainActor
    private func reconnectTrackOutputOnMain(_ routing: TrackOutputRouting) {
        reconnectTrackOutputCountForTesting += 1
        let source = routing.source
        let dryDestination = routing.busID.flatMap { mixerBusHosts[$0]?.destinationNode() } ?? preMasterMixer

        // Resolve the per-track FX insert chain boundary. The track's output is
        // `source -> [insert chain] -> chainOutput`; every downstream wire (dry
        // destination + send fanout) then feeds from `chainOutput`, so sends are
        // post-insert (mirroring a DAW channel strip). When the chain is empty,
        // `chainOutput` collapses back to `source`. We do NOT disconnect `source`
        // wholesale up front: when the persistent send geometry below is already
        // established and unchanged, the only edge that moves is the fanout's
        // INPUT leg (chainOutput -> fanout). Tearing down and re-adding the
        // live send-bus legs (sendA/sendB -> send buses) on every reconnect is
        // what wedged the CoreAudio render reconfigure into an unbounded
        // AllocateInputBlock recursion when a track FX insert was added to a
        // send-active track (docs/bugs/20260625-add-second-insert-render-recursion-cycle).
        let chainOutput: AVAudioNode
        if let host = trackInsertChainHosts[trackID(for: source)],
           let chainInput = host.inputNode,
           let chainTerminal = host.terminalNode
        {
            engine.disconnectNodeOutput(source)
            engine.disconnectNodeInput(chainInput)
            engine.disconnectNodeOutput(chainTerminal)
            engine.connect(source, to: chainInput, format: nil)
            chainOutput = chainTerminal
        } else {
            engine.disconnectNodeOutput(source)
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
        if let sendADestination = sendBusHosts[.sendA]?.destinationNode(),
           let sendBDestination = sendBusHosts[.sendB]?.destinationNode()
        {
            let key = ObjectIdentifier(source)
            let nodes = sendNodes(for: source, levels: routing.sendLevels)
            let stored = trackSendDestinationsForTesting[key]

            // The send-bus legs (sendA -> send-bus A, sendB -> send-bus B) are
            // wired ONCE and then left permanently in place. Re-adding an
            // already-live send leg into a running send-bus inputMixer — which
            // forces CoreAudio to re-allocate that mixer's input blocks while
            // audio is flowing — wedged the render reconfigure into an unbounded
            // AllocateInputBlock recursion (the symptom in
            // docs/bugs/20260625-add-second-insert-render-recursion-cycle).
            // So we touch them only when they are not yet established (or the
            // send-bus destination node itself changed, which only happens when
            // the send buses are reinstalled).
            let sendLegsNeedWiring = stored?.sendA !== sendADestination
                || stored?.sendB !== sendBDestination
            if sendLegsNeedWiring {
                engine.disconnectNodeOutput(nodes.sendA)
                engine.disconnectNodeInput(nodes.sendA)
                engine.disconnectNodeOutput(nodes.sendB)
                engine.disconnectNodeInput(nodes.sendB)
                engine.connect(
                    nodes.sendA,
                    to: sendADestination,
                    fromBus: 0,
                    toBus: inputBus(for: sendADestination),
                    format: nil
                )
                engine.connect(
                    nodes.sendB,
                    to: sendBDestination,
                    fromBus: 0,
                    toBus: inputBus(for: sendBDestination),
                    format: nil
                )
            }

            // Always rebuild the fanout's OUTPUT splitter (dry + sendA + sendB):
            // the dry destination can change (bus reroute) and an upstream
            // rebuild (master/bus chain reinstall) can reset the destination
            // mixer's inputs, so this leg must be re-established every time to
            // keep audio flowing. This re-points only the fanout's own outputs
            // and never re-touches the live send-bus input legs above, so the
            // recursive reconfigure stays avoided. The fanout's INPUT
            // (chainOutput -> fanout) is re-pointed below because the chain
            // output can change on every insert edit.
            engine.disconnectNodeOutput(nodes.fanout)
            let fanoutDestinations = [
                connectionPoint(for: dryDestination),
                connectionPoint(for: nodes.sendA),
                connectionPoint(for: nodes.sendB),
            ]
            engine.connect(nodes.fanout, to: fanoutDestinations, fromBus: 0, format: nil)

            trackSendDestinationsForTesting[key] = TrackSendDestinations(
                fanout: [dryDestination, nodes.sendA, nodes.sendB],
                sendA: sendADestination,
                sendB: sendBDestination
            )

            // Re-point ONLY the fanout's input leg to the (possibly new) chain
            // output — the single edge that moves on an insert/value reconnect.
            engine.disconnectNodeInput(nodes.fanout)
            destinations = [connectionPoint(for: nodes.fanout)]
        } else {
            // Send buses not installed yet: route dry only and tear down any
            // stale send nodes. installSendBuses re-reconnects every track once
            // the buses exist, which establishes the persistent geometry above.
            // The fanout is a potential MULTI-POINT source: dissolve its output
            // point-by-point (see `dissolveOutputConnectionsOnMain`) so a
            // stopped-engine teardown cannot plant the UpdateGraphAfterReconfig
            // poison. Retire the send nodes to the graph-owned pool instead of
            // detaching them; rapid source transitions previously crashed inside
            // AVAudioEngineGraph::RemoveNode while removing these nodes.
            let key = ObjectIdentifier(source)
            if let nodes = trackSendNodes.removeValue(forKey: key) {
                retireTrackSendNodes(nodes)
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
        // The outputMixer IS this track's gain stage (trackGainStage returns the
        // source mixer for audio-input tracks). Write its level/mute THROUGH
        // MixerGainRamp.setImmediate so the ramp records this as the node's
        // SETTLED steady-state target. If we wrote `outputMixer.outputVolume`
        // directly (out-of-band), settledTarget would stay stale at a prior
        // level — and a later routing change's ramp-to-silence restore would read
        // that stale target and AUDIBLY UN-MUTE a muted audio-input track (the
        // mute-escape regression). Routing all gain-stage writes through the ramp
        // keeps the invariant "settledTarget == intended rest level" for ALL
        // track kinds (sample/AU/audio-input).
        let intendedLevel: Float = request.source == .silent || request.mix.isMuted ? 0 : Float(request.mix.clampedLevel)
        MixerGainRamp.shared.setImmediate(host.outputMixer, to: intendedLevel)
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
            // Ramp-to-silence before the live reconnect (click fix): the capture
            // tap teardown + output reconnect run inside the gain-stage ramp so
            // an audio-input track reroute does not hard-cut a sounding monitor.
            withTrackGainRampedToSilence(source: host.outputMixer) { [weak self] in
                guard let self else { return }
                self.removeAudioInputCaptureTapOnMain(host: host)
                self.reconnectTrackOutputOnMain(routing)
                self.installAudioInputCaptureTapIfNeededOnMain(host: host)
            }
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
        if host.connectedSource == .input, !simulatesLiveInputConnection {
            // Already-armed path: a live `.input` connection exists, so the
            // input node was necessarily accessed before.
            engine.disconnectNodeOutput(armedEngineInputNode())
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
            if simulatesLiveInputConnection {
                // Simulated live connect (tests, or an offline manual-rendering
                // engine that has no input IO unit — see
                // `simulatesLiveInputConnection`). The host reports `.input`
                // for UI/route state; no real input edge exists.
                DevActivity.trace(DevActivity.audioGraph, "audio-input monitor connect SIMULATED (no engine.inputNode wiring) track=\(host.trackID.uuidString)")
                host.connectedSource = .input
                return
            }
            guard Self.liveAudioInputAuthorized else {
                host.connectedSource = .silent
                // Through the ramp so settledTarget tracks this forced-silent rest
                // level (keeps the mute-escape invariant; see installAudioInput…).
                MixerGainRamp.shared.setImmediate(host.outputMixer, to: 0)
                return
            }
            // Arming moment (user intent): this is where the shared IO unit's
            // input scope gets enabled for the first time, and — on a fresh
            // grant or a stale-authorized rebuilt binary — where the mic-TCC
            // prompt is allowed to fire.
            let inputNode = armedEngineInputNode()
            let inputFormat = inputNode.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0 else {
                host.connectedSource = .silent
                MixerGainRamp.shared.setImmediate(host.outputMixer, to: 0)
                return
            }
            applyInputChannelMapOnMain(
                for: host.selectedChannel,
                deviceChannelCount: Int(inputFormat.channelCount)
            )
            engine.connect(inputNode, to: host.outputMixer, format: inputNode.inputFormat(forBus: 0))
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
        armedEngineInputNode().auAudioUnit.channelMap = map
    }

    @MainActor
    private func teardownAudioInputRoutingOnMain(trackID: UUID) {
        guard let host = audioInputRoutingHosts.removeValue(forKey: trackID) else { return }

        if engine.isRunning {
            // Defensive Hard Rule 5 fallback: the normal full-routing sync stops
            // the engine before removing audio-input hosts, but this method owns
            // the teardown invariant if a future caller reaches it live.
            withTrackGainRampedToSilence(source: host.outputMixer) { [weak self] in
                self?.teardownAudioInputRoutingNodesOnMain(host: host)
            }
            return
        }

        teardownAudioInputRoutingNodesOnMain(host: host)
    }

    @MainActor
    private func teardownAudioInputRoutingNodesOnMain(host: AudioInputRoutingHost) {
        if host.connectedSource == .input, !simulatesLiveInputConnection {
            // Already-armed path (live `.input` connection being torn down).
            engine.disconnectNodeOutput(armedEngineInputNode())
        }
        removeAudioInputCaptureTapOnMain(host: host)
        host.loopPlayer.stop()
        engine.disconnectNodeOutput(host.loopPlayer)
        engine.disconnectNodeInput(host.outputMixer)
        // Forget the outputMixer's recorded settled target — it is a routing gain
        // stage driven by MixerGainRamp (mute/level), so a node recycled at the
        // same ObjectIdentifier must not inherit a stale rest level.
        MixerGainRamp.shared.forgetSettledTarget(for: host.outputMixer)
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
            // This is a reconnect (bus reroute / FX-insert edit / bus reinstall)
            // re-asserting the AUTHORITATIVE send levels. It may race a still
            // in-flight steady-state send ramp (R4) on these same nodes — go
            // through setImmediate so the ramp's generation token is bumped and
            // the stale ramp can't land its old target on top of this value.
            MixerGainRamp.shared.setImmediate(nodes.sendA, to: levels.clampedSendA)
            MixerGainRamp.shared.setImmediate(nodes.sendB, to: levels.clampedSendB)
            return nodes
        }

        let nodes: TrackSendNodes
        if let retired = retiredTrackSendNodes.popLast() {
            nodes = retired
        } else {
            nodes = TrackSendNodes(fanout: AVAudioMixerNode(), sendA: AVAudioMixerNode(), sendB: AVAudioMixerNode())
            engine.attach(nodes.fanout)
            engine.attach(nodes.sendA)
            engine.attach(nodes.sendB)
        }
        // Seed the fanout's SETTLED target at its rest level (1.0). The fanout is
        // a pure dry/send splitter whose `outputVolume` is only ever moved by the
        // routing ramp-to-silence dip — so its steady-state is always full. The
        // ramp-to-silence restore reads this settled value, not the live volume,
        // so a splice that lands mid-dip restores to 1.0 (not the transient).
        // Without this seed, settledTarget(for: fanout) would be nil and the
        // restore would fall back to the mid-dip live volume — the silence bug.
        MixerGainRamp.shared.setImmediate(nodes.fanout, to: 1.0)
        MixerGainRamp.shared.setImmediate(nodes.sendA, to: levels.clampedSendA)
        MixerGainRamp.shared.setImmediate(nodes.sendB, to: levels.clampedSendB)
        trackSendNodes[key] = nodes
        return nodes
    }

    /// Sever every output edge of `node` by disconnecting each DESTINATION's
    /// input bus, one connection point at a time — never
    /// `disconnectNodeOutput(node)` on a node that may hold a MULTI-POINT
    /// (1→N) output connection while the engine is stopped.
    ///
    /// AVFAudio poison (bug 20260702-123512, record-arm crash): calling
    /// `disconnectNodeOutput` (or `detach`, whose internal disconnect takes
    /// the same path) on a node with a multi-point output connection while
    /// the engine is STOPPED, and then restarting WITHOUT re-establishing a
    /// connection on that node, leaves a stale entry in
    /// `AVAudioEngineGraph`'s bookkeeping. The NEXT disconnect on the
    /// RUNNING engine then walks it in `UpdateGraphAfterReconfig` and makes
    /// a virtual call through a NULL AUInterface — SIGSEGV at
    /// `KERN_INVALID_ADDRESS 0x68` at a completely unrelated call site
    /// (bus-terminal rewire, prepared-track repair). Proven by a standalone
    /// AVAudioEngine repro: source-side multi-point disconnect while stopped
    /// crashes; this destination-side point-by-point dissolve is clean.
    /// The only multi-point source in the track architecture is the per-track
    /// send FANOUT splitter (dry + sendA + sendB), torn down exactly here.
    @MainActor
    private func dissolveOutputConnectionsOnMain(of node: AVAudioNode) {
        for point in engine.outputConnectionPoints(for: node, outputBus: 0) {
            guard let destination = point.node else { continue }
            engine.disconnectNodeInput(destination, bus: point.bus)
        }
    }

    @MainActor
    private func retireTrackSendNodes(_ nodes: TrackSendNodes) {
        // Remove every edge while the nodes are still graph-owned, then keep the
        // nodes attached but disconnected for reuse by a later track/source.
        // This follows the fixed-resource graph rule and avoids the crash site:
        // AVAudioEngine detachNode during rapid sample source transitions.
        dissolveOutputConnectionsOnMain(of: nodes.fanout)
        engine.disconnectNodeInput(nodes.fanout)
        dissolveOutputConnectionsOnMain(of: nodes.sendA)
        engine.disconnectNodeInput(nodes.sendA)
        dissolveOutputConnectionsOnMain(of: nodes.sendB)
        engine.disconnectNodeInput(nodes.sendB)
        MixerGainRamp.shared.forgetSettledTarget(for: nodes.fanout)
        MixerGainRamp.shared.forgetSettledTarget(for: nodes.sendA)
        MixerGainRamp.shared.forgetSettledTarget(for: nodes.sendB)
        nodes.fanout.outputVolume = 0
        nodes.sendA.outputVolume = 0
        nodes.sendB.outputVolume = 0
        retiredTrackSendNodes.append(nodes)
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
        retireTrackSendNodes(nodes)
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
    /// Largest absolute sample-to-sample jump seen on the master output since
    /// the last publish (a discontinuity / CLICK metric). A smooth sustained
    /// drone produces a small per-sample delta; a hard disconnect of a sounding
    /// node injects an abrupt step → a spike here. Headless rigs read this to
    /// flag CLICK per graph-edit op (routing-stress.sh). Default 0 keeps the
    /// `.silent`/cleared constructors and all existing call sites unchanged.
    var maxSampleDelta: Double = 0
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

        // Discontinuity / CLICK metric: the largest absolute SECOND difference
        // in this buffer, NORMALIZED by the buffer peak. Normalizing is what
        // makes it honest against an always-on drone whose level rises through
        // a test run: a continuous waveform's curvature scales WITH its
        // amplitude, so the normalized value stays a small, level-independent
        // constant; a true sample-level discontinuity (a hard disconnect of a
        // sounding node) is large RELATIVE to the signal → the normalized value
        // spikes. Folded into the transport's running max, drained on the next
        // publish so a rig can read it per op.
        var maxDelta = Self.maxSampleDelta(channel: channels[0], frameCount: frameCount)
        if channelCount > 1 {
            maxDelta = max(maxDelta, Self.maxSampleDelta(channel: channels[1], frameCount: frameCount))
        }
        let peak = max(left, right)
        let normalized = peak > 0.0001 ? maxDelta / peak : 0
        transport.storeMaxSampleDelta(normalized)
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
            isClipLatched: displayState.isClipLatched || snapshot.isClipped,
            // Surface the per-publish discontinuity reading directly (no
            // envelope): a CLICK is a transient the rig samples right after an
            // op. Carry the previous value forward when this publish saw no
            // buffer (snapshot delta 0 from an empty drain) so a fresh spike is
            // not masked, but a sustained 0 naturally settles back to 0.
            maxSampleDelta: max(snapshot.maxSampleDelta, displayState.maxSampleDelta * 0.5)
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

    /// Largest absolute SECOND difference (|Δ[n] − Δ[n−1]|) between consecutive
    /// samples in the buffer — the discontinuity metric used to flag a CLICK.
    ///
    /// Why the second difference and not the raw first difference: a loud,
    /// continuous waveform (the always-on drone) has a large but SMOOTHLY
    /// varying first difference (its slope), so a raw max-|Δ| can't tell a loud
    /// high-frequency signal apart from a real step — pure gain changes (which
    /// cannot click) showed false spikes. A continuous signal has a bounded,
    /// smoothly varying slope, so its second difference stays small; a true
    /// sample-level discontinuity (a hard disconnect of a sounding node) injects
    /// an abrupt slope change → an isolated spike in the second difference.
    /// This suppresses the loud-drone slope and isolates genuine edges.
    /// (Intra-buffer only; a disconnect click produces a step well inside the
    /// affected buffer.)
    private static func maxSampleDelta(channel: UnsafePointer<Float>, frameCount: Int) -> Double {
        guard frameCount > 2 else { return 0 }
        var maxSecondDelta: Float = 0
        var previousDelta = channel[1] - channel[0]
        for frame in 2..<frameCount {
            let delta = channel[frame] - channel[frame - 1]
            maxSecondDelta = max(maxSecondDelta, abs(delta - previousDelta))
            previousDelta = delta
        }
        return Double(maxSecondDelta)
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
    private let maxDeltaBits = AtomicInt64(Int64(bitPattern: 0.0.bitPattern))
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

    /// Fold a buffer's largest sample-to-sample jump into the running max (the
    /// discontinuity / CLICK metric). Drained on snapshot.
    func storeMaxSampleDelta(_ delta: Double) {
        let safe = Self.safeAmplitude(delta)
        maxDeltaBits.storeMaximum(Self.amplitudeBits(safe), shouldReplace: Self.shouldReplaceAmplitude)
    }

    func snapshot() -> (left: Double, right: Double, isClipped: Bool, maxSampleDelta: Double) {
        (
            left: Self.amplitude(fromBits: leftBits.exchange(Self.zeroAmplitudeBits)),
            right: Self.amplitude(fromBits: rightBits.exchange(Self.zeroAmplitudeBits)),
            isClipped: clipped.load() != 0,
            maxSampleDelta: Self.amplitude(fromBits: maxDeltaBits.exchange(Self.zeroAmplitudeBits))
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
