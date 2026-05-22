import XCTest
@testable import SequencerAI

final class EngineControllerScenePerformTests: XCTestCase {
    func test_effectiveCrossfaderReturnsPersistedCrossfaderWhenNoLiveOverrideExists() {
        let controller = EngineController(client: nil, endpoint: nil)
        let sceneA = MasterBusScene(name: "A")
        let sceneB = MasterBusScene(name: "B")
        controller.apply(masterBus: MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(sceneAID: sceneA.id, sceneBID: sceneB.id, crossfader: 0.37)
        ))

        XCTAssertEqual(controller.effectiveCrossfader, 0.37, accuracy: 0.000_001)
    }

    func test_effectiveCrossfaderReturnsLiveOverrideWhenSet() {
        let controller = EngineController(client: nil, endpoint: nil)
        let sceneA = MasterBusScene(name: "A")
        let sceneB = MasterBusScene(name: "B")
        controller.apply(masterBus: MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(sceneAID: sceneA.id, sceneBID: sceneB.id, crossfader: 0.12)
        ))

        controller.setLiveMasterCrossfader(0.88)

        XCTAssertEqual(controller.effectiveCrossfader, 0.88, accuracy: 0.000_001)
    }

    func test_scenePerformDominanceDerivesFromEffectiveCrossfader() {
        let cases: [(value: Double, isADominant: Bool, isBDominant: Bool)] = [
            (0.0, true, false),
            (0.5, false, false),
            (1.0, false, true)
        ]

        for testCase in cases {
            let dominance = ScenePerformDominance(effectiveCrossfader: testCase.value)
            XCTAssertEqual(dominance.isADominant, testCase.isADominant, "A dominance for \(testCase.value)")
            XCTAssertEqual(dominance.isBDominant, testCase.isBDominant, "B dominance for \(testCase.value)")
        }
    }
}
