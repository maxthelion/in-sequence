import AVFoundation
import XCTest
@testable import SequencerAI

final class MasterBusHostTests: XCTestCase {
    func test_equalPowerCrossfadeGains() {
        let left = MasterBusHost.equalPowerGains(crossfader: 0)
        XCTAssertEqual(left.a, 1, accuracy: 0.0001)
        XCTAssertEqual(left.b, 0, accuracy: 0.0001)

        let middle = MasterBusHost.equalPowerGains(crossfader: 0.5)
        XCTAssertEqual(middle.a, sqrt(0.5), accuracy: 0.0001)
        XCTAssertEqual(middle.b, sqrt(0.5), accuracy: 0.0001)

        let right = MasterBusHost.equalPowerGains(crossfader: 1)
        XCTAssertEqual(right.a, 0, accuracy: 0.0001)
        XCTAssertEqual(right.b, 1, accuracy: 0.0001)
    }

    func test_applyStoresNormalizedState() {
        let host = MasterBusHost()
        let scene = MasterBusScene(name: "  ", inserts: [
            MasterBusInsert(name: "", wetDry: 4, kind: .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 99_000, resonance: 9)))
        ])

        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))

        XCTAssertEqual(host.applyCallCount, 1)
        XCTAssertEqual(host.appliedState.activeScene.name, "Scene")
        XCTAssertEqual(host.appliedState.activeScene.inserts[0].wetDry, 1)
        guard case let .nativeFilter(settings) = host.appliedState.activeScene.inserts[0].kind else {
            return XCTFail("Expected filter")
        }
        XCTAssertEqual(settings.cutoffHz, 20_000)
        XCTAssertEqual(settings.resonance, 1)
    }

    @MainActor
    func test_applyInstallsNativeFilterOnAttachedGraph() {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        host.attach(to: graph)
        let scene = MasterBusScene(name: "Filter", inserts: [
            MasterBusInsert(name: "Filter", kind: .nativeFilter(.default))
        ])

        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))

        let preMasterOutputs = graph.engine.outputConnectionPoints(
            for: graph.preMasterMixer,
            outputBus: 0
        )
        XCTAssertEqual(preMasterOutputs.count, 1)
        XCTAssertTrue(preMasterOutputs[0].node is AVAudioUnitEQ)
    }

    @MainActor
    func test_applyInstallsNativeLoFiNodeOnAttachedGraph() throws {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        host.attach(to: graph)
        let scene = MasterBusScene(name: "LoFi", inserts: [
            MasterBusInsert(
                name: "LoFi",
                wetDry: 0.75,
                kind: .nativeBitcrusher(
                    MasterBitcrusherSettings(bitDepth: 6, sampleRateScale: 0.2, drive: 0.5)
                )
            )
        ])

        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))

        let branch = try XCTUnwrap(graph.masterBranchesForTesting.first)
        let distortion = try XCTUnwrap(branch.nodes.first as? AVAudioUnitDistortion)
        XCTAssertEqual(distortion.wetDryMix, 75, accuracy: 0.0001)
        XCTAssertEqual(distortion.preGain, 18, accuracy: 0.0001)
    }

    @MainActor
    func test_abModeInstallsTwoSceneBranchesWithEqualPowerGains() throws {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        let sceneA = MasterBusScene(name: "A")
        let sceneB = MasterBusScene(name: "B")
        host.attach(to: graph)

        host.apply(MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(
                sceneAID: sceneA.id,
                sceneBID: sceneB.id,
                crossfader: 0.5
            )
        ))

        XCTAssertEqual(graph.masterBranchesForTesting.count, 2)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, Float(sqrt(0.5)), accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[1].gain, Float(sqrt(0.5)), accuracy: 0.0001)
    }
}
