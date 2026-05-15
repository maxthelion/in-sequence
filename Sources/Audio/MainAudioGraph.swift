import AVFoundation
import Foundation
import Observation

final class MainAudioGraph {
    struct MasterChain {
        var nodes: [AVAudioNode]
        var gain: Double
    }

    struct MasterBranchReadout {
        var nodes: [AVAudioNode]
        var gain: Float
    }

    let engine: AVAudioEngine
    let preMasterMixer: AVAudioMixerNode
    let masterMeterPublisher: MasterMeterPublisher
    private(set) var masterBranchesForTesting: [MasterBranchReadout] = []
    private(set) var postBlendMasterInsertNodesForTesting: [AVAudioNode] = []
    private(set) var masterOutputGainForTesting: Float = 1
    private(set) var masterMeterTapPointForTesting: MasterMeterTapPoint?
    private(set) var masterMeterTapInstallCountForTesting = 0
    private(set) var masterMeterTapRemoveCountForTesting = 0

    private let graphLock = NSLock()
    private let postBlendMixer = AVAudioMixerNode()
    private let finalOutputMixer = AVAudioMixerNode()
    private var managedMasterNodes: [AVAudioNode] = []
    private var managedMasterGainMixers: [AVAudioMixerNode] = []
    private var mixerBusHosts: [UUID: MixerBusHost] = [:]
    private var trackOutputDestinationsForTesting: [ObjectIdentifier: AVAudioNode] = [:]
    private var isStarted = false
    private var isMasterMeterTapInstalled = false
    private let masterMeterTapGeneration = AtomicInt32(0)

    init(engine: AVAudioEngine = AVAudioEngine(), masterMeterPublisher: MasterMeterPublisher = MasterMeterPublisher()) {
        self.engine = engine
        self.masterMeterPublisher = masterMeterPublisher
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
            self.engine.disconnectNodeOutput(node)
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

    func connectTrackOutput(_ source: AVAudioNode, to busID: UUID?) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            guard source.engine === self.engine else { return }
            let wasRunning = self.engine.isRunning
            self.removeMasterMeterTapIfNeeded()
            if wasRunning {
                self.engine.stop()
            }

            self.engine.disconnectNodeOutput(source)
            let destination = busID.flatMap { self.mixerBusHosts[$0]?.destinationNode() } ?? self.preMasterMixer
            self.engine.connect(source, to: destination, format: nil)
            self.trackOutputDestinationsForTesting[ObjectIdentifier(source)] = destination
            self.engine.prepare()
            self.installMasterMeterTapIfNeeded()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
            }
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

    func trackOutputDestinationForTesting(_ source: AVAudioNode) -> AVAudioNode? {
        graphLock.lock()
        defer { graphLock.unlock() }

        return performOnMainReturning {
            self.trackOutputDestinationsForTesting[ObjectIdentifier(source)]
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
}

enum MasterMeterTapPoint: Equatable {
    case finalOutputMixer
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

private final class AtomicInt64 {
    private let storage: UnsafeMutablePointer<Int64>

    init(_ value: Int64) {
        storage = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        storage.initialize(to: value)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func load() -> Int64 {
        OSAtomicAdd64Barrier(0, storage)
    }

    func store(_ value: Int64) {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    func storeMaximum(_ value: Int64, shouldReplace: (Int64, Int64) -> Bool) {
        while true {
            let oldValue = load()
            guard shouldReplace(oldValue, value) else { return }
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    func exchange(_ value: Int64) -> Int64 {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return oldValue
            }
        }
    }

}

private final class AtomicInt32 {
    private let storage: UnsafeMutablePointer<Int32>

    init(_ value: Int32) {
        storage = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        storage.initialize(to: value)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func load() -> Int32 {
        OSAtomicAdd32Barrier(0, storage)
    }

    func store(_ value: Int32) {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap32Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    @discardableResult
    func increment() -> Int32 {
        OSAtomicIncrement32Barrier(storage)
    }
}
