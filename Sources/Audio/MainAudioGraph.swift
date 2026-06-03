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
    private let audioDeviceOwner: AudioDeviceOwning
    private(set) var masterBranchesForTesting: [MasterBranchReadout] = []
    private(set) var postBlendMasterInsertNodesForTesting: [AVAudioNode] = []
    private(set) var masterOutputGainForTesting: Float = 1
    private(set) var masterMeterTapPointForTesting: MasterMeterTapPoint?
    private(set) var masterMeterTapInstallCountForTesting = 0
    private(set) var masterMeterTapRemoveCountForTesting = 0
    private(set) var audioInputFullRoutingSyncCountForTesting = 0
    private(set) var audioInputScopedRoutingUpdateCountForTesting = 0

    private let graphLock = NSLock()
    private let postBlendMixer = AVAudioMixerNode()
    private let finalOutputMixer = AVAudioMixerNode()
    private var managedMasterNodes: [AVAudioNode] = []
    private var managedMasterGainMixers: [AVAudioMixerNode] = []
    private var mixerBusHosts: [UUID: MixerBusHost] = [:]
    private var sendBusHosts: [SendBusID: SendBusHost] = [:]
    private var trackOutputDestinationsForTesting: [ObjectIdentifier: AVAudioNode] = [:]
    private var trackOutputRoutings: [ObjectIdentifier: TrackOutputRouting] = [:]
    private var trackSendNodes: [ObjectIdentifier: TrackSendNodes] = [:]
    private var trackSendDestinationsForTesting: [ObjectIdentifier: TrackSendDestinations] = [:]
    private var audioInputRoutingHosts: [UUID: AudioInputRoutingHost] = [:]
    private var isStarted = false
    private var isMasterMeterTapInstalled = false
    private let masterMeterTapGeneration = AtomicInt32(0)

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
        var selectedChannel: AudioInputChannel = .stereo
        var outputBusID: UUID?

        init(trackID: UUID) {
            self.trackID = trackID
        }
    }

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        masterMeterPublisher: MasterMeterPublisher = MasterMeterPublisher(),
        audioDeviceOwner: AudioDeviceOwning = CoreAudioHALDeviceOwner()
    ) {
        self.engine = engine
        self.masterMeterPublisher = masterMeterPublisher
        self.audioDeviceOwner = audioDeviceOwner
        self.preMasterMixer = AVAudioMixerNode()

        performOnMain {
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
        masterMeterPublisher.stopPublishing()
        performOnMain {
            self.removeMasterMeterTapIfNeeded()
        }
    }

    func attach(_ node: AVAudioNode) {
        performOnMain {
            guard node.engine == nil else { return }
            self.engine.attach(node)
        }
    }

    func detach(_ node: AVAudioNode) {
        performOnMain {
            guard node.engine === self.engine else { return }
            self.engine.disconnectNodeInput(node)
            self.engine.disconnectNodeOutput(node)
            self.engine.detach(node)
        }
    }

    func connect(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat? = nil) {
        performOnMain {
            self.engine.connect(source, to: destination, format: format)
        }
    }

    func disconnectOutput(_ node: AVAudioNode) {
        performOnMain {
            self.removeTrackSendNodes(for: node)
            self.engine.disconnectNodeOutput(node)
        }
    }

    var sendReturnDestinationForTesting: AVAudioNode {
        finalOutputMixer
    }

    var availableInputChannelCount: Int {
        Int(engine.inputNode.inputFormat(forBus: 0).channelCount)
    }

    func syncAudioInputRoutings(_ requests: [AudioInputRoutingRequest]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
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

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    func updateAudioInputRoutingParameters(_ requests: [AudioInputRoutingRequest]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            self.applyAudioInputRoutingParametersOnMain(requests)
            self.audioInputScopedRoutingUpdateCountForTesting += 1
        }
    }

    func installMixerBuses(_ buses: [MixerBus], effectiveMuteByBusID: [UUID: Bool] = [:]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

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

            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    func setMixerBusMix(busID: UUID, mix: BusMixSettings, effectiveMute: Bool) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            self.mixerBusHosts[busID]?.applyMix(mix, effectiveMute: effectiveMute)
        }
    }

    func setMixerBusParameters(bus: MixerBus, effectiveMute: Bool) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            self.mixerBusHosts[bus.id]?.applyParameters(bus: bus, effectiveMute: effectiveMute)
        }
    }

    func installSendBuses(_ sendBuses: [SendBusState]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

            let busesByID = Dictionary(uniqueKeysWithValues: sendBuses.map { ($0.id, $0) })
            for id in SendBusID.allCases {
                let state = (busesByID[id] ?? SendBusState(id: id)).normalized(expectedID: id)
                let host = self.sendBusHosts[id] ?? SendBusHost(id: id)
                self.sendBusHosts[id] = host
                host.install(sendBus: state, in: self)
            }

            for routing in self.trackOutputRoutings.values where routing.source.engine === self.engine {
                self.reconnectTrackOutputOnMain(routing)
            }

            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    func installSendBus(_ sendBus: SendBusState) {
        graphLock.lock()
        let existing = performOnMainReturning {
            SendBusID.allCases.map { id in
                if id == sendBus.id {
                    return sendBus
                }
                return self.sendBusHosts[id]?.appliedStateForTesting ?? SendBusState(id: id)
            }
        }
        graphLock.unlock()
        installSendBuses(existing)
    }

    func connectTrackOutput(
        _ source: AVAudioNode,
        to busID: UUID?,
        sends sendLevels: TrackSendLevels = .zero
    ) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            guard source.engine === self.engine else { return }
            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

            let routing = TrackOutputRouting(source: source, busID: busID, sendLevels: sendLevels)
            self.trackOutputRoutings[ObjectIdentifier(source)] = routing
            self.reconnectTrackOutputOnMain(routing)
            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
        }
    }

    func setTrackSendLevels(_ source: AVAudioNode, sendA: Double, sendB: Double) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            let key = ObjectIdentifier(source)
            let sendLevels = TrackSendLevels(sendA: sendA, sendB: sendB)
            if var routing = self.trackOutputRoutings[key] {
                routing.sendLevels = sendLevels
                self.trackOutputRoutings[key] = routing
            }
            self.trackSendNodes[key]?.sendA.outputVolume = sendLevels.clampedSendA
            self.trackSendNodes[key]?.sendB.outputVolume = sendLevels.clampedSendB
        }
    }

    func start() throws {
        try performOnMainThrowing {
            guard !self.isStarted || !self.engine.isRunning else { return }
            self.installMasterMeterTapIfNeeded()
            self.masterMeterPublisher.startPublishing()
            try self.engine.start()
            self.isStarted = true
        }
    }

    func stop() {
        performOnMain {
            self.removeMasterMeterTapIfNeeded()
            self.masterMeterPublisher.stopPublishing()
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
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
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
            var firstDestinations: [AVAudioConnectionPoint] = []
            var branchReadouts: [MasterBranchReadout] = []

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
            self.engine.connect(self.preMasterMixer, to: firstDestinations, fromBus: 0, format: nil)
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
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.mixerBusHosts.values.compactMap { $0.readout() }
                .sorted { $0.busID.uuidString < $1.busID.uuidString }
        }
    }

    func mixerBusReadoutForTesting(busID: UUID) -> MixerBusHost.Readout? {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.mixerBusHosts[busID]?.readout()
        }
    }

    var sendBusReadoutsForTesting: [SendBusHost.Readout] {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.sendBusHosts.values.compactMap { $0.readout() }
                .sorted { $0.busID.rawValue < $1.busID.rawValue }
        }
    }

    func sendBusReadoutForTesting(busID: SendBusID) -> SendBusHost.Readout? {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.sendBusHosts[busID]?.readout()
        }
    }

    func trackOutputDestinationForTesting(_ source: AVAudioNode) -> AVAudioNode? {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.trackOutputDestinationsForTesting[ObjectIdentifier(source)]
        }
    }

    func trackSendReadoutForTesting(_ source: AVAudioNode) -> TrackSendReadout? {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
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
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
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
                pan: host.outputMixer.pan
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

    @MainActor
    private func installMasterMeterTapIfNeeded() {
        guard !isMasterMeterTapInstalled else { return }
        let generation = masterMeterTapGeneration.increment()
        finalOutputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, self.masterMeterTapGeneration.load() == generation else { return }
            self.masterMeterPublisher.process(buffer: buffer)
        }
        isMasterMeterTapInstalled = true
        masterMeterTapPointForTesting = .finalOutputMixer
        masterMeterTapInstallCountForTesting += 1
    }

    @MainActor
    private func removeMasterMeterTapIfNeeded() {
        guard isMasterMeterTapInstalled else { return }
        masterMeterTapGeneration.increment()
        finalOutputMixer.removeTap(onBus: 0)
        masterMeterPublisher.recordPeakAmplitudes(left: 0, right: 0)
        isMasterMeterTapInstalled = false
        masterMeterTapPointForTesting = nil
        masterMeterTapRemoveCountForTesting += 1
    }

    private static func clampedMasterOutputGain(_ gain: Double) -> Float {
        guard gain.isFinite else { return 1 }
        return Float(min(max(gain, 0), 2))
    }

    @MainActor
    private func recoverAudioGraphAfterDeviceApply(wasRunning: Bool) throws {
        if self.engine.isRunning {
            self.engine.stop()
        }
        self.engine.reset()
        self.engine.prepare()
        self.installMasterMeterTapIfNeeded()
        if wasRunning {
            self.masterMeterPublisher.startPublishing()
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
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            let clampedGain = Self.clampedMasterOutputGain(gain)
            self.finalOutputMixer.outputVolume = clampedGain
            self.masterOutputGainForTesting = clampedGain
        }
    }

    func setMasterBranchGains(_ gains: [Double]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
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
        let source = routing.source
        let dryDestination = routing.busID.flatMap { mixerBusHosts[$0]?.destinationNode() } ?? preMasterMixer
        engine.disconnectNodeOutput(source)

        var destinations = [connectionPoint(for: dryDestination)]
        if sendBusHosts[.sendA]?.destinationNode() != nil,
           sendBusHosts[.sendB]?.destinationNode() != nil
        {
            let nodes = sendNodes(for: source, levels: routing.sendLevels)
            engine.disconnectNodeOutput(nodes.fanout)
            engine.disconnectNodeOutput(nodes.sendA)
            engine.disconnectNodeOutput(nodes.sendB)
            engine.connect(
                nodes.fanout,
                to: [
                    connectionPoint(for: nodes.sendA),
                    connectionPoint(for: nodes.sendB),
                ],
                fromBus: 0,
                format: nil
            )
            var sendDestinations = TrackSendDestinations(fanout: [nodes.sendA, nodes.sendB], sendA: nil, sendB: nil)
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
            destinations.append(connectionPoint(for: nodes.fanout))
        }

        if destinations.count == 1 {
            engine.connect(
                source,
                to: dryDestination,
                fromBus: 0,
                toBus: inputBus(for: dryDestination),
                format: nil
            )
        } else {
            engine.connect(source, to: destinations, fromBus: 0, format: nil)
        }
        trackOutputDestinationsForTesting[ObjectIdentifier(source)] = dryDestination
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

        reconnectAudioInputSourceOnMain(host: host, requestedSource: request.source)
        applyAudioInputRoutingParametersOnMain(request)
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
            reconnectTrackOutputOnMain(routing)
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
        if host.connectedSource == .input {
            engine.disconnectNodeOutput(engine.inputNode)
        }
        if host.connectedSource == .loop {
            host.loopPlayer.stop()
            engine.disconnectNodeOutput(host.loopPlayer)
        }
        engine.disconnectNodeInput(host.outputMixer)

        switch requestedSource {
        case .input:
            let inputFormat = engine.inputNode.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0 else {
                host.connectedSource = .silent
                host.outputMixer.outputVolume = 0
                return
            }
            engine.connect(engine.inputNode, to: host.outputMixer, format: inputFormat)
            host.connectedSource = .input

        case .loop:
            engine.connect(host.loopPlayer, to: host.outputMixer, format: nil)
            host.connectedSource = .loop

        case .silent:
            host.connectedSource = .silent
        }
    }

    @MainActor
    private func teardownAudioInputRoutingOnMain(trackID: UUID) {
        guard let host = audioInputRoutingHosts.removeValue(forKey: trackID) else { return }

        if host.connectedSource == .input {
            engine.disconnectNodeOutput(engine.inputNode)
        }
        host.loopPlayer.stop()
        engine.disconnectNodeOutput(host.loopPlayer)
        engine.disconnectNodeInput(host.outputMixer)
        disconnectOutput(host.outputMixer)
        detach(host.loopPlayer)
        detach(host.outputMixer)
    }

    @MainActor
    private func connectionPoint(for destination: AVAudioNode) -> AVAudioConnectionPoint {
        AVAudioConnectionPoint(node: destination, bus: inputBus(for: destination))
    }

    @MainActor
    private func inputBus(for destination: AVAudioNode) -> AVAudioNodeBus {
        if let mixer = destination as? AVAudioMixerNode {
            return mixer.nextAvailableInputBus
        }
        return 0
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

        var thrownError: Error?
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

        var output: T?
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

        var output: T?
        var thrownError: Error?
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
    @ObservationIgnored private let publishInterval: TimeInterval
    @ObservationIgnored private let peakHoldDuration: TimeInterval
    @ObservationIgnored private let peakHoldReleaseDBPerSecond: Double
    @ObservationIgnored private let levelReleaseDBPerSecond: Double
    @ObservationIgnored private var publishTimer: DispatchSourceTimer?
    @ObservationIgnored private var lastPublishTime: TimeInterval?
    @ObservationIgnored private var leftPeakHoldTime: TimeInterval = 0
    @ObservationIgnored private var rightPeakHoldTime: TimeInterval = 0

    init(
        publishInterval: TimeInterval = 1.0 / 60.0,
        peakHoldDuration: TimeInterval = 0.75,
        peakHoldReleaseDBPerSecond: Double = 18,
        levelReleaseDBPerSecond: Double = 42
    ) {
        self.publishInterval = publishInterval
        self.peakHoldDuration = peakHoldDuration
        self.peakHoldReleaseDBPerSecond = peakHoldReleaseDBPerSecond
        self.levelReleaseDBPerSecond = levelReleaseDBPerSecond
    }

    func startPublishing() {
        if Thread.isMainThread {
            startPublishingOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startPublishingOnMain()
            }
        }
    }

    func stopPublishing() {
        if Thread.isMainThread {
            stopPublishingOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopPublishingOnMain()
            }
        }
    }

    deinit {
        publishTimer?.cancel()
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

        displayState = MasterMeterDisplayState(
            leftPeakDBFS: leftPeak,
            rightPeakDBFS: rightPeak,
            leftPeakHoldDBFS: leftHold,
            rightPeakHoldDBFS: rightHold,
            isClipLatched: displayState.isClipLatched || snapshot.isClipped
        )
    }

    func clearClip() {
        transport.clearClip()
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.clearClip()
            }
            return
        }
        displayState.isClipLatched = false
    }

    static func dbFS(amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else {
            return MasterMeterDisplayState.silenceDBFS
        }
        return 20 * log10(amplitude)
    }

    private func startPublishingOnMain() {
        guard publishTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + publishInterval, repeating: publishInterval)
        timer.setEventHandler { [weak self] in
            self?.publishPendingToMain()
        }
        publishTimer = timer
        timer.resume()
    }

    private func stopPublishingOnMain() {
        publishTimer?.cancel()
        publishTimer = nil
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
