import AVFoundation
import XCTest
@testable import SequencerAI

final class MainAudioGraphTests: XCTestCase {
    /// Steady-state send-level changes now RAMP on a background queue (R4), so a
    /// readback immediately after `setTrackSendLevels` can be stale mid-ramp.
    /// Spin the main run loop until the live send gains settle (or time out).
    @MainActor
    private func waitForSendGains(
        _ graph: MainAudioGraph,
        source: AVAudioNode,
        sendA: Float,
        sendB: Float,
        accuracy: Float = 0.0005,
        timeout: TimeInterval = 1.0
    ) -> MainAudioGraph.TrackSendReadout? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: MainAudioGraph.TrackSendReadout?
        while Date() < deadline {
            last = graph.trackSendReadoutForTesting(source)
            if let r = last,
               abs(r.sendAGain - sendA) <= accuracy,
               abs(r.sendBGain - sendB) <= accuracy {
                return r
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return last
    }

    @MainActor
    func test_installMixerBuses_reusesHostsByStableIDAndTearsDownRemovedBuses() throws {
        let graph = MainAudioGraph()
        let busID = UUID()
        let otherBusID = UUID()
        let bus = MixerBus(id: busID, name: "Drums")

        graph.installMixerBuses([bus])
        let firstReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))

        graph.installMixerBuses([MixerBus(id: busID, name: "Drum Stem")])
        let reusedReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))

        XCTAssertTrue(firstReadout.inputMixer === reusedReadout.inputMixer)
        XCTAssertEqual(reusedReadout.topologyRebuildCount, 1)

        graph.installMixerBuses([MixerBus(id: otherBusID, name: "FX")])

        XCTAssertNil(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertNotNil(graph.mixerBusReadoutForTesting(busID: otherBusID))
    }

    @MainActor
    func test_connectTrackOutput_routesToMasterBusOrFailsSafeToMaster() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        let busID = UUID()
        graph.attach(source)
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])

        graph.connectTrackOutput(source, to: nil)
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === graph.preMasterMixer)

        graph.connectTrackOutput(source, to: busID)
        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer)

        graph.connectTrackOutput(source, to: UUID())
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === graph.preMasterMixer)
    }

    @MainActor
    func test_installMixerBuses_routesBusTerminalNodeToPreMasterMixer() throws {
        let graph = MainAudioGraph()
        let dryBusID = UUID()
        let insertedBusID = UUID()
        let filter = MixerBusInsert(
            name: "Filter",
            kind: .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 1_200, resonance: 0.2))
        )

        graph.installMixerBuses([
            MixerBus(id: dryBusID, name: "Dry"),
            MixerBus(id: insertedBusID, name: "Inserted", inserts: [filter]),
        ])

        let dryReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: dryBusID))
        XCTAssertTrue(dryReadout.terminalSourceNode === dryReadout.inputMixer)
        XCTAssertTrue(dryReadout.terminalOutputNode === graph.preMasterMixer)

        let insertedReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: insertedBusID))
        let terminalInsert = try XCTUnwrap(insertedReadout.insertNodes.last)
        XCTAssertTrue(insertedReadout.terminalSourceNode === terminalInsert)
        XCTAssertTrue(insertedReadout.terminalOutputNode === graph.preMasterMixer)
    }

    @MainActor
    func test_installSendBuses_createsFixedHostsReturningToFinalOutput() throws {
        let graph = MainAudioGraph()

        graph.installSendBuses([.sendA, .sendB])

        let sendA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let sendB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))
        XCTAssertTrue(sendA.terminalSourceNode === sendA.inputMixer)
        XCTAssertTrue(sendB.terminalSourceNode === sendB.inputMixer)
        XCTAssertTrue(sendA.terminalOutputNode === graph.sendReturnDestinationForTesting)
        XCTAssertTrue(sendB.terminalOutputNode === graph.sendReturnDestinationForTesting)
    }

    @MainActor
    func test_connectTrackOutputFansOutToDryPathAndFixedSendGains() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        graph.attach(source)
        graph.installSendBuses([.sendA, .sendB])

        graph.connectTrackOutput(
            source,
            to: nil,
            sends: MainAudioGraph.TrackSendLevels(sendA: 0.25, sendB: 0.75)
        )

        let readout = try XCTUnwrap(graph.trackSendReadoutForTesting(source))
        let sendA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let sendB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))
        let sourceOutputs = graph.engine.outputConnectionPoints(for: source, outputBus: 0)

        // R0 (fixed-superset): the dry signal routes THROUGH the fanout, so the
        // source drives only the fanout (one output), and the fanout fans out to
        // the dry destination + both send gains.
        XCTAssertTrue(readout.dryDestination === graph.preMasterMixer)
        XCTAssertEqual(sourceOutputs.count, 1)
        XCTAssertTrue(sourceOutputs.contains { $0.node === readout.sendFanoutNode })
        XCTAssertEqual(readout.sendFanoutDestinations.count, 3)
        XCTAssertTrue(readout.sendFanoutDestinations.contains { $0 === graph.preMasterMixer })
        XCTAssertTrue(readout.sendFanoutDestinations.contains { $0 === readout.sendAGainNode })
        XCTAssertTrue(readout.sendFanoutDestinations.contains { $0 === readout.sendBGainNode })
        XCTAssertTrue(readout.sendADestination === sendA.inputMixer)
        XCTAssertTrue(readout.sendBDestination === sendB.inputMixer)
        XCTAssertEqual(readout.sendAGain, 0.25, accuracy: 0.0001)
        XCTAssertEqual(readout.sendBGain, 0.75, accuracy: 0.0001)
    }

    @MainActor
    func test_setTrackSendLevelsUpdatesOnlyGainParametersWithoutGraphRebuild() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        graph.attach(source)
        graph.installSendBuses([.sendA, .sendB])
        graph.connectTrackOutput(
            source,
            to: nil,
            sends: MainAudioGraph.TrackSendLevels(sendA: 0.1, sendB: 0.2)
        )
        let outputsBefore = graph.engine.outputConnectionPoints(for: source, outputBus: 0).map(\.node)
        let tapRemovalsBefore = graph.masterMeterTapRemoveCountForTesting

        graph.setTrackSendLevels(source, sendA: 0.6, sendB: 0.3)

        // Steady-state send change RAMPS (R4) — poll past the ~12 ms ramp.
        let readout = try XCTUnwrap(waitForSendGains(graph, source: source, sendA: 0.6, sendB: 0.3))
        let outputsAfter = graph.engine.outputConnectionPoints(for: source, outputBus: 0).map(\.node)
        XCTAssertEqual(outputsBefore.count, outputsAfter.count)
        XCTAssertTrue(zip(outputsBefore, outputsAfter).allSatisfy { $0 === $1 })
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovalsBefore)
        XCTAssertEqual(readout.sendAGain, 0.6, accuracy: 0.0005)
        XCTAssertEqual(readout.sendBGain, 0.3, accuracy: 0.0005)
    }

    @MainActor
    func test_sendBusInsertEditRebuildsOnlyTargetSendBus() throws {
        let graph = MainAudioGraph()
        graph.installSendBuses([.sendA, .sendB])
        let initialA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let initialB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))

        let insert = SendBusInsert(name: "Send Filter", kind: .nativeFilter(.default))
        graph.installSendBus(SendBusState(id: .sendA, inserts: [insert]))

        let updatedA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let updatedB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))
        XCTAssertEqual(updatedA.topologyRebuildCount, initialA.topologyRebuildCount + 1)
        XCTAssertEqual(updatedA.insertNodes.count, 1)
        XCTAssertEqual(updatedB.topologyRebuildCount, initialB.topologyRebuildCount)
        XCTAssertTrue(updatedB.insertNodes.isEmpty)
    }

    @MainActor
    func test_installSendBus_valueOnlyInsertChangeDoesNotChangeTopologyOrStopEngine() throws {
        let graph = MainAudioGraph()
        let insertID = UUID()
        let insert = SendBusInsert(
            id: insertID,
            name: "Send Filter",
            wetDry: 1,
            kind: .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 1_000, resonance: 0.1))
        )
        graph.installSendBuses([SendBusState(id: .sendA, inserts: [insert]), .sendB])
        let installCountAfterShapeChange = graph.sendBusTopologyInstallCountForTesting
        let initialReadout = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let tapRemovalsBefore = graph.masterMeterTapRemoveCountForTesting

        // Drag-rate value change (cutoff move): same shape, parameter-only.
        var movedInsert = insert
        movedInsert.kind = .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 4_000, resonance: 0.1))
        graph.installSendBus(SendBusState(id: .sendA, inserts: [movedInsert]))

        let afterValueChange = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        XCTAssertEqual(graph.sendBusTopologyInstallCountForTesting, installCountAfterShapeChange,
                       "value-only send-FX changes must not run the engine stop/reinstall/start cycle")
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovalsBefore)
        XCTAssertEqual(afterValueChange.topologyRebuildCount, initialReadout.topologyRebuildCount)
        XCTAssertEqual(afterValueChange.parameterApplyCount, initialReadout.parameterApplyCount + 1)
        let eq = try XCTUnwrap(afterValueChange.insertNodes.first as? AVAudioUnitEQ)
        XCTAssertEqual(eq.bands[0].frequency, 4_000, accuracy: 0.0001)

        // Shape change (insert removed) still rebuilds topology.
        graph.installSendBus(SendBusState(id: .sendA, inserts: []))
        XCTAssertEqual(graph.sendBusTopologyInstallCountForTesting, installCountAfterShapeChange + 1)
    }

    @MainActor
    func test_installSendBus_inlineAUInstantiationCompletesWithoutDeadlockAndWiresNode() throws {
        // Regression pin for the live-sampled "+ Add FX" self-deadlock: an AU
        // factory that completes INLINE (synchronously, on main) used to
        // re-enter installSendBus while installSendBuses still held the
        // non-recursive graph lock — wedging main forever. The fix defers the
        // re-entry to the next main-queue turn.
        let graph = MainAudioGraph()
        let effect = AVAudioUnitEQ(numberOfBands: 1)
        let factory = AUAudioUnitFactory { _, completion in
            completion(effect, nil)
        }
        let host = SendBusHost(id: .sendA, factory: factory)
        graph.installSendBusHostForTesting(host)
        let insert = SendBusInsert(
            name: "AU FX",
            kind: .auEffect(componentID: AudioEffectChoice.testEffect.audioComponentID, stateBlob: nil)
        )

        // Before the fix this call never returned (main-thread self-deadlock
        // on graphLock).
        graph.installSendBus(SendBusState(id: .sendA, inserts: [insert]))

        // The deferred re-install lands on the next main-queue turns and must
        // wire the loaded AU into the chain (pins installedShape reflecting
        // only actually-installed inserts).
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if graph.sendBusReadoutForTesting(busID: .sendA)?.insertNodes.count == 1 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let readout = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        XCTAssertEqual(readout.insertNodes.count, 1)
        XCTAssertTrue(readout.insertNodes.first === effect)
    }

    @MainActor
    func test_setTrackSendLevels_zeroSendValueChangeDoesNotReconnectTrackOutput() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        graph.attach(source)
        graph.installSendBuses([.sendA, .sendB])
        graph.connectTrackOutput(source, to: nil, sends: .zero)
        let reconnectsAfterSetup = graph.reconnectTrackOutputCountForTesting

        // R0 (fixed-superset): send nodes are persistent once the buses exist,
        // so NO send-level change after setup ever rewires the graph. Zero
        // drags, crossing 0 -> active, active moves, and returning to zero are
        // all pure outputVolume writes — the reconnect count never moves.
        graph.setTrackSendLevels(source, sendA: 0, sendB: 0)
        graph.setTrackSendLevels(source, sendA: 0, sendB: 0)
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup)

        // Crossing 0 -> active: parameter-only (nodes already exist).
        graph.setTrackSendLevels(source, sendA: 0.4, sendB: 0)
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup)

        // Active-value moves stay parameter-only.
        graph.setTrackSendLevels(source, sendA: 0.5, sendB: 0)
        graph.setTrackSendLevels(source, sendA: 0.6, sendB: 0.1)
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup)
        // Steady-state send change RAMPS (R4) — poll past the ramp.
        let readout = try XCTUnwrap(waitForSendGains(graph, source: source, sendA: 0.6, sendB: 0.1))
        XCTAssertEqual(readout.sendAGain, 0.6, accuracy: 0.0005)
        XCTAssertEqual(readout.sendBGain, 0.1, accuracy: 0.0005)

        // Returning to zero does NOT tear nodes down: still no reconnect, and
        // the gains simply ramp to 0.
        graph.setTrackSendLevels(source, sendA: 0, sendB: 0)
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup)
        let zeroedReadout = try XCTUnwrap(waitForSendGains(graph, source: source, sendA: 0, sendB: 0))
        XCTAssertEqual(zeroedReadout.sendAGain, 0, accuracy: 0.0005)
        XCTAssertEqual(zeroedReadout.sendBGain, 0, accuracy: 0.0005)
    }

    /// R4: a steady-state send-level change (the send nodes already exist) takes
    /// the glitch-free RAMP path — `sendRampCountForTesting` increments per
    /// change and the gains settle on target — WITHOUT any topology reconnect.
    /// This is the A/A+B/B-switch click fix: a live switch must ramp, not jump.
    @MainActor
    func test_setTrackSendLevels_steadyState_takesRampPath_noReconnect() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        graph.attach(source)
        graph.installSendBuses([.sendA, .sendB])
        // Establish the persistent send nodes (first apply = setup write).
        graph.connectTrackOutput(source, to: nil, sends: .zero)
        let reconnectsAfterSetup = graph.reconnectTrackOutputCountForTesting
        let rampsAfterSetup = graph.sendRampCountForTesting

        // A: sendA=1, sendB=0. Steady-state → RAMP.
        graph.setTrackSendLevels(source, sendA: 1, sendB: 0)
        XCTAssertEqual(graph.sendRampCountForTesting, rampsAfterSetup + 1,
                       "a live (steady-state) send-level change must take the ramp path")
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup,
                       "a pure send-gain change must NOT reconnect the track output")
        let a = try XCTUnwrap(waitForSendGains(graph, source: source, sendA: 1, sendB: 0))
        XCTAssertEqual(a.sendAGain, 1, accuracy: 0.0005)
        XCTAssertEqual(a.sendBGain, 0, accuracy: 0.0005, "A-only contributes nothing to B")

        // B: sendA=0, sendB=1. Another ramp, still no reconnect.
        graph.setTrackSendLevels(source, sendA: 0, sendB: 1)
        XCTAssertEqual(graph.sendRampCountForTesting, rampsAfterSetup + 2)
        XCTAssertEqual(graph.reconnectTrackOutputCountForTesting, reconnectsAfterSetup)
        let b = try XCTUnwrap(waitForSendGains(graph, source: source, sendA: 0, sendB: 1))
        XCTAssertEqual(b.sendAGain, 0, accuracy: 0.0005, "B-only contributes nothing to A")
        XCTAssertEqual(b.sendBGain, 1, accuracy: 0.0005)
    }

    @MainActor
    func test_mixerBusMixAndBypassStayParameterOnlyWhileInsertShapeRebuildsTopology() throws {
        let graph = MainAudioGraph()
        let busID = UUID()
        let insertID = UUID()
        let insert = MixerBusInsert(
            id: insertID,
            name: "Filter",
            isEnabled: true,
            kind: .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 1_000, resonance: 0.1))
        )
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums", inserts: [insert])])
        let initialReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))

        graph.setMixerBusMix(
            busID: busID,
            mix: BusMixSettings(level: 0.5, pan: -0.25, isMuted: false, isSoloed: false),
            effectiveMute: false
        )
        let afterMix = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertEqual(afterMix.topologyRebuildCount, initialReadout.topologyRebuildCount)
        XCTAssertEqual(afterMix.outputVolume, 0.5, accuracy: 0.0001)
        XCTAssertEqual(afterMix.pan, -0.25, accuracy: 0.0001)

        var bypassedInsert = insert
        bypassedInsert.isEnabled = false
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums", inserts: [bypassedInsert])])
        let afterBypass = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertEqual(afterBypass.topologyRebuildCount, initialReadout.topologyRebuildCount)
        let eq = try XCTUnwrap(afterBypass.insertNodes.first as? AVAudioUnitEQ)
        XCTAssertTrue(eq.bands[0].bypass)

        let extraInsert = MixerBusInsert(name: "Crush", kind: .nativeBitcrusher(.default))
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums", inserts: [bypassedInsert, extraInsert])])
        let afterShapeChange = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertEqual(afterShapeChange.topologyRebuildCount, initialReadout.topologyRebuildCount + 1)
    }

    @MainActor
    func test_installMasterChains_connectsInsertOrderBetweenPreMasterAndOutput() throws {
        let graph = MainAudioGraph()
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        let distortion = AVAudioUnitDistortion()

        graph.installMasterChains([
            MainAudioGraph.MasterChain(nodes: [filter, distortion], gain: 0.25)
        ])

        let preMasterOutputs = graph.engine.outputConnectionPoints(
            for: graph.preMasterMixer,
            outputBus: 0
        )
        XCTAssertEqual(preMasterOutputs.count, 1)
        XCTAssertTrue(preMasterOutputs[0].node === filter)

        let filterOutputs = graph.engine.outputConnectionPoints(for: filter, outputBus: 0)
        XCTAssertEqual(filterOutputs.count, 1)
        XCTAssertTrue(filterOutputs[0].node === distortion)

        XCTAssertEqual(graph.masterBranchesForTesting.count, 1)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, 0.25, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[0].nodes.count, 2)
        XCTAssertTrue(graph.masterBranchesForTesting[0].nodes[0] === filter)
        XCTAssertTrue(graph.masterBranchesForTesting[0].nodes[1] === distortion)
    }

    @MainActor
    func test_installMasterChains_fansOutBranchesWithIndependentGains() throws {
        let graph = MainAudioGraph()

        graph.installMasterChains([
            MainAudioGraph.MasterChain(nodes: [], gain: 1),
            MainAudioGraph.MasterChain(nodes: [], gain: 0.5),
        ])

        XCTAssertEqual(graph.masterBranchesForTesting.count, 2)
        XCTAssertEqual(graph.masterBranchesForTesting[0].nodes.count, 0)
        XCTAssertEqual(graph.masterBranchesForTesting[1].nodes.count, 0)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, 1, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[1].gain, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func test_installMasterChains_placesMasterInsertsAfterBranchMix() throws {
        let graph = MainAudioGraph()
        let sceneFilter = AVAudioUnitEQ(numberOfBands: 1)
        let masterLimiter = AVAudioUnitDistortion()

        graph.installMasterChains(
            [
                MainAudioGraph.MasterChain(nodes: [sceneFilter], gain: 0.25),
                MainAudioGraph.MasterChain(nodes: [], gain: 0.75),
            ],
            postBlendMasterNodes: [masterLimiter],
            masterOutputGain: 0.8
        )

        XCTAssertEqual(graph.masterBranchesForTesting.count, 2)
        XCTAssertTrue(graph.masterBranchesForTesting[0].nodes.first === sceneFilter)
        XCTAssertEqual(graph.postBlendMasterInsertNodesForTesting.count, 1)
        XCTAssertTrue(graph.postBlendMasterInsertNodesForTesting[0] === masterLimiter)
        XCTAssertEqual(graph.masterOutputGainForTesting, 0.8, accuracy: 0.0001)
    }

    @MainActor
    func test_masterHostConfiguresNativeFilterNodeInSharedGraph() throws {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        host.attach(to: graph)

        let scene = MasterBusScene(
            name: "Highpass",
            inserts: [
                MasterBusInsert(
                    name: "Highpass",
                    kind: .nativeFilter(
                        MasterFilterSettings(mode: .highPass, cutoffHz: 10_000, resonance: 0.2)
                    )
                )
            ]
        )
        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))

        let branch = try XCTUnwrap(graph.masterBranchesForTesting.first)
        let eq = try XCTUnwrap(branch.nodes.first as? AVAudioUnitEQ)
        let band = eq.bands[0]
        XCTAssertFalse(band.bypass)
        XCTAssertEqual(band.filterType, .highPass)
        XCTAssertEqual(band.frequency, 10_000, accuracy: 0.0001)
    }

    @MainActor
    func test_masterMeterTapUsesFinalOutputAndReinstallsAcrossGraphRebuilds() {
        let publisher = MasterMeterPublisher()
        let graph = MainAudioGraph(masterMeterPublisher: publisher)

        XCTAssertEqual(graph.masterMeterTapPointForTesting, .finalOutputMixer)
        XCTAssertTrue(graph.isMasterMeterTapInstalledForTesting)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, 1)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, 0)

        graph.installMasterChains([], masterOutputGain: 0.5)

        XCTAssertEqual(graph.masterOutputGainForTesting, 0.5, accuracy: 0.0001)
        XCTAssertEqual(graph.masterMeterTapPointForTesting, .finalOutputMixer)
        XCTAssertTrue(graph.isMasterMeterTapInstalledForTesting)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, 2)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, 1)

        graph.stop()

        XCTAssertFalse(graph.isMasterMeterTapInstalledForTesting)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, 2)
    }

    @MainActor
    func test_masterMeterIgnoresStaleTapGenerationAfterGraphRebuild() {
        let publisher = MasterMeterPublisher()
        let graph = MainAudioGraph(masterMeterPublisher: publisher)
        let staleGeneration = graph.masterMeterTapGenerationForTesting

        graph.installMasterChains([])
        graph.recordMasterMeterPeakForTesting(left: 1.4, right: 1.4, generation: staleGeneration)
        publisher.publishPendingToMain(now: 1)

        XCTAssertFalse(publisher.displayState.isClipLatched)
        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterDisplayState.silenceDBFS)

        graph.recordMasterMeterPeakForTesting(left: 1.4, right: 0.25)
        publisher.publishPendingToMain(now: 2)

        XCTAssertTrue(publisher.displayState.isClipLatched)
        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 1.4), accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 0.25), accuracy: 0.0001)
    }

    // MARK: - Deinit teardown liveness (bug 20260702-140500)

    private final class GraphBox: @unchecked Sendable {
        var graph: MainAudioGraph?
        init(_ graph: MainAudioGraph) { self.graph = graph }
    }

    /// Bug 20260702-140500: `MainAudioGraph.deinit` used to remove the master
    /// meter tap through `performOnMain` — a SYNCHRONOUS main hop. Deinit runs
    /// on whatever thread drops the last strong reference; sampled in the wild
    /// that thread was CoreAudio's `RealtimeMessenger.mServiceQueue` (the tap
    /// callback's `guard let self` upgrade was the final reference), which was
    /// holding the messenger's recursive mutex mid-perform. The sync hop to
    /// main deadlocked against ANOTHER graph's deinit already on main inside
    /// `removeTapOnBus` → `_PerformPendingMessages()` waiting for that same
    /// mutex — wedging the whole test host (the ~990 s full-suite stalls).
    ///
    /// This pins the invariant deterministically: dropping the last reference
    /// off-main must complete WITHOUT the main thread servicing its queue.
    func test_deinit_offMainThread_completesWithoutSynchronousMainHop() {
        let box = GraphBox(MainAudioGraph(engine: AVAudioEngine()))
        let released = DispatchSemaphore(value: 0)
        DispatchQueue(label: "test.mainaudiograph.deinit.offmain").async {
            box.graph = nil
            released.signal()
        }
        // Deliberately block the test's main thread WITHOUT running the run
        // loop: if deinit needs a synchronous main-queue hop, this times out.
        XCTAssertEqual(
            released.wait(timeout: .now() + 5), .success,
            "MainAudioGraph.deinit must never synchronously wait on the main thread"
        )
        // Drain the deferred (async-to-main) tap teardown so it cannot leak
        // into the next test.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    /// Regression for the record-arm crash mechanism (bug 20260702-123512,
    /// QA row 26-audio-recording; standalone-repro-proven AVFAudio poison):
    /// `disconnectNodeOutput`/`detach` on a node holding a MULTI-POINT (1→N)
    /// output connection — the per-track send FANOUT splitter — while the
    /// engine is STOPPED, followed by a restart with that node left
    /// disconnected, corrupts `AVAudioEngineGraph`'s bookkeeping. The next
    /// disconnect on the RUNNING engine then dies inside
    /// `UpdateGraphAfterReconfig` (SIGSEGV at 0x68, null-AUInterface virtual
    /// call) at an unrelated call site. The app hit this exactly when the QA
    /// fixture replaced the audio-input track: `syncAudioInputRoutings`'
    /// stopped full rebuild tore down the host's fanout, and the NEXT
    /// apply's first disconnect (bus-terminal rewire / prepared-track
    /// repair) crashed.
    ///
    /// Drives that exact sequence through the graph API: install an `.input`
    /// host WITH send buses (fanout = dry+sendA+sendB multi-point), start,
    /// tear the host down via a stopped full rebuild, then perform a
    /// running-engine disconnect. Pre-fix this test CRASHES the host; the
    /// fix dissolves the fanout's edges point-by-point from the destination
    /// side (`dissolveOutputConnectionsOnMain`) so every edge is gone before
    /// detach and the walk never sees the poisoned multi-point entry.
    @MainActor
    func test_inputHostTeardownAcrossStoppedRebuild_doesNotPoisonNextDisconnect() throws {
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        defer { MainAudioGraph.simulateAudioInputConnectionForTesting = false }
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        // Send buses first: the host's track output then routes through the
        // persistent fanout splitter (dry + sendA + sendB = 1→3 multi-point).
        graph.installSendBuses([.sendA, .sendB])
        let trackID = UUID()
        graph.syncAudioInputRoutings([
            MainAudioGraph.AudioInputRoutingRequest(
                trackID: trackID,
                source: .input,
                selectedChannel: .stereo(firstChannel: 0),
                outputBusID: nil,
                mix: .default
            ),
        ])
        try graph.start()
        XCTAssertTrue(graph.isEngineRunning)

        // Track replace: the host teardown runs inside the STOPPED full
        // rebuild — the poisonous window pre-fix.
        graph.syncAudioInputRoutings([])
        XCTAssertTrue(graph.isEngineRunning, "full rebuild restarts a previously running engine")

        // The next running-engine disconnect — the production crash site.
        let probe = AVAudioMixerNode()
        graph.attach(probe)
        graph.connect(probe, to: graph.sendReturnDestinationForTesting)
        graph.disconnectOutput(probe)
        graph.detach(probe)
    }
}

