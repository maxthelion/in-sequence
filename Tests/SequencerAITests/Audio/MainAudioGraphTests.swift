import AVFoundation
import XCTest
@testable import SequencerAI

final class MainAudioGraphTests: XCTestCase {
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
        XCTAssertEqual(band.bandwidth, 1.62, accuracy: 0.0001)
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
    func test_peakHoldMaintainsMarkerThenReleasesTowardLivePeak() {
        let publisher = MasterMeterPublisher(peakHoldDuration: 0.5, peakHoldReleaseDBPerSecond: 10)
        publisher.stopPublishing()

        publisher.recordPeakAmplitudes(left: 1, right: 1)
        publisher.publishPendingToMain(now: 1)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, 0, accuracy: 0.0001)

        publisher.recordPeakAmplitudes(left: 0.1, right: 0.1)
        publisher.publishPendingToMain(now: 1.25)
        XCTAssertEqual(publisher.displayState.leftPeakDBFS, -20, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, 0, accuracy: 0.0001)

        publisher.publishPendingToMain(now: 1.75)

        XCTAssertEqual(publisher.displayState.leftPeakHoldDBFS, -5, accuracy: 0.0001)
        XCTAssertEqual(publisher.displayState.rightPeakHoldDBFS, -5, accuracy: 0.0001)
    }
}
