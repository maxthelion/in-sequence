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
        XCTAssertEqual(host.appliedState.scenes.count, 2)
        XCTAssertNotNil(host.appliedState.abSelection)
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

        XCTAssertEqual(graph.masterBranchesForTesting.count, 2)
        XCTAssertTrue(graph.masterBranchesForTesting[0].nodes.first is AVAudioUnitEQ)
        XCTAssertEqual(graph.masterBranchesForTesting[1].nodes.count, 0)
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
        let sceneA = MasterBusScene(name: "A", outputGain: 0.2)
        let sceneB = MasterBusScene(name: "B", outputGain: 1.5)
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
        XCTAssertEqual(host.appliedState.scene(id: sceneA.id)?.outputGain, 1)
        XCTAssertEqual(host.appliedState.scene(id: sceneB.id)?.outputGain, 1)
    }

    @MainActor
    func test_masterOutputGainAppliesToFinalOutputWithoutChangingBranchMath() {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        let sceneA = MasterBusScene(name: "A")
        let sceneB = MasterBusScene(name: "B")
        host.attach(to: graph)

        host.apply(MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(sceneAID: sceneA.id, sceneBID: sceneB.id, crossfader: 0.5),
            masterOutputGain: 0.4
        ))

        XCTAssertEqual(graph.masterOutputGainForTesting, 0.4, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, Float(sqrt(0.5)), accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[1].gain, Float(sqrt(0.5)), accuracy: 0.0001)

        host.setLiveCrossfaderOverride(1)

        XCTAssertEqual(graph.masterOutputGainForTesting, 0.4, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, 0, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[1].gain, 1, accuracy: 0.0001)
        XCTAssertEqual(host.appliedState.masterOutputGain, 0.4)
        XCTAssertEqual(host.appliedState.abSelection?.crossfader, 0.5)
        XCTAssertEqual(host.resolvedState.abSelection?.crossfader, 1)
    }

    @MainActor
    func test_liveMacroOverrideUpdatesExistingNodeWithoutReapply() throws {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        host.attach(to: graph)
        let insert = MasterBusInsert(name: "Filter", kind: .nativeFilter(.default))
        let macro = MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: insert.id))
        let scene = MasterBusScene(name: "Filter", inserts: [insert], macroBindings: [macro])

        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))
        let eqBefore = try XCTUnwrap(graph.masterBranchesForTesting.first?.nodes.first as? AVAudioUnitEQ)

        host.setSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: 2_000)

        let eqAfter = try XCTUnwrap(graph.masterBranchesForTesting.first?.nodes.first as? AVAudioUnitEQ)
        XCTAssertTrue(eqBefore === eqAfter)
        XCTAssertEqual(host.applyCallCount, 1)
        XCTAssertEqual(eqAfter.bands[0].frequency, 2_000, accuracy: 0.0001)
        XCTAssertEqual(host.appliedState.activeScene.inserts[0].kind.summary, "12000 Hz")
        XCTAssertEqual(host.resolvedState.activeScene.inserts[0].kind.summary, "2000 Hz")
    }

    @MainActor
    func test_liveCrossfaderOverrideUpdatesBranchGainsWithoutReapply() {
        let graph = MainAudioGraph()
        let host = MasterBusHost()
        let sceneA = MasterBusScene(name: "A")
        let sceneB = MasterBusScene(name: "B")
        host.attach(to: graph)
        host.apply(MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(sceneAID: sceneA.id, sceneBID: sceneB.id, crossfader: 0)
        ))

        host.setLiveCrossfaderOverride(1)

        XCTAssertEqual(host.applyCallCount, 1)
        XCTAssertEqual(graph.masterBranchesForTesting[0].gain, 0, accuracy: 0.0001)
        XCTAssertEqual(graph.masterBranchesForTesting[1].gain, 1, accuracy: 0.0001)
        XCTAssertEqual(host.appliedState.abSelection?.crossfader, 0)
        XCTAssertEqual(host.resolvedState.abSelection?.crossfader, 1)
    }

    @MainActor
    func test_auParameterMacroWritesLiveEffectWithoutReapply() throws {
        let graph = MainAudioGraph()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let factory = AUAudioUnitFactory { _, completion in
            DispatchQueue.main.async {
                completion(eq, nil)
            }
        }
        let host = MasterBusHost(factory: factory)
        host.attach(to: graph)
        let insert = MasterBusInsert(name: "EQ", kind: .auEffect(componentID: AudioEffectChoice.testEffect.audioComponentID, stateBlob: nil))
        let macro = MasterSceneMacroBinding(
            slotIndex: 0,
            target: .auParameter(
                insertID: insert.id,
                address: 3000,
                identifier: "3000",
                displayName: "Frequency",
                minValue: 10,
                maxValue: 20_000,
                defaultValue: 440,
                unit: "Hz"
            ),
            authoredValue: 2_000
        )
        let scene = MasterBusScene(name: "AU", inserts: [insert], macroBindings: [macro])

        host.apply(MasterBusState(scenes: [scene], activeSceneID: scene.id))
        waitUntil(timeout: 1) {
            host.currentAUEffect(insertID: insert.id) != nil
        }
        let param = try XCTUnwrap(eq.auAudioUnit.parameterTree?.parameter(withAddress: 3000))

        XCTAssertEqual(param.value, 2_000, accuracy: 0.0001)
        XCTAssertEqual(host.auEffectParameterReadout(insertID: insert.id)?.contains { $0.address == 3000 }, true)

        host.setSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: 4_000)

        XCTAssertEqual(param.value, 4_000, accuracy: 0.0001)
        XCTAssertEqual(host.applyCallCount, 1)
        XCTAssertEqual(host.appliedState.activeScene.macroBindings[0].value(in: host.appliedState.activeScene), 2_000)
        XCTAssertEqual(host.resolvedState.activeScene.macroBindings[0].value(in: host.resolvedState.activeScene), 4_000)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}
