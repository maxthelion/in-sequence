import XCTest
@testable import SequencerAI

final class MixerMasterOutputTests: XCTestCase {
    func test_masterOutputLayoutUsesFixedColumnAtNormalWidths() {
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 540),
            .fullColumn(width: 190)
        )
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 900),
            .fullColumn(width: 190)
        )
    }

    func test_masterOutputLayoutUsesCompactStripBelowBreakpoint() {
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 539.5),
            .compactStrip(width: 44)
        )
        XCTAssertTrue(MasterOutputColumnLayout.presentation(for: 320).usesCompactOverlay)
    }

    func test_masterOutputInsertsUseMasterBusChainNotDominantScene() {
        let sceneAID = UUID()
        let sceneBID = UUID()
        let sceneA = MasterBusScene(id: sceneAID, name: "Intro", inserts: [.filter()])
        let sceneB = MasterBusScene(id: sceneBID, name: "Break", inserts: [.bitcrusher()])
        var masterBus = MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneAID,
            abSelection: MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneBID, crossfader: 1)
        )

        masterBus.addMasterInsert(.filter())

        XCTAssertEqual(masterBus.masterInserts.count, 1)
        XCTAssertEqual(masterBus.scene(id: sceneAID)?.inserts.count, 1)
        XCTAssertEqual(masterBus.scene(id: sceneBID)?.inserts.count, 1)
    }

    func test_masterOutputGainScaleKeepsUnityNearApprovedFaderThrow() {
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: 1), 2, accuracy: 0.0001)
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: MasterOutputGainScale.unityPosition), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(MasterOutputGainScale.unityPosition, 0.75)
        XCTAssertLessThan(MasterOutputGainScale.unityPosition, 0.80)
        XCTAssertEqual(MasterOutputGainScale.dbLabel(forGain: 1), "0 dB")
        XCTAssertEqual(MasterOutputGainScale.dbLabel(forGain: 0), "-inf")
    }

    func test_meterScaleAndClipActionReflectTransientDisplayState() {
        let state = MasterMeterDisplayState(
            leftPeakDBFS: -12,
            rightPeakDBFS: -6,
            leftPeakHoldDBFS: -9,
            rightPeakHoldDBFS: -3,
            isClipLatched: true
        )

        XCTAssertGreaterThan(MasterMeterLevelScale.normalized(state.rightPeakDBFS), MasterMeterLevelScale.normalized(state.leftPeakDBFS))
        XCTAssertTrue(state.isClearClipActionable)
        XCTAssertEqual(MasterMeterLevelScale.normalized(MasterMeterDisplayState.silenceDBFS), 0)
        XCTAssertEqual(MasterMeterLevelScale.normalized(3), 1)
    }
}
