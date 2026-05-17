import AVFoundation
import XCTest
@testable import SequencerAI

final class MainAudioGraphTests: XCTestCase {
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

        XCTAssertTrue(readout.dryDestination === graph.preMasterMixer)
        XCTAssertEqual(sourceOutputs.count, 2)
        XCTAssertTrue(sourceOutputs.contains { $0.node === graph.preMasterMixer })
        XCTAssertTrue(sourceOutputs.contains { $0.node === readout.sendFanoutNode })
        XCTAssertEqual(readout.sendFanoutDestinations.count, 2)
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

        let readout = try XCTUnwrap(graph.trackSendReadoutForTesting(source))
        let outputsAfter = graph.engine.outputConnectionPoints(for: source, outputBus: 0).map(\.node)
        XCTAssertEqual(outputsBefore.count, outputsAfter.count)
        XCTAssertTrue(zip(outputsBefore, outputsAfter).allSatisfy { $0 === $1 })
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovalsBefore)
        XCTAssertEqual(readout.sendAGain, 0.6, accuracy: 0.0001)
        XCTAssertEqual(readout.sendBGain, 0.3, accuracy: 0.0001)
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
        publisher.stopPublishing()
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
        publisher.stopPublishing()
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
}

final class MasterMeterPublisherTests: XCTestCase {
    @MainActor
    func test_meterPublishesDisplayStateOnExplicitMainBoundary() {
        let publisher = MasterMeterPublisher()
        publisher.stopPublishing()

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
        publisher.stopPublishing()

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
        publisher.stopPublishing()

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
        publisher.stopPublishing()

        publisher.recordPeakAmplitudes(left: 1, right: 1)
        publisher.publishPendingToMain(now: 1)
        publisher.publishPendingToMain(now: 1.6)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterDisplayState.silenceDBFS)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterDisplayState.silenceDBFS)
    }

    @MainActor
    func test_peakHoldMaintainsMarkerThenReleasesTowardLivePeak() {
        let publisher = MasterMeterPublisher(peakHoldDuration: 0.5, peakHoldReleaseDBPerSecond: 10)
        publisher.stopPublishing()

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
}
