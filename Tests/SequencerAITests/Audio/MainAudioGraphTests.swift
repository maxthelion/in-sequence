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
}
