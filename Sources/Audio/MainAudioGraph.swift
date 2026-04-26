import AVFoundation
import Foundation

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
    private(set) var masterBranchesForTesting: [MasterBranchReadout] = []

    private let graphLock = NSLock()
    private let finalOutputMixer = AVAudioMixerNode()
    private var managedMasterNodes: [AVAudioNode] = []
    private var isStarted = false

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        self.preMasterMixer = AVAudioMixerNode()

        performOnMain {
            self.engine.attach(self.preMasterMixer)
            self.engine.attach(self.finalOutputMixer)
            self.engine.connect(self.preMasterMixer, to: self.finalOutputMixer, format: nil)
            self.engine.connect(self.finalOutputMixer, to: self.engine.mainMixerNode, format: nil)
            self.engine.prepare()
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

    func start() throws {
        try performOnMainThrowing {
            guard !self.isStarted || !self.engine.isRunning else { return }
            try self.engine.start()
            self.isStarted = true
        }
    }

    func stop() {
        performOnMain {
            guard self.isStarted || self.engine.isRunning else { return }
            self.engine.stop()
            self.isStarted = false
        }
    }

    func installMasterChains(_ chains: [MasterChain]) {
        graphLock.lock()
        defer { graphLock.unlock() }

        performOnMain {
            let wasRunning = self.engine.isRunning
            if wasRunning {
                self.engine.stop()
            }

            self.engine.disconnectNodeOutput(self.preMasterMixer)
            for node in self.managedMasterNodes {
                if node.engine === self.engine {
                    self.engine.disconnectNodeInput(node)
                    self.engine.disconnectNodeOutput(node)
                    self.engine.detach(node)
                }
            }
            self.managedMasterNodes = []

            let resolvedChains = chains.isEmpty ? [MasterChain(nodes: [], gain: 1)] : chains
            var firstDestinations: [AVAudioConnectionPoint] = []
            var branchReadouts: [MasterBranchReadout] = []

            for chain in resolvedChains {
                let gainMixer = AVAudioMixerNode()
                let clampedGain = Float(min(max(chain.gain, 0), 1.5))
                gainMixer.outputVolume = clampedGain
                self.engine.attach(gainMixer)
                self.managedMasterNodes.append(gainMixer)

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

                self.engine.connect(gainMixer, to: self.finalOutputMixer, format: nil)
                branchReadouts.append(MasterBranchReadout(nodes: chainNodes, gain: clampedGain))
            }

            self.masterBranchesForTesting = branchReadouts
            self.engine.connect(self.preMasterMixer, to: firstDestinations, fromBus: 0, format: nil)
            self.engine.prepare()

            if wasRunning {
                try? self.engine.start()
                self.isStarted = self.engine.isRunning
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
}