final class MasterMeterPublisherTests: XCTestCase {
    @MainActor
    func test_meterPublishesDisplayStateOnExplicitMainBoundary() {
        let publisher = MasterMeterPublisher()

        publisher.recordPeakAmplitudes(left: 0.5, right: 1.25)

        XCTAssertEqual(publisher.displayState, .silent)

        publisher.publishPendingToMain(now: 1)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, -6.0206, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, 1.9382, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, publisher.displayState.leftPeakDBFS)
        XCTAssertEqual(publisher.displayState.rightPeakHoldDBFS, publisher.displayState.rightPeakDBFS)
        XCTAssertTrue(publisher.displayState.isClipLatched)
        XCTAssertTrue(publisher.displayState.isClearClipActionable)

        publisher.clearClip()

        XCTAssertFalse(publisher.displayState.isClipLatched)
        XCTAssertFalse(publisher.displayState.isClearClipActionable)
    }

    @MainActor
    func test_meterPublishesHighestChannelPeaksRecordedSincePreviousPublish() {
        let publisher = MasterMeterPublisher()

        publisher.recordPeakAmplitudes(left: 0.9, right: 0.7)
        publisher.recordPeakAmplitudes(left: 0.2, right: 0.3)
        publisher.publishPendingToMain(now: 1)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 0.9), accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 0.7), accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, publisher.displayState.leftPeakDBFS)
        XCTAssertEqual(publisher.displayState.rightPeakHoldDBFS, publisher.displayState.rightPeakDBFS)

        publisher.recordPeakAmplitudes(left: 0.1, right: 0.2)
        publisher.publishPendingToMain(now: 2)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 0.1), accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterPublisher.dbFS(amplitude: 0.2), accuracy: 0.0001)
    }

    @MainActor
    func test_meterDisplayReleasesSmoothlyWhenNoAudioArrives() {
        let publisher = MasterMeterPublisher(levelReleaseDBPerSecond: 12)

        publisher.recordPeakAmplitudes(left: 1, right: 1)
        publisher.publishPendingToMain(now: 1)
        publisher.publishPendingToMain(now: 1.25)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, -3, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, -3, accuracy: 0.0001)
        XCTAssertFalse(publisher.displayState.isClipLatched)
    }

    @MainActor
    func test_meterDisplayReturnsToSilentStateWhenNoAudioArrivesPastFloor() {
        let publisher = MasterMeterPublisher(levelReleaseDBPerSecond: 120)

        publisher.recordPeakAmplitudes(left: 1, right: 1)
        publisher.publishPendingToMain(now: 1)
        publisher.publishPendingToMain(now: 1.6)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterDisplayState.silenceDBFS)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterDisplayState.silenceDBFS)
    }

    @MainActor
    func test_peakHoldMaintainsMarkerThenReleasesTowardLivePeak() {
        let publisher = MasterMeterPublisher(peakHoldDuration: 0.5, peakHoldReleaseDBPerSecond: 10)

        publisher.recordPeakAmplitudes(left: 1, right: 1)
        publisher.publishPendingToMain(now: 1)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, 0, accuracy: 0.0001)

        publisher.recordPeakAmplitudes(left: 0.1, right: 0.1)
        publisher.publishPendingToMain(now: 1.25)
        XCTAssertEqual(publisher.displayState.leftPeakDBFS, -10.5, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, 0, accuracy: 0.0001)

        publisher.publishPendingToMain(now: 1.75)

        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, -5, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakHoldDBFS, -5, accuracy: 0.0001)
    }

    /// The capture-format read at record start was the last waived tick-path
    /// main hop; it now reads a snapshot that main publishes at every
    /// routing sync. Pins both halves: the snapshot is published (a valid
    /// format comes back for a connected host, nil after it goes silent or
    /// is torn down), and reading it from a marked tick thread fires NO
    /// guard violation — the trap-by-default guard would otherwise crash
    /// every DEBUG record start.
    func test_audioInputCaptureFormat_readsPublishedSnapshotWithoutMainHop() throws {
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        defer { MainAudioGraph.simulateAudioInputConnectionForTesting = false }

        let graph = MainAudioGraph()
        let trackID = UUID()
        let request = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: nil,
            mix: .default
        )
        graph.syncAudioInputRoutings([request])

        var violations: [String] = []
        TickPathMainSyncGuard.violationHandlerForTesting = { violations.append($0) }
        defer { TickPathMainSyncGuard.violationHandlerForTesting = nil }

        let formatBox = NSMutableArray()
        let tickQueue = DispatchQueue(label: "test.capture-format-snapshot")
        tickQueue.sync {
            TickPathMainSyncGuard.withTickPathMarker {
                if let format = graph.audioInputCaptureFormat(trackID: trackID) {
                    formatBox.add(format)
                }
            }
        }

        XCTAssertEqual(violations, [], "snapshot read must not hop to main from the tick path")
        let format = try XCTUnwrap(formatBox.firstObject as? AVAudioFormat)
        XCTAssertGreaterThan(format.sampleRate, 0)
        XCTAssertGreaterThan(format.channelCount, 0)
        XCTAssertNil(graph.audioInputCaptureFormat(trackID: UUID()), "unknown track has no snapshot entry")

        // Going silent republishes: the stale format must not survive.
        let silentRequest = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .silent,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: nil,
            mix: .default
        )
        graph.syncAudioInputRoutings([silentRequest])
        XCTAssertNil(graph.audioInputCaptureFormat(trackID: trackID))

        // Reconnect, then tear the host down entirely.
        graph.syncAudioInputRoutings([request])
        XCTAssertNotNil(graph.audioInputCaptureFormat(trackID: trackID))
        graph.syncAudioInputRoutings([])
        XCTAssertNil(graph.audioInputCaptureFormat(trackID: trackID))
    }

    /// Regression for the audio-input MUTE-ESCAPE on a routing change
    /// (docs/bugs/20260626-route-to-master-intermittent-silence, finding B):
    /// the audio-input host's outputMixer is the track's gain stage, but its
    /// mute/level used to be written DIRECTLY to `outputMixer.outputVolume`,
    /// bypassing MixerGainRamp. So `settledTargetByNode[outputMixer]` stayed at a
    /// prior AUDIBLE level after a mute. A later routing change runs the
    /// ramp-to-silence restore, which reads the (stale, audible) settled target —
    /// and AUDIBLY UN-MUTES a muted track. The fix routes the host's mute/level
    /// writes THROUGH MixerGainRamp.setImmediate so settledTarget always tracks
    /// the intended rest level; a routing change on a muted track stays silent.
    ///
    /// Graph/engine-state level — no mic (simulateAudioInputConnection). Proven
    /// to FAIL on the pre-fix direct-write code (restore ramped back to ~0.8).
    @MainActor
    func test_audioInputMute_thenRoutingChange_staysSilent_noMuteEscape() throws {
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        defer { MainAudioGraph.simulateAudioInputConnectionForTesting = false }
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        graph.installSendBuses([.sendA, .sendB])
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "FX")])
        let trackID = UUID()

        // 1. Audible on master.
        let audibleMaster = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: nil,
            mix: TrackMixSettings(level: 0.8, pan: 0, isMuted: false)
        )
        graph.syncAudioInputRoutings([audibleMaster])
        try graph.start()
        let mixer = try XCTUnwrap(
            graph.audioInputRoutingReadoutForTesting(trackID: trackID)?.outputMixer
        )

        // 2. Reroute WHILE AUDIBLE (master -> bus). This takes the ramp-to-silence
        //    path; its restore ramps the gain stage back up and RECORDS the
        //    settled target = 0.8. This is the prior-route step that seeds the
        //    stale settled target the bug depends on.
        let audibleBus = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: busID,
            mix: TrackMixSettings(level: 0.8, pan: 0, isMuted: false)
        )
        graph.updateAudioInputRoutingParameters([audibleBus])
        // Let the reroute ramp + restore settle back to the audible level.
        let restored = Date().addingTimeInterval(1.0)
        while Date() < restored, mixer.outputVolume < 0.75 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(mixer.outputVolume, 0.8, accuracy: 0.05, "audible reroute restores the gain stage")

        // 3. MUTE (same bus — a pure level/mute write, NOT a reroute). With the
        //    fix this goes through MixerGainRamp.setImmediate so settledTarget
        //    becomes 0; with the old code it was a direct outputVolume write and
        //    settledTarget stayed stale at 0.8 (the seed from step 2).
        let mutedBus = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: busID,
            mix: TrackMixSettings(level: 0.8, pan: 0, isMuted: true)
        )
        graph.updateAudioInputRoutingParameters([mutedBus])
        XCTAssertEqual(mixer.outputVolume, 0, accuracy: 0.001, "mute must silence the gain stage")

        // 4. Routing change while MUTED (bus -> master): the reroute runs the
        //    ramp-to-silence restore. It must restore to the SETTLED level (0,
        //    muted), not the stale audible target seeded in step 2. With the old
        //    code it ramped back to ~0.8 — the mute escape.
        let mutedRerouted = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: nil,
            mix: TrackMixSettings(level: 0.8, pan: 0, isMuted: true)
        )
        graph.updateAudioInputRoutingParameters([mutedRerouted])

        // Spin the run loop past the ~12 ms ramp + restore; the muted track must
        // STAY silent throughout and after.
        let deadline = Date().addingTimeInterval(1.0)
        var maxObserved: Float = mixer.outputVolume
        while Date() < deadline {
            maxObserved = max(maxObserved, mixer.outputVolume)
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertLessThan(
            maxObserved, 0.05,
            "a routing change on a MUTED audio-input track must not un-mute it (mute escape)"
        )
        XCTAssertLessThan(mixer.outputVolume, 0.05, "muted track must rest silent after the reroute")

        graph.stop()
    }

    // MARK: - Track insert chain splice (no render cycle)

    /// Walk the engine graph UPSTREAM from `start` (via per-input-bus
    /// connection points, which never trip AVAudioEngine's output-splitter
    /// precondition) and assert no node is reachable from itself. A feedback
    /// cycle in either direction is the unbounded render recursion this bug
    /// produces.
    @MainActor
    private func assertNoCycle(
        from start: AVAudioNode,
        in graph: MainAudioGraph,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var onPath: Set<ObjectIdentifier> = []
        var fullyExplored: Set<ObjectIdentifier> = []
        func visit(_ node: AVAudioNode) -> [AVAudioNode]? {
            let id = ObjectIdentifier(node)
            if onPath.contains(id) { return [node] }
            if fullyExplored.contains(id) { return nil }
            onPath.insert(id)
            for bus in 0..<node.numberOfInputs {
                guard let point = graph.engine.inputConnectionPoint(for: node, inputBus: bus),
                      let upstream = point.node else { continue }
                if var trail = visit(upstream) {
                    trail.append(node)
                    return trail
                }
            }
            onPath.remove(id)
            fullyExplored.insert(id)
            return nil
        }
        if let trail = visit(start) {
            XCTFail(
                "render graph cycle detected: \(trail.reversed().map { String(describing: type(of: $0)) }.joined(separator: " -> "))",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func test_addingSecondTrackInsertWithActiveSendDoesNotCreateRenderCycle() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        graph.attach(source)
        graph.installSendBuses([.sendA, .sendB])

        let trackID = UUID()
        graph.setTrackMeterSources(trackIDs: [trackID], node: source)
        // Mirrors the "Sample Lead" fixture: routed to master with an active
        // send. The active send keeps the persistent fanout wired (R0), which
        // is exactly the path that regressed.
        graph.connectTrackOutput(
            source,
            to: nil,
            sends: MainAudioGraph.TrackSendLevels(sendA: 0.6, sendB: 0)
        )
        assertNoCycle(from: graph.sendReturnDestinationForTesting, in: graph)

        // Capture the established send-bus legs. The fix's core invariant is
        // that these LIVE legs are never re-added on a later insert/value
        // reconnect — re-adding a live send leg into a running send-bus mixer is
        // what wedged the CoreAudio render reconfigure into the unbounded
        // AllocateInputBlock recursion.
        let baseline = try XCTUnwrap(graph.trackSendReadoutForTesting(source))
        let sendA = try XCTUnwrap(baseline.sendAGainNode)
        let sendB = try XCTUnwrap(baseline.sendBGainNode)
        let sendADestBefore = try XCTUnwrap(baseline.sendADestination)
        let sendBDestBefore = try XCTUnwrap(baseline.sendBDestination)

        // First insert: source -> insert0 -> fanout -> [dry, sendA, sendB].
        let insert0 = TrackFXInsert.filter()
        graph.setTrackInserts(trackID: trackID, inserts: [insert0])
        assertNoCycle(from: graph.sendReturnDestinationForTesting, in: graph)

        // Second insert: source -> insert0 -> insert1 -> fanout -> ...
        let insert1 = TrackFXInsert.bitcrusher()
        graph.setTrackInserts(trackID: trackID, inserts: [insert0, insert1])
        assertNoCycle(from: graph.sendReturnDestinationForTesting, in: graph)

        // The chain terminal must feed the fanout, and the raw source must NOT
        // feed the fanout directly once a chain exists (the regressed leg).
        let readout = try XCTUnwrap(graph.trackSendReadoutForTesting(source))
        let fanoutNode = try XCTUnwrap(readout.sendFanoutNode)
        let fanoutInputs = (0..<fanoutNode.numberOfInputs).compactMap {
            graph.engine.inputConnectionPoint(for: fanoutNode, inputBus: $0)?.node
        }
        XCTAssertTrue(fanoutInputs.allSatisfy { $0 !== source },
                      "fanout must be fed by the insert chain terminal, not the raw source")
        XCTAssertEqual(fanoutInputs.count, 1, "fanout has exactly one upstream feed (the chain terminal)")

        // Invariant: the send gain nodes and their send-bus destinations are
        // the SAME objects after the insert edits — the legs were left in
        // place, not re-added (which is what avoided the render recursion).
        XCTAssertTrue(readout.sendAGainNode === sendA, "sendA gain node must be the same persistent node")
        XCTAssertTrue(readout.sendBGainNode === sendB, "sendB gain node must be the same persistent node")
        XCTAssertTrue(readout.sendADestination === sendADestBefore,
                      "sendA -> send-bus destination must be preserved across insert edits")
        XCTAssertTrue(readout.sendBDestination === sendBDestBefore,
                      "sendB -> send-bus destination must be preserved across insert edits")

        // Idempotent removal back to a single insert, then to none.
        graph.setTrackInserts(trackID: trackID, inserts: [insert0])
        assertNoCycle(from: graph.sendReturnDestinationForTesting, in: graph)
        graph.setTrackInserts(trackID: trackID, inserts: [])
        assertNoCycle(from: graph.sendReturnDestinationForTesting, in: graph)

        // Send legs still preserved after the full add/remove cycle.
        let final = try XCTUnwrap(graph.trackSendReadoutForTesting(source))
        XCTAssertTrue(final.sendAGainNode === sendA, "sendA node preserved through add/remove cycle")
        XCTAssertTrue(final.sendBGainNode === sendB, "sendB node preserved through add/remove cycle")
        XCTAssertTrue(final.sendADestination === sendADestBefore, "sendA dest preserved through add/remove cycle")
        XCTAssertTrue(final.sendBDestination === sendBDestBefore, "sendB dest preserved through add/remove cycle")
    }
}
