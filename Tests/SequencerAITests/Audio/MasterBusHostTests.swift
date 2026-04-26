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
}
